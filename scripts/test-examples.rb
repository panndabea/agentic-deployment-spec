#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"
require "rbconfig"
require "tmpdir"
require "yaml"

REPO_ROOT = File.expand_path("..", __dir__)
RUBY = RbConfig.ruby
SCHEMA_FILE = "schemas/ads.schema.json"
EXPECTATIONS_FILE = "conformance/expectations.yaml"

def executable?(name)
  ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |directory|
    path = File.join(directory, name)
    File.file?(path) && File.executable?(path)
  end
end

def schema_command
  return ["check-jsonschema"] if executable?("check-jsonschema")
  return ["uvx", "check-jsonschema"] if executable?("uvx")

  nil
end

def run_command(label, command, expect_success: nil, expected_exit: nil, stdout_includes: [])
  stdout, stderr, status = Open3.capture3(*command)
  success = if expected_exit.nil?
              status.success? == expect_success
            else
              status.exitstatus == expected_exit
            end
  success &&= stdout_includes.all? { |text| stdout.include?(text) }

  puts "#{success ? "PASS" : "FAIL"} #{label}"

  unless success
    puts "  command: #{command.join(" ")}"
    expected = expected_exit.nil? ? (expect_success ? "success" : "failure") : "exit #{expected_exit}"
    puts "  expected: #{expected}"
    stdout_includes.each do |text|
      puts "  expected stdout to include: #{text.inspect}"
    end
    puts "  exit: #{status.exitstatus}"
    puts stdout.lines.map { |line| "  stdout: #{line}" }.join unless stdout.empty?
    puts stderr.lines.map { |line| "  stderr: #{line}" }.join unless stderr.empty?
  end

  success
end

def load_expectations
  YAML.safe_load(
    File.read(EXPECTATIONS_FILE),
    permitted_classes: [],
    permitted_symbols: [],
    aliases: false,
    filename: EXPECTATIONS_FILE
  ) || {}
rescue Errno::ENOENT => e
  warn "Missing fixture expectations file #{EXPECTATIONS_FILE}: #{e.message}"
  exit 2
rescue Psych::SyntaxError => e
  warn "Invalid YAML in #{EXPECTATIONS_FILE}: #{e.message}"
  exit 2
end

def expectation_list(expectations, *keys)
  value = keys.reduce(expectations) do |current, key|
    current.is_a?(Hash) ? current[key] : nil
  end

  return value if value.is_a?(Array)

  warn "Expected #{keys.join(".")} in #{EXPECTATIONS_FILE} to be a list."
  exit 2
end

def expectation_file(entry, key = "file")
  return entry if entry.is_a?(String)
  return entry[key] if entry.is_a?(Hash) && entry[key].is_a?(String)

  warn "Expected fixture entry in #{EXPECTATIONS_FILE} to include #{key.inspect}: #{entry.inspect}"
  exit 2
end

def expected_diagnostics(entry, required: false)
  unless entry.is_a?(Hash)
    if required
      warn "Expected fixture entry in #{EXPECTATIONS_FILE} to be a mapping with expectedDiagnostics: #{entry.inspect}"
      exit 2
    end

    return []
  end

  unless entry.key?("expectedDiagnostics")
    if required
      warn "Expected fixture entry in #{EXPECTATIONS_FILE} to include expectedDiagnostics: #{entry.inspect}"
      exit 2
    end

    return []
  end

  diagnostics = entry["expectedDiagnostics"]
  unless diagnostics.is_a?(Array)
    warn "Expected expectedDiagnostics in #{EXPECTATIONS_FILE} to be a list: #{entry.inspect}"
    exit 2
  end

  if required && diagnostics.empty?
    warn "Expected expectedDiagnostics in #{EXPECTATIONS_FILE} to include at least one substring: #{entry.inspect}"
    exit 2
  end

  unless diagnostics.all? { |diagnostic| diagnostic.is_a?(String) }
    warn "Expected expectedDiagnostics in #{EXPECTATIONS_FILE} to contain only strings: #{entry.inspect}"
    exit 2
  end

  diagnostics
end

Dir.chdir(REPO_ROOT) do
  schema = schema_command
  unless schema
    warn "Missing check-jsonschema or uvx; install one to run schema fixture tests."
    exit 2
  end

  expectations = load_expectations

  checks = []

  expectation_list(expectations, "schema", "accepts").each do |file|
    checks << run_command(
      "schema accepts #{file}",
      schema + ["--schemafile", SCHEMA_FILE, file],
      expect_success: true
    )
  end

  expectation_list(expectations, "schema", "rejects").each do |file|
    checks << run_command(
      "schema rejects #{file}",
      schema + ["--schemafile", SCHEMA_FILE, file],
      expected_exit: 1
    )
  end

  expectation_list(expectations, "conformance", "accepts").each do |file|
    checks << run_command(
      "conformance accepts #{file}",
      [RUBY, "scripts/ads-conformance-check.rb", file],
      expect_success: true
    )
  end

  expectation_list(expectations, "conformance", "rejects").each do |entry|
    file = expectation_file(entry)
    checks << run_command(
      "conformance rejects #{file}",
      [RUBY, "scripts/ads-conformance-check.rb", file],
      expected_exit: 1,
      stdout_includes: expected_diagnostics(entry, required: true)
    )
  end

  expectation_list(expectations, "conformance", "warns").each do |entry|
    file = expectation_file(entry)
    checks << run_command(
      "conformance warns #{file}",
      [RUBY, "scripts/ads-conformance-check.rb", "--strict-warnings", file],
      expected_exit: 1,
      stdout_includes: expected_diagnostics(entry, required: true)
    )
  end

  checks << run_command(
    "conformance emits SARIF diagnostics",
    [RUBY, "scripts/ads-conformance-check.rb", "--format", "sarif", "examples/conformance/invalid/duplicate-component.yaml"],
    expected_exit: 1,
    stdout_includes: [
      "\"version\": \"2.1.0\"",
      "\"name\": \"ADS Reference Processor\"",
      "\"ruleId\": \"reference-invalid\"",
      "\"adsPath\": \"$.runtime.components[1].name\""
    ]
  )

  Dir.mktmpdir("ads-conformance") do |directory|
    sarif_file = File.join(directory, "diagnostics.sarif")
    check = run_command(
      "conformance writes SARIF diagnostics",
      [
        RUBY,
        "scripts/ads-conformance-check.rb",
        "--format",
        "sarif",
        "--output",
        sarif_file,
        "examples/conformance/invalid/duplicate-component.yaml"
      ],
      expected_exit: 1
    )
    contents = File.file?(sarif_file) ? File.read(sarif_file) : ""
    check &&= contents.include?("\"version\": \"2.1.0\"")
    check &&= contents.include?("\"ruleId\": \"reference-invalid\"")
    check &&= contents.include?("\"adsPath\": \"$.runtime.components[1].name\"")

    puts "#{check ? "PASS" : "FAIL"} conformance SARIF output file content"
    checks << check
  end

  expectation_list(expectations, "targetContexts").each do |entry|
    unless entry.is_a?(Hash)
      warn "Expected targetContexts entries in #{EXPECTATIONS_FILE} to be mappings."
      exit 2
    end

    context = expectation_file(entry, "context")
    file = expectation_file(entry, "example")

    case entry["result"]
    when "accepts"
      checks << run_command(
        "target context #{context} accepts #{file}",
        [RUBY, "scripts/ads-conformance-check.rb", "--context", context, file],
        expect_success: true
      )
    when "rejects"
      checks << run_command(
        "target context #{context} rejects #{file}",
        [RUBY, "scripts/ads-conformance-check.rb", "--context", context, file],
        expected_exit: 1,
        stdout_includes: expected_diagnostics(entry, required: true)
      )
    else
      warn "Expected target context result to be accepts or rejects: #{entry.inspect}"
      exit 2
    end
  end

  exit(checks.all? ? 0 : 1)
end
