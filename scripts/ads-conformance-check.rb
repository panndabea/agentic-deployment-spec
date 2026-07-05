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
STATEFUL_MODES = %w[checkpointed durable-session durable-shared].freeze

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

def dig_hash(value, *keys)
  keys.reduce(value) do |current, key|
    return nil unless current.is_a?(Hash)

    current[key]
  end
end

def required_capability_names(document)
  required = dig_hash(document, "capabilities", "required")
  return [] unless required.is_a?(Array)

  required.map do |entry|
    case entry
    when String
      entry
    when Hash
      entry["name"]
    end
  end.compact
end

def component_names(document)
  components = dig_hash(document, "runtime", "components")
  return [] unless components.is_a?(Array)

  components.map do |component|
    component["name"] if component.is_a?(Hash)
  end.compact
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

def check_document(document)
  diagnostics = []

  check_minimal_structure(document, diagnostics)
  check_unknown_root_fields(document, diagnostics)
  check_component_references(document, diagnostics)
  check_scoped_component_references(document, diagnostics)
  check_capability_recommendations(document, diagnostics)
  check_network_consistency(document, diagnostics)
  check_extensions(document, diagnostics)

  diagnostics
end

options = {
  format: "text",
  strict_warnings: false
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: ruby scripts/ads-conformance-check.rb [options] FILE..."

  opts.on("--format FORMAT", "Output format: text or json") do |format|
    options[:format] = format
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

unless %w[text json].include?(options[:format])
  warn "Unsupported format #{options[:format].inspect}; expected text or json."
  exit 2
end

results = []

ARGV.each do |path|
  begin
    document = load_yaml(path)
    diagnostics = check_document(document)
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

case options[:format]
when "json"
  puts JSON.pretty_generate(results)
else
  results.each do |result|
    if result["diagnostics"].empty?
      puts "#{result["file"]}: ok"
      next
    end

    result["diagnostics"].each do |diagnostic|
      puts [
        result["file"],
        diagnostic["severity"],
        diagnostic["category"],
        diagnostic["path"],
        diagnostic["message"]
      ].join(": ")
    end
  end
end

has_errors = results.any? do |result|
  result["diagnostics"].any? { |diagnostic| diagnostic["severity"] == "error" }
end

has_warnings = results.any? do |result|
  result["diagnostics"].any? { |diagnostic| diagnostic["severity"] == "warning" }
end

exit(has_errors || (options[:strict_warnings] && has_warnings) ? 1 : 0)
