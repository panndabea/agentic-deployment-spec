# frozen_string_literal: true

require_relative "plan"
require_relative "processor"

module Ads
  module Planner
    ACTION_CONCERN_ORDER = %w[
      validate-schema
      resolve-target-context
      normalize-component
      resolve-secret-binding
      prepare-runtime-component
      configure-service
      configure-ingress
      configure-internal-traffic
      configure-egress-policy
      configure-security-policy
      configure-observability-sink
      configure-approval-gate
      verify-supply-chain
      apply-reliability-policy
    ].freeze

    module_function

    def plan(validation_result)
      raise ArgumentError, "ValidationResult blocks planning." if validation_result.blocking?

      document = validation_result.document
      context = validation_result.context
      components = normalized_components(document)
      actions = plan_actions(document, context, components, validation_result.target_profile)

      Plan.new(
        Processor.redact_secret_values(
          {
            "apiVersion" => "ads.dev/v1",
            "kind" => "ADSDeploymentPlan",
            "planVersion" => 1,
            "metadata" => metadata(document),
            "source" => source(validation_result, document),
            "target" => target(context),
            "components" => components,
            "capabilities" => capabilities(document),
            "secrets" => secrets(document, context),
            "networking" => networking(document, context),
            "security" => security(document, context),
            "approvals" => approvals(document, context),
            "observability" => observability(document, context),
            "supplyChain" => supply_chain(document, context),
            "reliability" => reliability(document),
            "actions" => actions,
            "diagnostics" => validation_result.warnings
          }
        )
      )
    end

    def metadata(document)
      source = Processor.dig_hash(document, "metadata") || {}
      {
        "name" => source["name"],
        "owner" => source["owner"],
        "labels" => source["labels"].is_a?(Hash) ? ordered_hash(source["labels"]) : {},
        "annotations" => source["annotations"].is_a?(Hash) ? ordered_hash(source["annotations"]) : {}
      }
    end

    def source(validation_result, document)
      {
        "file" => validation_result.file,
        "contextFile" => validation_result.context_file,
        "documentKind" => document["kind"],
        "documentApiVersion" => document["apiVersion"]
      }
    end

    def target(context)
      {
        "profile" => Processor.target_profile(context),
        "capabilities" => {
          "supported" => Processor.context_capability_names(context).sort,
          "secretBindings" => Processor.context_secret_binding_names(context).sort,
          "egressDestinations" => Processor.context_egress_destinations(context).sort,
          "defaultDenyEgress" => Processor.context_default_deny_egress_available?(context)
        }
      }
    end

    def ordered_hash(hash)
      hash.keys.map(&:to_s).sort.each_with_object({}) do |key, ordered|
        ordered[key] = hash[key]
      end
    end

    def redact_hash(hash)
      Processor.redact_secret_values(hash || {})
    end

    def runtime_components(document)
      components = Processor.dig_hash(document, "runtime", "components")
      components.is_a?(Array) ? components : []
    end

    def topologically_sorted_components(document)
      components = runtime_components(document)
      by_name = {}
      components.each_with_index do |component, index|
        next unless component.is_a?(Hash) && component["name"].is_a?(String)

        by_name[component["name"]] = [component, index]
      end

      visited = {}
      sorted = []
      visit = lambda do |name|
        return if visited[name]

        visited[name] = true
        component, = by_name[name]
        Processor.string_or_list(component["dependsOn"]).each do |dependency|
          visit.call(dependency) if by_name.key?(dependency)
        end
        sorted << by_name[name]
      end

      components.each do |component|
        visit.call(component["name"]) if component.is_a?(Hash) && component["name"].is_a?(String)
      end

      sorted
    end

    def normalized_components(document)
      topologically_sorted_components(document).map do |component, index|
        entry = {
          "name" => component["name"],
          "resourceName" => Processor.normalize_resource_name(component["name"]),
          "type" => component["type"]
        }
        entry["image"] = component["image"] if component.key?("image")
        entry["externalRef"] = component["externalRef"] if component.key?("externalRef")
        entry.merge!(
          "execution" => redact_hash(component["execution"] || {}),
          "ports" => redact_hash(component["ports"] || []),
          "dependsOn" => Processor.string_or_list(component["dependsOn"]).select { |name| name.is_a?(String) },
          "state" => redact_hash(component["state"] || {}),
          "resources" => redact_hash(component["resources"] || {}),
          "health" => redact_hash(component["health"] || {}),
          "scaling" => redact_hash(component["scaling"] || {}),
          "config" => redact_hash(component["config"] || {}),
          "sourcePath" => "$.runtime.components[#{index}]"
        )
        entry
      end
    end

    def capabilities(document)
      {
        "required" => normalize_capability_list(Processor.dig_hash(document, "capabilities", "required"), "$.capabilities.required"),
        "optional" => normalize_capability_list(Processor.dig_hash(document, "capabilities", "optional"), "$.capabilities.optional")
      }
    end

    def normalize_capability_list(entries, base_path)
      return [] unless entries.is_a?(Array)

      entries.each_with_index.map do |entry, index|
        case entry
        when String
          {
            "name" => entry,
            "sourcePath" => "#{base_path}[#{index}]"
          }
        when Hash
          normalized = {
            "name" => entry["name"]
          }
          scoped = Processor.string_or_list(entry["for"]).select { |value| value.is_a?(String) }
          normalized["for"] = scoped unless scoped.empty?
          normalized["level"] = entry["level"] if entry.key?("level")
          normalized["reason"] = entry["reason"] if entry.key?("reason")
          normalized["sourcePath"] = "#{base_path}[#{index}]"
          normalized
        end
      end.compact
    end

    def secrets(document, context)
      required = Processor.dig_hash(document, "secrets", "required")
      return [] unless required.is_a?(Array)

      required.each_with_index.map do |secret, index|
        name = secret["name"]
        binding, binding_path = Processor.secret_binding_for(context, name)
        ordered_secret = {}
        %w[name purpose rotation source injection reload for].each do |key|
          ordered_secret[key] = secret[key] if secret.key?(key)
        end
        secret.keys.map(&:to_s).sort.each do |key|
          next if ordered_secret.key?(key)

          ordered_secret[key] = secret[key]
        end
        ordered_secret["binding"] = Processor.redacted_secret_binding(binding)
        ordered_secret["bindingAvailable"] = !binding.nil?
        ordered_secret["sourcePath"] = "$.secrets.required[#{index}]"
        ordered_secret["bindingSourcePath"] = binding_path if binding_path
        Processor.redact_secret_values(ordered_secret)
      end
    end

    def networking(document, context)
      {
        "ingress" => redact_hash(Processor.dig_hash(document, "networking", "ingress") || {}),
        "internalTraffic" => redact_hash(Processor.dig_hash(document, "networking", "internalTraffic") || {}),
        "egress" => redact_hash(Processor.dig_hash(document, "networking", "egress") || {}),
        "outbound" => redact_hash(Processor.dig_hash(document, "security", "outbound") || {}),
        "defaultDeny" => Processor.default_deny_egress_path(document) ? true : false,
        "target" => {
          "defaultDenyEgress" => Processor.context_default_deny_egress_available?(context),
          "allowedDestinations" => Processor.context_egress_destinations(context).sort
        }
      }
    end

    def security(document, context)
      {
        "sandbox" => document.dig("security", "defaultSandbox"),
        "outbound" => redact_hash(Processor.dig_hash(document, "security", "outbound") || {}),
        "toolPolicy" => redact_hash(Processor.dig_hash(document, "security", "toolPolicy") || {}),
        "identity" => redact_hash(Processor.dig_hash(document, "security", "identity") || {}),
        "trustBoundaries" => redact_hash(Processor.dig_hash(document, "security", "trustBoundaries") || []),
        "threatModel" => redact_hash(Processor.dig_hash(document, "security", "threatModel") || {}),
        "hardening" => redact_hash(Processor.dig_hash(document, "security", "hardening") || {}),
        "target" => {
          "sandbox" => redact_hash(Processor.dig_hash(context, "security", "sandbox") || {}),
          "toolPolicy" => redact_hash(Processor.dig_hash(context, "security", "toolPolicy") || {})
        }
      }
    end

    def approvals(document, context)
      {
        "required" => redact_hash(Processor.dig_hash(document, "approvals", "required") || []),
        "policyDecisionPoints" => redact_hash(Processor.dig_hash(document, "approvals", "policyDecisionPoints") || []),
        "targetHandlers" => redact_hash(Processor.dig_hash(context, "approvals", "handlers") || {}),
        "targetPolicyDecisionPoints" => redact_hash(Processor.dig_hash(context, "approvals", "policyDecisionPoints") || {})
      }
    end

    def observability(document, context)
      {
        "traces" => redact_hash(Processor.dig_hash(document, "observability", "traces") || {}),
        "metrics" => redact_hash(Processor.dig_hash(document, "observability", "metrics") || {}),
        "logs" => redact_hash(Processor.dig_hash(document, "observability", "logs") || {}),
        "auditEvents" => redact_hash(Processor.dig_hash(document, "observability", "auditEvents") || {}),
        "targetSinks" => redact_hash(Processor.dig_hash(context, "observability") || {})
      }
    end

    def supply_chain(document, context)
      {
        "requirements" => redact_hash(document["supplyChain"] || {}),
        "targetControls" => redact_hash(context["supplyChain"] || {})
      }
    end

    def reliability(document)
      redact_hash(document["reliability"] || {})
    end

    def add_action(actions, type:, requirement:, source_path:, target_profile:, component: nil, notes: nil)
      action = {
        "type" => type,
        "status" => "planned",
        "requirement" => requirement,
        "sourcePath" => source_path,
        "targetProfile" => target_profile
      }
      action["component"] = component if component
      action["notes"] = notes if notes
      actions << action
    end

    def plan_actions(document, context, components, target_profile)
      actions = []
      add_action(actions, type: "validate-schema", requirement: "ADS document satisfies structural and conformance validation.", source_path: "$", target_profile: target_profile)
      add_action(actions, type: "resolve-target-context", requirement: "Target context #{target_profile} is compatible.", source_path: "$", target_profile: target_profile)

      components.each do |component|
        add_action(actions, type: "normalize-component", requirement: component["name"], source_path: component["sourcePath"], target_profile: target_profile, component: component["name"])
        next if component.key?("externalRef") && !component.key?("image")

        add_action(actions, type: "prepare-runtime-component", requirement: component["type"], source_path: component["sourcePath"], target_profile: target_profile, component: component["name"])
        unless component["ports"].empty?
          add_action(actions, type: "configure-service", requirement: "ports", source_path: "#{component["sourcePath"]}.ports", target_profile: target_profile, component: component["name"])
        end
      end

      secrets(document, context).each do |secret|
        add_action(actions, type: "resolve-secret-binding", requirement: secret["name"], source_path: secret["sourcePath"], target_profile: target_profile)
      end

      ingress = Processor.dig_hash(document, "networking", "ingress")
      add_action(actions, type: "configure-ingress", requirement: "ingress", source_path: "$.networking.ingress", target_profile: target_profile) if Processor.provided?(ingress)

      internal = Processor.dig_hash(document, "networking", "internalTraffic")
      add_action(actions, type: "configure-internal-traffic", requirement: "internalTraffic", source_path: "$.networking.internalTraffic", target_profile: target_profile) if Processor.provided?(internal)

      if Processor.provided?(Processor.dig_hash(document, "security", "outbound")) || Processor.provided?(Processor.dig_hash(document, "networking", "egress"))
        add_action(actions, type: "configure-egress-policy", requirement: "egress", source_path: Processor.default_deny_egress_path(document) || "$.networking.egress", target_profile: target_profile)
      end

      add_action(actions, type: "configure-security-policy", requirement: "security", source_path: "$.security", target_profile: target_profile)

      %w[traces metrics auditEvents logs].each do |signal|
        value = Processor.dig_hash(document, "observability", signal)
        add_action(actions, type: "configure-observability-sink", requirement: signal, source_path: "$.observability.#{signal}", target_profile: target_profile) if Processor.provided?(value)
      end

      approvals = Processor.dig_hash(document, "approvals", "required")
      if approvals.is_a?(Array)
        approvals.each_with_index do |approval, index|
          next unless approval.is_a?(Hash)

          add_action(actions, type: "configure-approval-gate", requirement: approval["action"], source_path: "$.approvals.required[#{index}]", target_profile: target_profile)
        end
      end

      supply = document["supplyChain"]
      add_action(actions, type: "verify-supply-chain", requirement: "supplyChain", source_path: "$.supplyChain", target_profile: target_profile) if Processor.provided?(supply)

      add_action(actions, type: "apply-reliability-policy", requirement: "reliability", source_path: "$.reliability", target_profile: target_profile) if Processor.provided?(document["reliability"])

      order_actions(actions)
    end

    def order_actions(actions)
      actions.sort_by do |action|
        [
          ACTION_CONCERN_ORDER.index(action["type"]) || ACTION_CONCERN_ORDER.length,
          action["component"].to_s,
          action["requirement"].to_s,
          action["sourcePath"].to_s
        ]
      end
    end
  end
end
