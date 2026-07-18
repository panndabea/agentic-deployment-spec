# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require "yaml"

require_relative "../plan"
require_relative "../processor"

module Ads
  module Adapters
    class Error < StandardError; end
    class OutputConflict < Error; end

    module Common
      module_function

      def plan_hash(plan)
        case plan
        when Ads::Plan
          plan.to_h
        when Hash
          plan
        else
          raise Error, "Adapter requires an Ads::Plan object or parsed plan JSON."
        end
      end

      def validate_plan!(plan, expected_profile)
        data = plan_hash(plan)
        raise Error, "Plan kind must be ADSDeploymentPlan." unless data["kind"] == "ADSDeploymentPlan"
        raise Error, "Plan apiVersion must be ads.dev/v1." unless data["apiVersion"] == "ads.dev/v1"
        raise Error, "Plan target profile must be #{expected_profile}." unless data.dig("target", "profile") == expected_profile

        errors = (data["diagnostics"] || []).select { |diagnostic| diagnostic["severity"] == "error" }
        raise Error, "Plan contains blocking diagnostics." unless errors.empty?

        data
      end

      def write_bundle(output_dir)
        if File.exist?(output_dir)
          entries = Dir.children(output_dir)
          raise OutputConflict, "Output directory #{output_dir} is not empty." unless entries.empty?
        end

        parent = File.dirname(File.expand_path(output_dir))
        FileUtils.mkdir_p(parent)
        tmp = Dir.mktmpdir(".ads-", parent)
        artifacts = []

        begin
          artifacts = yield tmp
          FileUtils.rmdir(output_dir) if Dir.exist?(output_dir)
          FileUtils.mv(tmp, output_dir)
          tmp = nil
          artifacts.map { |artifact| File.join(output_dir, artifact) }
        ensure
          FileUtils.rm_rf(tmp) if tmp && Dir.exist?(tmp)
        end
      end

      def write_json(path, data)
        File.write(path, "#{JSON.pretty_generate(data)}\n")
      end

      def write_yaml(path, data)
        File.write(path, YAML.dump(data))
      end

      def write_yaml_documents(path, documents)
        body = documents.map { |document| YAML.dump(document).sub(/\A---\n/, "") }.join("---\n")
        File.write(path, body)
      end

      def labels(plan, extra = {})
        metadata = plan["metadata"] || {}
        {
          "app.kubernetes.io/name" => normalize_label(metadata["name"]),
          "app.kubernetes.io/managed-by" => "ads-reference-processor",
          "ads.dev/target-profile" => normalize_label(plan.dig("target", "profile"))
        }.merge(extra)
      end

      def normalize_label(value)
        Processor.normalize_resource_name(value.to_s)
      end

      def namespace(plan)
        Processor.normalize_resource_name(plan.dig("metadata", "name"))
      end

      def env_name(secret_name)
        secret_name.to_s.upcase.gsub(/[^A-Z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
      end

      def env_name_from_secret(secret)
        ref = secret.dig("binding", "ref")
        return ref.delete_prefix("env:") if ref.is_a?(String) && ref.start_with?("env:")

        env_name(secret["name"])
      end

      def secret_applies_to_component?(secret, component_name)
        scoped = Processor.string_or_list(secret["for"]).select { |entry| entry.is_a?(String) }
        scoped.empty? || scoped.include?(component_name)
      end
    end
  end
end
