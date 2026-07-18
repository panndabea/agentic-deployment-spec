# frozen_string_literal: true

require_relative "common"

module Ads
  module Adapters
    module Compose
      SUPPORTED_PROFILE = "compose-single-host"
      STATEFUL_MODES = %w[checkpointed durable-session durable-shared].freeze

      module_function

      def emit(plan, output_dir)
        data = Common.validate_plan!(plan, SUPPORTED_PROFILE)

        Common.write_bundle(output_dir) do |directory|
          Common.write_yaml(File.join(directory, "compose.yaml"), compose_manifest(data))
          Common.write_json(File.join(directory, "ads-plan.json"), data)
          File.write(File.join(directory, "README.md"), readme(data))
          %w[compose.yaml ads-plan.json README.md]
        end
      end

      def compose_manifest(plan)
        manifest = {
          "services" => services(plan)
        }
        volumes = named_volumes(plan)
        manifest["volumes"] = volumes unless volumes.empty?
        manifest["x-ads-requirements"] = ads_requirements(plan)
        manifest
      end

      def services(plan)
        image_components = plan["components"].select { |component| image_component?(component) }
        service_names = image_components.map { |component| component["name"] }

        image_components.each_with_object({}) do |component, services|
          service = {
            "image" => component["image"],
            "labels" => {
              "ads.dev/name" => plan.dig("metadata", "name"),
              "ads.dev/component" => component["name"],
              "ads.dev/source-path" => component["sourcePath"]
            }
          }

          ports = external_ports(component)
          service["ports"] = ports unless ports.empty?

          depends_on = component["dependsOn"].select { |dependency| service_names.include?(dependency) }
          service["depends_on"] = depends_on unless depends_on.empty?

          environment = secret_environment(plan, component)
          service["environment"] = environment unless environment.empty?

          mounts = state_mounts(plan, component)
          service["volumes"] = mounts unless mounts.empty?

          restart = restart_policy(plan)
          service["restart"] = restart if restart

          services[component["resourceName"]] = service
        end
      end

      def image_component?(component)
        component.key?("image")
      end

      def external_ports(component)
        component["ports"].each_with_object([]) do |port, ports|
          exposure = port["exposure"]
          next unless %w[external public ingress internet].include?(exposure)

          ports << "#{port["containerPort"]}:#{port["containerPort"]}"
        end
      end

      def secret_environment(plan, component)
        plan["secrets"].each_with_object({}) do |secret, environment|
          next unless Common.secret_applies_to_component?(secret, component["name"])

          name = Common.env_name_from_secret(secret)
          environment[name] = "${#{name}:?ADS secret #{secret["name"]} is required}"
        end
      end

      def state_mounts(plan, component)
        mode = component.dig("state", "mode")
        return [] unless STATEFUL_MODES.include?(mode)

        volume_name = state_volume_name(plan, component)
        ["#{volume_name}:/var/lib/ads/#{component["resourceName"]}"]
      end

      def named_volumes(plan)
        plan["components"].each_with_object({}) do |component, volumes|
          mode = component.dig("state", "mode")
          next unless STATEFUL_MODES.include?(mode)

          volumes[state_volume_name(plan, component)] = {
            "labels" => {
              "ads.dev/name" => plan.dig("metadata", "name"),
              "ads.dev/component" => component["name"],
              "ads.dev/source-path" => component["sourcePath"]
            }
          }
        end
      end

      def state_volume_name(plan, component)
        Processor.normalize_resource_name("#{plan.dig("metadata", "name")}-#{component["resourceName"]}-state")
      end

      def restart_policy(plan)
        policy = plan.dig("reliability", "restart")
        return nil unless policy.is_a?(String)

        case policy
        when "always", "unless-stopped", "no", "on-failure"
          policy
        end
      end

      def ads_requirements(plan)
        {
          "security" => {
            "sandbox" => plan.dig("security", "sandbox"),
            "toolPolicy" => plan.dig("security", "toolPolicy"),
            "outbound" => plan.dig("security", "outbound")
          },
          "networking" => plan["networking"],
          "approvals" => plan["approvals"],
          "observability" => plan["observability"],
          "supplyChain" => plan["supplyChain"],
          "reliability" => plan["reliability"],
          "externalComponents" => plan["components"].select { |component| component.key?("externalRef") && !component.key?("image") }.map do |component|
            {
              "name" => component["name"],
              "resourceName" => component["resourceName"],
              "externalRef" => component["externalRef"],
              "sourcePath" => component["sourcePath"]
            }
          end
        }
      end

      def readme(plan)
        lines = []
        lines << "# ADS Compose Bundle"
        lines << ""
        lines << "- ADS deployment: #{plan.dig("metadata", "name")}"
        lines << "- Target profile: #{plan.dig("target", "profile")}"
        lines << "- Source: #{plan.dig("source", "file")}"
        lines << ""
        lines << "Generated files:"
        lines << ""
        lines << "- `compose.yaml`: Compose services and externally satisfied ADS requirements."
        lines << "- `ads-plan.json`: The exact ADS deployment plan used by this adapter."
        lines << ""
        lines << "Secret bindings are emitted as environment references only; no secret payloads are included."
        "#{lines.join("\n")}\n"
      end
    end
  end
end
