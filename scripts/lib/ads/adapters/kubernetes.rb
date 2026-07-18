# frozen_string_literal: true

require_relative "common"

module Ads
  module Adapters
    module Kubernetes
      SUPPORTED_PROFILE = "kubernetes-production"

      module_function

      def emit(plan, output_dir)
        data = Common.validate_plan!(plan, SUPPORTED_PROFILE)

        Common.write_bundle(output_dir) do |directory|
          Common.write_yaml(File.join(directory, "namespace.yaml"), namespace_manifest(data))
          Common.write_yaml_documents(File.join(directory, "deployments.yaml"), deployments(data))
          Common.write_yaml_documents(File.join(directory, "services.yaml"), services(data))
          Common.write_yaml_documents(File.join(directory, "network-policies.yaml"), network_policies(data))
          Common.write_yaml_documents(File.join(directory, "secret-bindings.yaml"), secret_bindings(data))
          Common.write_yaml_documents(File.join(directory, "observability.yaml"), observability_stubs(data))
          Common.write_yaml_documents(File.join(directory, "approvals.yaml"), approval_stubs(data))
          Common.write_yaml_documents(File.join(directory, "supply-chain-policy.yaml"), supply_chain_stubs(data))
          Common.write_json(File.join(directory, "ads-plan.json"), data)
          File.write(File.join(directory, "README.md"), readme(data))
          %w[
            namespace.yaml
            deployments.yaml
            services.yaml
            network-policies.yaml
            secret-bindings.yaml
            observability.yaml
            approvals.yaml
            supply-chain-policy.yaml
            ads-plan.json
            README.md
          ]
        end
      end

      def namespace_manifest(plan)
        {
          "apiVersion" => "v1",
          "kind" => "Namespace",
          "metadata" => {
            "name" => Common.namespace(plan),
            "labels" => Common.labels(plan, "ads.dev/name" => Common.normalize_label(plan.dig("metadata", "name"))),
            "annotations" => {
              "ads.dev/source-file" => plan.dig("source", "file")
            }
          }
        }
      end

      def image_components(plan)
        plan["components"].select { |component| component.key?("image") }
      end

      def deployments(plan)
        image_components(plan).map do |component|
          {
            "apiVersion" => "apps/v1",
            "kind" => "Deployment",
            "metadata" => resource_metadata(plan, component),
            "spec" => {
              "replicas" => replicas(component),
              "selector" => {
                "matchLabels" => selector_labels(plan, component)
              },
              "template" => {
                "metadata" => {
                  "labels" => selector_labels(plan, component),
                  "annotations" => {
                    "ads.dev/source-path" => component["sourcePath"]
                  }
                },
                "spec" => pod_spec(plan, component)
              }
            }
          }
        end
      end

      def pod_spec(plan, component)
        spec = {
          "containers" => [
            container(plan, component)
          ]
        }

        service_account = plan.dig("security", "identity", "serviceAccount")
        spec["serviceAccountName"] = service_account if service_account.is_a?(String)
        spec
      end

      def container(plan, component)
        container = {
          "name" => component["resourceName"],
          "image" => component["image"]
        }

        ports = component["ports"].map do |port|
          {
            "name" => Processor.normalize_resource_name(port["name"]),
            "containerPort" => port["containerPort"],
            "protocol" => (port["protocol"] || "TCP").upcase
          }
        end
        container["ports"] = ports unless ports.empty?

        env = secret_env(plan, component)
        container["env"] = env unless env.empty?

        container["resources"] = component["resources"] unless component["resources"].empty?

        readiness = probe(component, "readiness")
        liveness = probe(component, "liveness")
        container["readinessProbe"] = readiness if readiness
        container["livenessProbe"] = liveness if liveness

        container
      end

      def secret_env(plan, component)
        plan["secrets"].each_with_object([]) do |secret, env|
          next unless Common.secret_applies_to_component?(secret, component["name"])

          env << {
            "name" => Common.env_name_from_secret(secret),
            "valueFrom" => {
              "secretKeyRef" => {
                "name" => Processor.normalize_resource_name("#{component["resourceName"]}-#{secret["name"]}"),
                "key" => "value",
                "optional" => false
              }
            }
          }
        end
      end

      def probe(component, key)
        config = component.dig("health", key)
        return nil unless config.is_a?(Hash)

        path = config["path"]
        port = config["port"] || component.dig("ports", 0, "containerPort")
        return nil unless path && port

        {
          "httpGet" => {
            "path" => path,
            "port" => port
          },
          "initialDelaySeconds" => config["initialDelaySeconds"] || 10,
          "periodSeconds" => config["periodSeconds"] || 10
        }
      end

      def replicas(component)
        scaling = component["scaling"]
        return scaling["replicas"] if scaling.is_a?(Hash) && scaling["replicas"].is_a?(Integer)
        return scaling["minReplicas"] if scaling.is_a?(Hash) && scaling["minReplicas"].is_a?(Integer)

        1
      end

      def services(plan)
        image_components(plan).each_with_object([]) do |component, manifests|
          next if component["ports"].empty?

          manifests << {
            "apiVersion" => "v1",
            "kind" => "Service",
            "metadata" => resource_metadata(plan, component),
            "spec" => {
              "type" => service_type(component),
              "selector" => selector_labels(plan, component),
              "ports" => component["ports"].map do |port|
                {
                  "name" => Processor.normalize_resource_name(port["name"]),
                  "port" => port["containerPort"],
                  "targetPort" => port["containerPort"],
                  "protocol" => (port["protocol"] || "TCP").upcase
                }
              end
            }
          }
        end
      end

      def service_type(component)
        component["ports"].any? { |port| %w[external public ingress internet].include?(port["exposure"]) } ? "LoadBalancer" : "ClusterIP"
      end

      def network_policies(plan)
        namespace = Common.namespace(plan)
        documents = []

        if plan.dig("networking", "defaultDeny")
          documents << {
            "apiVersion" => "networking.k8s.io/v1",
            "kind" => "NetworkPolicy",
            "metadata" => {
              "name" => "#{namespace}-default-deny-egress",
              "namespace" => namespace,
              "labels" => Common.labels(plan),
              "annotations" => {
                "ads.dev/source-path" => plan.dig("networking", "outbound").empty? ? "$.networking.egress" : "$.security.outbound"
              }
            },
            "spec" => {
              "podSelector" => {},
              "policyTypes" => ["Egress"],
              "egress" => []
            }
          }
        end

        destinations = Processor.egress_allow_references(plan_document_like(plan)).map { |reference| reference["destination"] }.uniq.sort
        unless destinations.empty?
          documents << config_map(
            plan,
            "#{namespace}-egress-policy",
            "networking",
            "$.security.outbound.allow",
            {
              "defaultDeny" => plan.dig("networking", "defaultDeny").to_s,
              "allowedDestinations" => destinations.join(",")
            }
          )
        end

        documents
      end

      def plan_document_like(plan)
        {
          "security" => {
            "outbound" => plan.dig("networking", "outbound")
          },
          "networking" => {
            "egress" => plan.dig("networking", "egress")
          }
        }
      end

      def secret_bindings(plan)
        plan["secrets"].map do |secret|
          config_map(
            plan,
            "#{Common.namespace(plan)}-secret-#{Processor.normalize_resource_name(secret["name"])}",
            "secret-binding",
            secret["sourcePath"],
            {
              "name" => secret["name"],
              "purpose" => secret["purpose"],
              "source" => secret.dig("binding", "source").to_s,
              "ref" => secret.dig("binding", "ref").to_s,
              "bindingAvailable" => secret["bindingAvailable"].to_s
            }
          )
        end
      end

      def observability_stubs(plan)
        %w[traces metrics logs auditEvents].each_with_object([]) do |signal, documents|
          value = plan.dig("observability", signal)
          next unless Processor.provided?(value)

          documents << config_map(
            plan,
            "#{Common.namespace(plan)}-observability-#{Processor.normalize_resource_name(signal)}",
            "observability",
            "$.observability.#{signal}",
            {
              "signal" => signal,
              "requirement" => JSON.generate(value),
              "targetSinks" => JSON.generate(plan.dig("observability", "targetSinks", signal) || {})
            }
          )
        end
      end

      def approval_stubs(plan)
        required = plan.dig("approvals", "required") || []
        policy_decision_points = plan.dig("approvals", "policyDecisionPoints") || []
        documents = []

        required.each_with_index do |approval, index|
          documents << config_map(
            plan,
            "#{Common.namespace(plan)}-approval-#{Processor.normalize_resource_name(approval["action"] || index.to_s)}",
            "approval",
            "$.approvals.required[#{index}]",
            {
              "action" => approval["action"].to_s,
              "mode" => approval["mode"].to_s,
              "policyDecisionPointRef" => approval["policyDecisionPointRef"].to_s,
              "failureMode" => "closed"
            }
          )
        end

        policy_decision_points.each_with_index do |point, index|
          documents << config_map(
            plan,
            "#{Common.namespace(plan)}-pdp-#{Processor.normalize_resource_name(point["name"] || index.to_s)}",
            "policy-decision-point",
            "$.approvals.policyDecisionPoints[#{index}]",
            {
              "name" => point["name"].to_s,
              "engineRef" => point["engineRef"].to_s,
              "failureMode" => (point["failureMode"] || "closed").to_s
            }
          )
        end

        documents
      end

      def supply_chain_stubs(plan)
        requirements = plan.dig("supplyChain", "requirements")
        return [] unless Processor.provided?(requirements)

        [
          config_map(
            plan,
            "#{Common.namespace(plan)}-supply-chain-policy",
            "supply-chain",
            "$.supplyChain",
            {
              "requirements" => JSON.generate(requirements),
              "targetControls" => JSON.generate(plan.dig("supplyChain", "targetControls") || {})
            }
          )
        ]
      end

      def resource_metadata(plan, component)
        {
          "name" => component["resourceName"],
          "namespace" => Common.namespace(plan),
          "labels" => Common.labels(plan, "app.kubernetes.io/component" => component["resourceName"]),
          "annotations" => {
            "ads.dev/component" => component["name"],
            "ads.dev/source-path" => component["sourcePath"]
          }
        }
      end

      def selector_labels(plan, component)
        {
          "app.kubernetes.io/name" => Common.normalize_label(plan.dig("metadata", "name")),
          "app.kubernetes.io/component" => component["resourceName"]
        }
      end

      def config_map(plan, name, requirement_type, source_path, data)
        {
          "apiVersion" => "v1",
          "kind" => "ConfigMap",
          "metadata" => {
            "name" => Processor.normalize_resource_name(name),
            "namespace" => Common.namespace(plan),
            "labels" => Common.labels(plan, "ads.dev/requirement-type" => requirement_type),
            "annotations" => {
              "ads.dev/source-path" => source_path
            }
          },
          "data" => data.transform_values(&:to_s)
        }
      end

      def readme(plan)
        lines = []
        lines << "# ADS Kubernetes Bundle"
        lines << ""
        lines << "- ADS deployment: #{plan.dig("metadata", "name")}"
        lines << "- Target profile: #{plan.dig("target", "profile")}"
        lines << "- Namespace: #{Common.namespace(plan)}"
        lines << "- Source: #{plan.dig("source", "file")}"
        lines << ""
        lines << "Generated files:"
        lines << ""
        %w[
          namespace.yaml
          deployments.yaml
          services.yaml
          network-policies.yaml
          secret-bindings.yaml
          observability.yaml
          approvals.yaml
          supply-chain-policy.yaml
          ads-plan.json
        ].each do |file|
          lines << "- `#{file}`"
        end
        lines << ""
        lines << "Secret bindings are references only; no secret payloads are included."
        lines << ""
        "#{lines.join("\n")}\n"
      end
    end
  end
end
