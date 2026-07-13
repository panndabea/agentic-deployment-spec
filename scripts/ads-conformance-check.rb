#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require "yaml"

KNOWN_ROOT_FIELDS = %w[
  apiVersion
  kind
  metadata
  profiles
  runtime
  capabilities
  secrets
  security
  supplyChain
  approvals
  observability
  networking
  reliability
  extensions
].freeze

REQUIRED_ROOT_FIELDS = %w[
  apiVersion
  kind
  metadata
  runtime
  capabilities
  secrets
  security
  approvals
  observability
].freeze

NAMESPACED_NAME = /\A[A-Za-z0-9][A-Za-z0-9._-]*\/[A-Za-z0-9][A-Za-z0-9._-]*\z/.freeze
IMAGE_DIGEST = /@sha256:[A-Fa-f0-9]{64}\z/.freeze
STATEFUL_MODES = %w[checkpointed durable-session durable-shared].freeze
STANDARD_AUDIT_EVENTS = %w[
  deployment_planned
  deployment_applied
  deployment_failed
  deployment_rolled_back
  approval_requested
  approval_granted
  approval_denied
  approval_expired
  policy_evaluated
  policy_decision_recorded
  secret_resolved
  secret_rotation_due
  secret_rotation_completed
  secret_rotation_failed
  tool_call_requested
  tool_call_allowed
  tool_call_denied
  tool_call_executed
  action_executed
  egress_allowed
  egress_denied
  state_checkpoint_written
  state_restore_started
  state_restore_completed
  state_restore_failed
].freeze

DIAGNOSTIC_CATEGORY_DESCRIPTIONS = {
  "schema-invalid" => "The document violates structural schema requirements.",
  "reference-invalid" => "A component name, dependsOn, for, or scoped reference cannot be resolved.",
  "capability-unsupported" => "A required capability is not supported by the selected target context.",
  "secret-unbound" => "A required secret has no binding in the target context.",
  "approval-handler-missing" => "A required human or policy approval handler is unavailable.",
  "policy-decision-point-missing" => "A policy-based approval is missing, undeclared, or unavailable.",
  "network-unresolved" => "A required network route, destination, exposure, or egress rule cannot be resolved or enforced.",
  "security-policy-unenforceable" => "A security, sandbox, identity, hardening, outbound, or tool-policy requirement cannot be enforced.",
  "supply-chain-unverified" => "A required image digest, signature, SBOM, or provenance requirement cannot be verified or satisfied.",
  "observability-sink-missing" => "A required trace, metric, log, or audit sink is unavailable.",
  "audit-event-missing" => "A recommended audit event is missing.",
  "threat-model-incomplete" => "A production document is missing recommended threat-model coverage.",
  "extension-unsupported" => "A required extension is unknown or unsupported by the processor.",
  "processor-limitation" => "The processor or target platform cannot preserve the declared runtime model.",
  "compatibility-warning" => "A non-blocking compatibility issue was detected."
}.freeze

def add_diagnostic(diagnostics, category:, severity:, path:, message:, extra: {})
  diagnostics << {
    "category" => category,
    "severity" => severity,
    "path" => path,
    "message" => message
  }.merge(extra)
end

def load_yaml(path)
  YAML.safe_load(
    File.read(path),
    permitted_classes: [],
    permitted_symbols: [],
    aliases: false,
    filename: path
  )
rescue Errno::ENOENT => e
  raise "cannot read #{path}: #{e.message}"
rescue Psych::SyntaxError => e
  raise "invalid YAML in #{path}: #{e.message}"
end

def load_target_context(path)
  context = load_yaml(path)
  raise "target context #{path} must be a mapping." unless context.is_a?(Hash)

  context
end

def string_or_list(value)
  case value
  when nil
    []
  when Array
    value
  else
    [value]
  end
end

def names_from_collection(value)
  case value
  when nil
    []
  when String
    [value]
  when Array
    value.each_with_object([]) do |entry, names|
      case entry
      when String
        names << entry
      when Hash
        name = entry["name"]
        names << name if name.is_a?(String)
      end
    end
  when Hash
    value.keys.map(&:to_s)
  else
    []
  end
end

def provided?(value)
  case value
  when nil, false
    false
  when String, Array, Hash
    !value.empty?
  else
    true
  end
end

def dig_hash(value, *keys)
  keys.reduce(value) do |current, key|
    return nil unless current.is_a?(Hash)

    current[key]
  end
end

def capability_name(entry)
  case entry
  when String
    entry
  when Hash
    entry["name"]
  end
end

def required_capability_references(document)
  required = dig_hash(document, "capabilities", "required")
  return [] unless required.is_a?(Array)

  required.each_with_index.each_with_object([]) do |(entry, index), references|
    name = capability_name(entry)
    next unless name.is_a?(String)

    references << {
      "name" => name,
      "path" => "$.capabilities.required[#{index}]"
    }
  end
end

def required_capability_names(document)
  required_capability_references(document).map { |reference| reference["name"] }
end

def runtime_image_references(document)
  components = dig_hash(document, "runtime", "components")
  return [] unless components.is_a?(Array)

  components.each_with_index.each_with_object([]) do |(component, index), references|
    next unless component.is_a?(Hash)

    image = component["image"]
    next unless image.is_a?(String)

    references << {
      "component" => component["name"],
      "image" => image,
      "path" => "$.runtime.components[#{index}].image"
    }
  end
end

def image_digest_pinned?(image)
  image.is_a?(String) && image.match?(IMAGE_DIGEST)
end

def supply_chain_images(document)
  images = dig_hash(document, "supplyChain", "images")
  images.is_a?(Hash) ? images : {}
end

def image_signature_required?(document)
  dig_hash(document, "supplyChain", "images", "signature", "required") == true
end

def sbom_required?(document)
  dig_hash(document, "supplyChain", "images", "sbom", "required") == true
end

def provenance_required?(document)
  dig_hash(document, "supplyChain", "images", "provenance", "required") == true
end

def audit_event_name_valid?(name)
  name.is_a?(String) && (STANDARD_AUDIT_EVENTS.include?(name) || name.match?(NAMESPACED_NAME))
end

def audit_event_references(document)
  references = []

  required = dig_hash(document, "observability", "auditEvents", "required")
  if required.is_a?(Array)
    required.each_with_index do |event, index|
      references << {
        "name" => event,
        "path" => "$.observability.auditEvents.required[#{index}]"
      }
    end
  end

  approvals = dig_hash(document, "approvals", "required")
  if approvals.is_a?(Array)
    approvals.each_with_index do |approval, approval_index|
      next unless approval.is_a?(Hash)

      audit_events = approval["auditEvents"]
      next unless audit_events.is_a?(Array)

      audit_events.each_with_index do |event, event_index|
        references << {
          "name" => event,
          "path" => "$.approvals.required[#{approval_index}].auditEvents[#{event_index}]"
        }
      end
    end
  end

  references
end

def required_audit_event_names(document)
  required = dig_hash(document, "observability", "auditEvents", "required")
  return [] unless required.is_a?(Array)

  required.select { |event| event.is_a?(String) }
end

def production_document?(document)
  return false unless document.is_a?(Hash)

  labels_tier = dig_hash(document, "metadata", "labels", "tier")
  profiles = document["profiles"]

  labels_tier == "production" ||
    (profiles.is_a?(Array) && profiles.include?("kubernetes-production"))
end

def component_names(document)
  components = dig_hash(document, "runtime", "components")
  return [] unless components.is_a?(Array)

  components.map do |component|
    component["name"] if component.is_a?(Hash)
  end.compact
end

def approval_action_names(document)
  approvals = dig_hash(document, "approvals", "required")
  return [] unless approvals.is_a?(Array)

  approvals.map do |approval|
    approval["action"] if approval.is_a?(Hash)
  end.compact
end

def policy_approval_mode?(mode)
  %w[policy policy-and-human].include?(mode)
end

def policy_decision_points(document)
  points = dig_hash(document, "approvals", "policyDecisionPoints")
  points.is_a?(Array) ? points : []
end

def target_profile(context)
  return nil unless context.is_a?(Hash)

  context["targetProfile"] || context["profile"]
end

def target_context_extra(context)
  profile = target_profile(context)
  return {} unless profile

  { "targetProfile" => profile }
end

def context_capability_names(context)
  (
    names_from_collection(dig_hash(context, "capabilities", "supported")) +
    names_from_collection(dig_hash(context, "capabilities", "external")) +
    names_from_collection(dig_hash(context, "externalIntegrations", "capabilities"))
  ).uniq
end

def context_secret_binding_names(context)
  (
    names_from_collection(dig_hash(context, "secrets", "bindings")) +
    names_from_collection(dig_hash(context, "externalIntegrations", "secrets"))
  ).uniq
end

def context_approval_handler_available?(context, handler)
  handlers = dig_hash(context, "approvals", "handlers")

  case handlers
  when Array
    handlers.include?(handler)
  when Hash
    provided?(handlers[handler])
  else
    false
  end
end

def required_approval_handlers(mode)
  case mode
  when "human"
    ["human"]
  when "policy"
    ["policy"]
  when "policy-and-human"
    %w[human policy]
  else
    []
  end
end

def context_policy_decision_point_available?(context, name)
  points = dig_hash(context, "approvals", "policyDecisionPoints")

  case points
  when Array
    names_from_collection(points).include?(name) || names_from_collection(points).include?("*")
  when Hash
    provided?(points[name]) || provided?(points["*"])
  else
    false
  end
end

def context_observability_sink_available?(context, signal)
  config = dig_hash(context, "observability", signal)
  return false if config.nil? || config == false
  return true if config == true
  return provided?(config) unless config.is_a?(Hash)
  return true if config["available"] == true

  provided?(config["sink"]) || provided?(config["sinks"])
end

def context_default_deny_egress_available?(context)
  config = dig_hash(context, "network", "egress")
  return false if config.nil? || config == false
  return true if config == true
  return false unless config.is_a?(Hash)

  config["defaultDeny"] == true ||
    config["enforceDefaultDeny"] == true ||
    config["default"] == "deny"
end

def context_egress_destinations(context)
  (
    names_from_collection(dig_hash(context, "network", "egress", "allow")) +
    names_from_collection(dig_hash(context, "network", "egress", "allowedDestinations")) +
    names_from_collection(dig_hash(context, "externalIntegrations", "egress"))
  ).uniq
end

def context_egress_destination_available?(context, destination)
  destinations = context_egress_destinations(context)
  destinations.include?("*") || destinations.include?(destination)
end

def context_sandbox_level_available?(context, level)
  config = dig_hash(context, "security", "sandbox")
  return false if config.nil? || config == false
  return true if config == true

  case config
  when Array
    config.include?(level)
  when Hash
    supported = (
      names_from_collection(config["levels"]) +
      names_from_collection(config["supported"])
    ).uniq

    config["level"] == level || supported.include?(level)
  else
    false
  end
end

def context_tool_policy_default_available?(context, default)
  config = dig_hash(context, "security", "toolPolicy")
  return false if config.nil? || config == false
  return true if config == true

  case config
  when Array
    config.include?(default)
  when Hash
    supported = (
      names_from_collection(config["defaults"]) +
      names_from_collection(config["supportedDefaults"]) +
      names_from_collection(config["supported"])
    ).uniq

    config["default"] == default ||
      (default == "deny" && config["defaultDeny"] == true) ||
      supported.include?(default)
  else
    false
  end
end

def context_tool_policy_rules_available?(context)
  config = dig_hash(context, "security", "toolPolicy")
  return false if config.nil? || config == false
  return true if config == true
  return false unless config.is_a?(Hash)

  config["ruleLists"] == true ||
    config["allowlist"] == true ||
    config["denylist"] == true ||
    provided?(config["rules"])
end

def context_supply_chain_control_available?(context, control)
  config = dig_hash(context, "supplyChain", control)
  return false if config.nil? || config == false
  return true if config == true
  return false unless config.is_a?(Hash)
  return false if config["available"] == false
  return true if config["available"] == true

  provided?(config["verifiers"]) ||
    provided?(config["formats"]) ||
    provided?(config["predicateTypes"]) ||
    config["enforced"] == true
end

def context_supply_chain_values(context, control, keys)
  config = dig_hash(context, "supplyChain", control)
  return [] unless config.is_a?(Hash)

  keys.each_with_object([]) do |key, values|
    values.concat(names_from_collection(config[key]))
  end.uniq
end

def check_minimal_structure(document, diagnostics)
  unless document.is_a?(Hash)
    add_diagnostic(
      diagnostics,
      category: "schema-invalid",
      severity: "error",
      path: "$",
      message: "ADS document must be a mapping."
    )
    return
  end

  REQUIRED_ROOT_FIELDS.each do |field|
    next if document.key?(field)

    add_diagnostic(
      diagnostics,
      category: "schema-invalid",
      severity: "error",
      path: "$.#{field}",
      message: "Missing required root field #{field}."
    )
  end

  components = dig_hash(document, "runtime", "components")
  return if components.nil? || (components.is_a?(Array) && !components.empty?)

  add_diagnostic(
    diagnostics,
    category: "schema-invalid",
    severity: "error",
    path: "$.runtime.components",
    message: "runtime.components must be a non-empty list."
  )
end

def check_unknown_root_fields(document, diagnostics)
  return unless document.is_a?(Hash)

  document.each_key do |field|
    next if KNOWN_ROOT_FIELDS.include?(field)

    add_diagnostic(
      diagnostics,
      category: "compatibility-warning",
      severity: "warning",
      path: "$.#{field}",
      message: "Unknown non-extension root field #{field} should be reported as a compatibility warning."
    )
  end
end

def check_component_references(document, diagnostics)
  components = dig_hash(document, "runtime", "components")
  return unless components.is_a?(Array)

  declared = {}

  components.each_with_index do |component, index|
    next unless component.is_a?(Hash)

    name = component["name"]
    next unless name.is_a?(String)

    if declared.key?(name)
      add_diagnostic(
        diagnostics,
        category: "reference-invalid",
        severity: "error",
        path: "$.runtime.components[#{index}].name",
        message: "Component name #{name.inspect} is duplicated.",
        extra: { "component" => name }
      )
    else
      declared[name] = index
    end
  end

  components.each_with_index do |component, component_index|
    next unless component.is_a?(Hash)

    depends_on = component["dependsOn"]
    next unless depends_on.is_a?(Array)

    depends_on.each_with_index do |dependency, dependency_index|
      next if declared.key?(dependency)

      add_diagnostic(
        diagnostics,
        category: "reference-invalid",
        severity: "error",
        path: "$.runtime.components[#{component_index}].dependsOn[#{dependency_index}]",
        message: "dependsOn reference #{dependency.inspect} does not match a declared component.",
        extra: { "component" => component["name"] }
      )
    end
  end
end

def check_scoped_component_references(document, diagnostics)
  declared = component_names(document)

  secrets = dig_hash(document, "secrets", "required")
  if secrets.is_a?(Array)
    secrets.each_with_index do |secret, secret_index|
      next unless secret.is_a?(Hash)

      string_or_list(secret["for"]).each_with_index do |component, ref_index|
        next if declared.include?(component)

        add_diagnostic(
          diagnostics,
          category: "reference-invalid",
          severity: "error",
          path: "$.secrets.required[#{secret_index}].for[#{ref_index}]",
          message: "Secret #{secret["name"].inspect} references undeclared component #{component.inspect}.",
          extra: { "component" => component }
        )
      end
    end
  end

  %w[required optional].each do |capability_scope|
    capabilities = dig_hash(document, "capabilities", capability_scope)
    next unless capabilities.is_a?(Array)

    capabilities.each_with_index do |capability, capability_index|
      next unless capability.is_a?(Hash) && capability.key?("for")

      string_or_list(capability["for"]).each_with_index do |component, ref_index|
        next if declared.include?(component)

        add_diagnostic(
          diagnostics,
          category: "reference-invalid",
          severity: "error",
          path: "$.capabilities.#{capability_scope}[#{capability_index}].for[#{ref_index}]",
          message: "Capability #{capability["name"].inspect} references undeclared component #{component.inspect}.",
          extra: { "component" => component, "capability" => capability["name"] }
        )
      end
    end
  end
end

def check_policy_decision_points(document, diagnostics)
  declared_points = {}

  policy_decision_points(document).each_with_index do |point, index|
    next unless point.is_a?(Hash)

    name = point["name"]
    next unless name.is_a?(String)

    if declared_points.key?(name)
      add_diagnostic(
        diagnostics,
        category: "reference-invalid",
        severity: "error",
        path: "$.approvals.policyDecisionPoints[#{index}].name",
        message: "Policy decision point name #{name.inspect} is duplicated.",
        extra: { "policyDecisionPoint" => name }
      )
    else
      declared_points[name] = index
    end
  end

  declared_actions = approval_action_names(document)
  policy_decision_points(document).each_with_index do |point, point_index|
    next unless point.is_a?(Hash)

    applies_to = point["appliesTo"]
    next if applies_to.nil?

    string_or_list(applies_to).each_with_index do |action, action_index|
      next if declared_actions.include?(action)

      path = applies_to.is_a?(Array) ? "$.approvals.policyDecisionPoints[#{point_index}].appliesTo[#{action_index}]" : "$.approvals.policyDecisionPoints[#{point_index}].appliesTo"
      add_diagnostic(
        diagnostics,
        category: "policy-decision-point-missing",
        severity: "warning",
        path: path,
        message: "Policy decision point #{point["name"].inspect} appliesTo action #{action.inspect} should reference a declared approval action.",
        extra: { "policyDecisionPoint" => point["name"], "approval" => action }
      )
    end
  end

  approvals = dig_hash(document, "approvals", "required")
  return unless approvals.is_a?(Array)

  approvals.each_with_index do |approval, index|
    next unless approval.is_a?(Hash)
    next unless policy_approval_mode?(approval["mode"])

    ref = approval["policyDecisionPointRef"]
    if ref.nil?
      next unless production_document?(document)

      add_diagnostic(
        diagnostics,
        category: "policy-decision-point-missing",
        severity: "warning",
        path: "$.approvals.required[#{index}]",
        message: "Policy approval action #{approval["action"].inspect} should reference a declared policy decision point.",
        extra: { "approval" => approval["action"] }
      )
      next
    end

    next if declared_points.key?(ref)

    add_diagnostic(
      diagnostics,
      category: "policy-decision-point-missing",
      severity: "error",
      path: "$.approvals.required[#{index}].policyDecisionPointRef",
      message: "Policy approval action #{approval["action"].inspect} references undeclared policy decision point #{ref.inspect}.",
      extra: { "approval" => approval["action"], "policyDecisionPoint" => ref }
    )
  end
end

def warn_missing_capability(diagnostics, capabilities, capability, path, message)
  return if capabilities.include?(capability)

  add_diagnostic(
    diagnostics,
    category: "compatibility-warning",
    severity: "warning",
    path: path,
    message: message,
    extra: { "capability" => capability }
  )
end

def check_capability_recommendations(document, diagnostics)
  capabilities = required_capability_names(document)

  secrets = dig_hash(document, "secrets", "required")
  if secrets.is_a?(Array) && !secrets.empty?
    warn_missing_capability(
      diagnostics,
      capabilities,
      "secret-injection",
      "$.capabilities.required",
      "Documents with required secrets should include the secret-injection required capability."
    )
  end

  components = dig_hash(document, "runtime", "components")
  if components.is_a?(Array)
    components.each_with_index do |component, index|
      next unless component.is_a?(Hash)

      state_mode = dig_hash(component, "state", "mode")
      next unless STATEFUL_MODES.include?(state_mode)

      warn_missing_capability(
        diagnostics,
        capabilities,
        "persistent-storage",
        "$.runtime.components[#{index}].state.mode",
        "State mode #{state_mode.inspect} should include the persistent-storage required capability unless the store is externally satisfied."
      )
    end
  end

  if dig_hash(document, "observability", "traces", "required") == true
    warn_missing_capability(
      diagnostics,
      capabilities,
      "trace-export",
      "$.observability.traces.required",
      "Required traces should include the trace-export required capability."
    )
  end

  metrics = dig_hash(document, "observability", "metrics", "required")
  if metrics.is_a?(Array) && !metrics.empty?
    warn_missing_capability(
      diagnostics,
      capabilities,
      "metrics-export",
      "$.observability.metrics.required",
      "Required metrics should include the metrics-export required capability."
    )
  end

  audit_events = dig_hash(document, "observability", "auditEvents", "required")
  if audit_events.is_a?(Array) && !audit_events.empty?
    warn_missing_capability(
      diagnostics,
      capabilities,
      "audit-log-export",
      "$.observability.auditEvents.required",
      "Required audit events should include the audit-log-export required capability."
    )
  end

  approval_modes = dig_hash(document, "approvals", "required")
  if approval_modes.is_a?(Array)
    modes = approval_modes.map { |approval| approval["mode"] if approval.is_a?(Hash) }.compact

    if modes.any? { |mode| %w[human policy-and-human].include?(mode) }
      warn_missing_capability(
        diagnostics,
        capabilities,
        "human-approval",
        "$.approvals.required",
        "Human approval modes should include the human-approval required capability."
      )
    end

    if modes.any? { |mode| %w[policy policy-and-human].include?(mode) }
      warn_missing_capability(
        diagnostics,
        capabilities,
        "policy-decision",
        "$.approvals.required",
        "Policy approval modes should include the policy-decision required capability."
      )
    end
  end

  outbound_default = dig_hash(document, "security", "outbound", "default")
  egress_default = dig_hash(document, "networking", "egress", "default")

  if outbound_default == "deny" || egress_default == "deny"
    warn_missing_capability(
      diagnostics,
      capabilities,
      "outbound-egress-policy",
      "$.capabilities.required",
      "Default-deny outbound or egress policy should include the outbound-egress-policy required capability."
    )
  end

  if image_signature_required?(document)
    warn_missing_capability(
      diagnostics,
      capabilities,
      "image-signature-verification",
      "$.supplyChain.images.signature.required",
      "Required image signatures should include the image-signature-verification required capability."
    )
  end
end

def check_audit_event_names(document, diagnostics)
  audit_event_references(document).each do |reference|
    name = reference["name"]
    next if audit_event_name_valid?(name)

    add_diagnostic(
      diagnostics,
      category: "schema-invalid",
      severity: "error",
      path: reference["path"],
      message: "Audit event name #{name.inspect} must be a standard ADS audit event name or a namespaced extension name."
    )
  end
end

def warn_missing_audit_event(diagnostics, declared_events, event, path, message)
  return if declared_events.include?(event)

  add_diagnostic(
    diagnostics,
    category: "audit-event-missing",
    severity: "warning",
    path: path,
    message: message,
    extra: { "auditEvent" => event }
  )
end

def warn_missing_threat_model(diagnostics, path, requirement, message)
  add_diagnostic(
    diagnostics,
    category: "threat-model-incomplete",
    severity: "warning",
    path: path,
    message: message,
    extra: { "requirement" => requirement }
  )
end

def check_audit_event_coverage(document, diagnostics)
  declared_events = required_audit_event_names(document)

  if production_document?(document)
    warn_missing_audit_event(
      diagnostics,
      declared_events,
      "deployment_planned",
      "$.observability.auditEvents.required",
      "Production documents should include the deployment_planned audit event."
    )
  end

  secrets = dig_hash(document, "secrets", "required")
  if secrets.is_a?(Array) && !secrets.empty?
    warn_missing_audit_event(
      diagnostics,
      declared_events,
      "secret_resolved",
      "$.observability.auditEvents.required",
      "Documents with required secrets should include the secret_resolved audit event."
    )
  end

  approvals = dig_hash(document, "approvals", "required")
  if approvals.is_a?(Array)
    modes = approvals.map { |approval| approval["mode"] if approval.is_a?(Hash) }.compact

    if modes.any? { |mode| %w[human policy-and-human].include?(mode) }
      %w[approval_requested approval_granted approval_denied].each do |event|
        warn_missing_audit_event(
          diagnostics,
          declared_events,
          event,
          "$.observability.auditEvents.required",
          "Documents with human approval gates should include the #{event} audit event."
        )
      end
    end

    if modes.any? { |mode| %w[policy policy-and-human].include?(mode) }
      warn_missing_audit_event(
        diagnostics,
        declared_events,
        "policy_decision_recorded",
        "$.observability.auditEvents.required",
        "Documents with policy approval gates should include the policy_decision_recorded audit event."
      )
    end
  end

  tool_policy_default = dig_hash(document, "security", "toolPolicy", "default")
  tool_policy_deny = dig_hash(document, "security", "toolPolicy", "deny")
  if tool_policy_default == "deny" || provided?(tool_policy_deny)
    warn_missing_audit_event(
      diagnostics,
      declared_events,
      "tool_call_denied",
      "$.observability.auditEvents.required",
      "Documents with deny-by-default tool policy or explicit tool deny rules should include the tool_call_denied audit event."
    )
  end
end

def check_threat_model_coverage(document, diagnostics)
  return unless production_document?(document)

  unless provided?(dig_hash(document, "security", "trustBoundaries"))
    warn_missing_threat_model(
      diagnostics,
      "$.security.trustBoundaries",
      "trust-boundaries",
      "Production documents should declare trust boundaries between users, agents, tools, data stores, and external services."
    )
  end

  threat_model = dig_hash(document, "security", "threatModel")
  unless threat_model.is_a?(Hash) && !threat_model.empty?
    warn_missing_threat_model(
      diagnostics,
      "$.security.threatModel",
      "threat-model",
      "Production documents should declare security.threatModel coverage for assets, actors, threats, mitigations, and review status."
    )
    return
  end

  {
    "assets" => "protected-assets",
    "actors" => "actors",
    "threats" => "threats",
    "mitigations" => "mitigations",
    "review" => "review-status"
  }.each do |field, requirement|
    next if provided?(threat_model[field])

    warn_missing_threat_model(
      diagnostics,
      "$.security.threatModel.#{field}",
      requirement,
      "Production threat models should declare #{field}."
    )
  end
end

def check_network_consistency(document, diagnostics)
  outbound_default = dig_hash(document, "security", "outbound", "default")
  egress_default = dig_hash(document, "networking", "egress", "default")
  return if outbound_default.nil? || egress_default.nil? || outbound_default == egress_default

  add_diagnostic(
    diagnostics,
    category: "network-unresolved",
    severity: "error",
    path: "$.networking.egress.default",
    message: "networking.egress.default #{egress_default.inspect} conflicts with security.outbound.default #{outbound_default.inspect}."
  )
end

def check_supply_chain_consistency(document, diagnostics)
  images = supply_chain_images(document)
  return unless images["requireDigest"] == true

  runtime_image_references(document).each do |reference|
    next if image_digest_pinned?(reference["image"])

    add_diagnostic(
      diagnostics,
      category: "supply-chain-unverified",
      severity: "error",
      path: reference["path"],
      message: "Image #{reference["image"].inspect} must be pinned by sha256 digest when supplyChain.images.requireDigest is true.",
      extra: { "component" => reference["component"] }
    )
  end
end

def check_target_capability_support(document, context, diagnostics)
  supported = context_capability_names(context)

  required_capability_references(document).each do |capability|
    name = capability["name"]
    next if supported.include?(name)

    add_diagnostic(
      diagnostics,
      category: "capability-unsupported",
      severity: "error",
      path: capability["path"],
      message: "Required capability #{name.inspect} is not supported by the target context.",
      extra: target_context_extra(context).merge("capability" => name)
    )
  end
end

def check_target_secret_bindings(document, context, diagnostics)
  bound = context_secret_binding_names(context)
  secrets = dig_hash(document, "secrets", "required")
  return unless secrets.is_a?(Array)

  secrets.each_with_index do |secret, index|
    next unless secret.is_a?(Hash)

    name = secret["name"]
    next unless name.is_a?(String)
    next if bound.include?(name)

    add_diagnostic(
      diagnostics,
      category: "secret-unbound",
      severity: "error",
      path: "$.secrets.required[#{index}].name",
      message: "Required secret #{name.inspect} has no binding in the target context.",
      extra: target_context_extra(context).merge("secret" => name)
    )
  end
end

def check_target_approval_handlers(document, context, diagnostics)
  approvals = dig_hash(document, "approvals", "required")
  return unless approvals.is_a?(Array)

  approvals.each_with_index do |approval, index|
    next unless approval.is_a?(Hash)

    required_approval_handlers(approval["mode"]).each do |handler|
      next if context_approval_handler_available?(context, handler)

      add_diagnostic(
        diagnostics,
        category: "approval-handler-missing",
        severity: "error",
        path: "$.approvals.required[#{index}].mode",
        message: "Approval action #{approval["action"].inspect} requires a #{handler} handler, but the target context does not provide one.",
        extra: target_context_extra(context).merge(
          "approval" => approval["action"],
          "handler" => handler
        )
      )
    end
  end
end

def check_target_policy_decision_points(document, context, diagnostics)
  approvals = dig_hash(document, "approvals", "required")
  return unless approvals.is_a?(Array)

  approvals.each_with_index do |approval, index|
    next unless approval.is_a?(Hash)
    next unless policy_approval_mode?(approval["mode"])

    ref = approval["policyDecisionPointRef"]
    next unless ref.is_a?(String)
    next if context_policy_decision_point_available?(context, ref)

    add_diagnostic(
      diagnostics,
      category: "policy-decision-point-missing",
      severity: "error",
      path: "$.approvals.required[#{index}].policyDecisionPointRef",
      message: "Policy decision point #{ref.inspect} is unavailable in the target context.",
      extra: target_context_extra(context).merge(
        "approval" => approval["action"],
        "policyDecisionPoint" => ref
      )
    )
  end
end

def check_target_observability_bindings(document, context, diagnostics)
  if dig_hash(document, "observability", "traces", "required") == true &&
     !context_observability_sink_available?(context, "traces")
    add_diagnostic(
      diagnostics,
      category: "observability-sink-missing",
      severity: "error",
      path: "$.observability.traces.required",
      message: "Required traces have no sink in the target context.",
      extra: target_context_extra(context).merge("signal" => "traces")
    )
  end

  metrics = dig_hash(document, "observability", "metrics", "required")
  if metrics.is_a?(Array) && !metrics.empty? &&
     !context_observability_sink_available?(context, "metrics")
    add_diagnostic(
      diagnostics,
      category: "observability-sink-missing",
      severity: "error",
      path: "$.observability.metrics.required",
      message: "Required metrics have no sink in the target context.",
      extra: target_context_extra(context).merge("signal" => "metrics")
    )
  end

  audit_events = dig_hash(document, "observability", "auditEvents", "required")
  if audit_events.is_a?(Array) && !audit_events.empty? &&
     !context_observability_sink_available?(context, "auditEvents")
    add_diagnostic(
      diagnostics,
      category: "observability-sink-missing",
      severity: "error",
      path: "$.observability.auditEvents.required",
      message: "Required audit events have no sink in the target context.",
      extra: target_context_extra(context).merge("signal" => "auditEvents")
    )
  end
end

def egress_allow_references(document)
  [
    ["$.security.outbound.allow", dig_hash(document, "security", "outbound", "allow")],
    ["$.networking.egress.allow", dig_hash(document, "networking", "egress", "allow")]
  ].each_with_object([]) do |(base_path, value), references|
    next if value.nil?

    string_or_list(value).each_with_index do |destination, index|
      next unless destination.is_a?(String)

      path = value.is_a?(Array) ? "#{base_path}[#{index}]" : base_path
      references << {
        "destination" => destination,
        "path" => path
      }
    end
  end
end

def default_deny_egress_path(document)
  return "$.security.outbound.default" if dig_hash(document, "security", "outbound", "default") == "deny"
  return "$.networking.egress.default" if dig_hash(document, "networking", "egress", "default") == "deny"

  nil
end

def check_target_network_feasibility(document, context, diagnostics)
  default_deny_path = default_deny_egress_path(document)
  if default_deny_path && !context_default_deny_egress_available?(context)
    add_diagnostic(
      diagnostics,
      category: "network-unresolved",
      severity: "error",
      path: default_deny_path,
      message: "Default-deny outbound or egress policy cannot be enforced by the target context.",
      extra: target_context_extra(context)
    )
  end

  egress_allow_references(document).each do |reference|
    destination = reference["destination"]
    next if context_egress_destination_available?(context, destination)

    add_diagnostic(
      diagnostics,
      category: "network-unresolved",
      severity: "error",
      path: reference["path"],
      message: "Egress destination #{destination.inspect} is not resolvable by the target context.",
      extra: target_context_extra(context).merge("destination" => destination)
    )
  end
end

def check_target_security_feasibility(document, context, diagnostics)
  sandbox = dig_hash(document, "security", "defaultSandbox")
  if sandbox.is_a?(String) && !context_sandbox_level_available?(context, sandbox)
    add_diagnostic(
      diagnostics,
      category: "security-policy-unenforceable",
      severity: "error",
      path: "$.security.defaultSandbox",
      message: "Sandbox level #{sandbox.inspect} cannot be enforced by the target context.",
      extra: target_context_extra(context).merge("sandbox" => sandbox)
    )
  end

  tool_policy_default = dig_hash(document, "security", "toolPolicy", "default")
  if tool_policy_default.is_a?(String) && !context_tool_policy_default_available?(context, tool_policy_default)
    add_diagnostic(
      diagnostics,
      category: "security-policy-unenforceable",
      severity: "error",
      path: "$.security.toolPolicy.default",
      message: "Tool policy default #{tool_policy_default.inspect} cannot be enforced by the target context.",
      extra: target_context_extra(context).merge("toolPolicyDefault" => tool_policy_default)
    )
  end

  tool_policy_allow = dig_hash(document, "security", "toolPolicy", "allow")
  tool_policy_deny = dig_hash(document, "security", "toolPolicy", "deny")
  return unless provided?(tool_policy_allow) || provided?(tool_policy_deny)
  return if context_tool_policy_rules_available?(context)

  add_diagnostic(
    diagnostics,
    category: "security-policy-unenforceable",
    severity: "error",
    path: "$.security.toolPolicy",
    message: "Tool policy allow or deny rules cannot be enforced by the target context.",
    extra: target_context_extra(context)
  )
end

def check_target_supply_chain_feasibility(document, context, diagnostics)
  if image_signature_required?(document)
    unless context_supply_chain_control_available?(context, "signatures")
      add_diagnostic(
        diagnostics,
        category: "supply-chain-unverified",
        severity: "error",
        path: "$.supplyChain.images.signature.required",
        message: "Required image signature verification is unavailable in the target context.",
        extra: target_context_extra(context)
      )
    end

    verifier = dig_hash(document, "supplyChain", "images", "signature", "verifier")
    supported_verifiers = context_supply_chain_values(context, "signatures", %w[verifiers supportedVerifiers])
    if verifier.is_a?(String) && !supported_verifiers.empty? && !supported_verifiers.include?(verifier)
      add_diagnostic(
        diagnostics,
        category: "supply-chain-unverified",
        severity: "error",
        path: "$.supplyChain.images.signature.verifier",
        message: "Image signature verifier #{verifier.inspect} is not supported by the target context.",
        extra: target_context_extra(context).merge("verifier" => verifier)
      )
    end
  end

  if sbom_required?(document)
    unless context_supply_chain_control_available?(context, "sbom")
      add_diagnostic(
        diagnostics,
        category: "supply-chain-unverified",
        severity: "error",
        path: "$.supplyChain.images.sbom.required",
        message: "Required SBOM availability is unavailable in the target context.",
        extra: target_context_extra(context)
      )
    end

    requested_formats = string_or_list(dig_hash(document, "supplyChain", "images", "sbom", "formats"))
    supported_formats = context_supply_chain_values(context, "sbom", %w[formats supportedFormats])
    unsupported_formats = requested_formats.select do |format|
      format.is_a?(String) && !supported_formats.empty? && !supported_formats.include?(format)
    end
    unless unsupported_formats.empty?
      add_diagnostic(
        diagnostics,
        category: "supply-chain-unverified",
        severity: "error",
        path: "$.supplyChain.images.sbom.formats",
        message: "Requested SBOM formats #{unsupported_formats.inspect} are not supported by the target context.",
        extra: target_context_extra(context).merge("formats" => unsupported_formats)
      )
    end
  end

  return unless provenance_required?(document)

  unless context_supply_chain_control_available?(context, "provenance")
    add_diagnostic(
      diagnostics,
      category: "supply-chain-unverified",
      severity: "error",
      path: "$.supplyChain.images.provenance.required",
      message: "Required build provenance is unavailable in the target context.",
      extra: target_context_extra(context)
    )
  end

  requested_predicates = string_or_list(dig_hash(document, "supplyChain", "images", "provenance", "predicateTypes"))
  supported_predicates = context_supply_chain_values(context, "provenance", %w[predicateTypes supportedPredicateTypes])
  unsupported_predicates = requested_predicates.select do |predicate|
    predicate.is_a?(String) && !supported_predicates.empty? && !supported_predicates.include?(predicate)
  end
  return if unsupported_predicates.empty?

  add_diagnostic(
    diagnostics,
    category: "supply-chain-unverified",
    severity: "error",
    path: "$.supplyChain.images.provenance.predicateTypes",
    message: "Requested provenance predicate types #{unsupported_predicates.inspect} are not supported by the target context.",
    extra: target_context_extra(context).merge("predicateTypes" => unsupported_predicates)
  )
end

def check_target_context(document, context, diagnostics)
  return unless context
  return unless document.is_a?(Hash)

  check_target_capability_support(document, context, diagnostics)
  check_target_secret_bindings(document, context, diagnostics)
  check_target_approval_handlers(document, context, diagnostics)
  check_target_policy_decision_points(document, context, diagnostics)
  check_target_observability_bindings(document, context, diagnostics)
  check_target_network_feasibility(document, context, diagnostics)
  check_target_security_feasibility(document, context, diagnostics)
  check_target_supply_chain_feasibility(document, context, diagnostics)
end

def check_extensions(document, diagnostics)
  extensions = document["extensions"] if document.is_a?(Hash)
  return if extensions.nil?
  return unless extensions.is_a?(Hash)

  extensions.each do |name, value|
    unless name.match?(NAMESPACED_NAME)
      add_diagnostic(
        diagnostics,
        category: "extension-unsupported",
        severity: "error",
        path: "$.extensions.#{name}",
        message: "Extension key #{name.inspect} must be namespaced."
      )
    end

    next unless value.is_a?(Hash) && value["required"] == true

    add_diagnostic(
      diagnostics,
      category: "extension-unsupported",
      severity: "error",
      path: "$.extensions.#{name}",
      message: "Required extension #{name.inspect} is not supported by this reference checker."
    )
  end
end

def check_document(document, context)
  diagnostics = []

  check_minimal_structure(document, diagnostics)
  check_unknown_root_fields(document, diagnostics)
  check_component_references(document, diagnostics)
  check_scoped_component_references(document, diagnostics)
  check_policy_decision_points(document, diagnostics)
  check_capability_recommendations(document, diagnostics)
  check_audit_event_names(document, diagnostics)
  check_audit_event_coverage(document, diagnostics)
  check_threat_model_coverage(document, diagnostics)
  check_network_consistency(document, diagnostics)
  check_supply_chain_consistency(document, diagnostics)
  check_target_context(document, context, diagnostics)
  check_extensions(document, diagnostics)

  diagnostics
end

def sarif_level(severity)
  case severity
  when "error"
    "error"
  when "warning"
    "warning"
  else
    "note"
  end
end

def sarif_rule(category)
  description = DIAGNOSTIC_CATEGORY_DESCRIPTIONS.fetch(category, "ADS conformance diagnostic.")

  {
    "id" => category,
    "name" => category,
    "shortDescription" => {
      "text" => description
    }
  }
end

def sarif_result(file, diagnostic)
  category = diagnostic.fetch("category")
  path = diagnostic.fetch("path", "$")
  properties = diagnostic.reject do |key, _value|
    %w[category severity path message].include?(key)
  end
  properties["adsPath"] = path

  {
    "ruleId" => category,
    "level" => sarif_level(diagnostic["severity"]),
    "message" => {
      "text" => "#{path}: #{diagnostic["message"]}"
    },
    "locations" => [
      {
        "physicalLocation" => {
          "artifactLocation" => {
            "uri" => file
          },
          "region" => {
            "startLine" => 1
          }
        }
      }
    ],
    "properties" => properties
  }
end

def sarif_document(results)
  diagnostics = results.flat_map { |result| result["diagnostics"] }
  rules = diagnostics
          .map { |diagnostic| diagnostic["category"] }
          .uniq
          .sort
          .map { |category| sarif_rule(category) }

  {
    "$schema" => "https://json.schemastore.org/sarif-2.1.0.json",
    "version" => "2.1.0",
    "runs" => [
      {
        "tool" => {
          "driver" => {
            "name" => "ADS Reference Processor",
            "rules" => rules
          }
        },
        "results" => results.flat_map do |result|
          result["diagnostics"].map { |diagnostic| sarif_result(result["file"], diagnostic) }
        end
      }
    ]
  }
end

def formatted_output(results, format)
  case format
  when "json"
    JSON.pretty_generate(results)
  when "sarif"
    JSON.pretty_generate(sarif_document(results))
  else
    results.flat_map do |result|
      if result["diagnostics"].empty?
        ["#{result["file"]}: ok"]
      else
        result["diagnostics"].map do |diagnostic|
          [
            result["file"],
            diagnostic["severity"],
            diagnostic["category"],
            diagnostic["path"],
            diagnostic["message"]
          ].join(": ")
        end
      end
    end.join("\n")
  end
end

options = {
  format: "text",
  strict_warnings: false,
  context_path: nil,
  output_path: nil
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: ruby scripts/ads-conformance-check.rb [options] FILE..."

  opts.on("--format FORMAT", "Output format: text, json, or sarif") do |format|
    options[:format] = format
  end

  opts.on("--context FILE", "Target context YAML file") do |path|
    options[:context_path] = path
  end

  opts.on("--output FILE", "Write formatted diagnostics to FILE") do |path|
    options[:output_path] = path
  end

  opts.on("--strict-warnings", "Exit non-zero when warnings are present") do
    options[:strict_warnings] = true
  end
end

parser.parse!

if ARGV.empty?
  warn parser
  exit 2
end

unless %w[text json sarif].include?(options[:format])
  warn "Unsupported format #{options[:format].inspect}; expected text, json, or sarif."
  exit 2
end

target_context = nil
if options[:context_path]
  begin
    target_context = load_target_context(options[:context_path])
  rescue StandardError => e
    warn e.message
    exit 2
  end
end

results = []

ARGV.each do |path|
  begin
    document = load_yaml(path)
    diagnostics = check_document(document, target_context)
  rescue StandardError => e
    diagnostics = []
    add_diagnostic(
      diagnostics,
      category: "schema-invalid",
      severity: "error",
      path: "$",
      message: e.message
    )
  end

  results << {
    "file" => path,
    "diagnostics" => diagnostics
  }
end

output = formatted_output(results, options[:format])

if options[:output_path]
  begin
    File.write(options[:output_path], "#{output}\n")
  rescue StandardError => e
    warn "cannot write #{options[:output_path]}: #{e.message}"
    exit 2
  end
else
  puts output
end

has_errors = results.any? do |result|
  result["diagnostics"].any? { |diagnostic| diagnostic["severity"] == "error" }
end

has_warnings = results.any? do |result|
  result["diagnostics"].any? { |diagnostic| diagnostic["severity"] == "warning" }
end

exit(has_errors || (options[:strict_warnings] && has_warnings) ? 1 : 0)
