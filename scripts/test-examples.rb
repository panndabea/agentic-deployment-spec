#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"
require "fileutils"
require "json"
require "rbconfig"
require "tmpdir"
require "yaml"

require_relative "lib/ads/planner"
require_relative "lib/ads/adapters/compose"
require_relative "lib/ads/adapters/kubernetes"

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

def contains_all?(text, substrings)
  substrings.all? { |substring| text.include?(substring) }
end

def diagnostics_text(diagnostics)
  diagnostics.map do |diagnostic|
    [
      diagnostic["severity"],
      diagnostic["category"],
      diagnostic["path"],
      diagnostic["message"]
    ].join(" ")
  end.join("\n")
end

def print_assertion(label, success, details = [])
  puts "#{success ? "PASS" : "FAIL"} #{label}"
  unless success
    Array(details).each do |detail|
      puts "  #{detail}"
    end
  end
  success
end

def plan_for(example, context)
  result = Ads::Processor.validate_for_planning(file: example, context_file: context)
  return [result, nil] if result.blocking?

  [result, Ads::Planner.plan(result)]
end

def pretty_json(data)
  "#{JSON.pretty_generate(data)}\n"
end

def compare_plan_fixture(entry)
  example = expectation_file(entry, "example")
  context = expectation_file(entry, "context")
  fixture = expectation_file(entry, "fixture")
  result, plan = plan_for(example, context)
  actual = plan ? pretty_json(plan.to_h) : ""
  expected = File.file?(fixture) ? File.read(fixture) : ""
  success = result.ok? && actual == expected
  print_assertion(
    "plan fixture #{fixture}",
    success,
    [
      "example: #{example}",
      "context: #{context}",
      "diagnostics: #{diagnostics_text(result.diagnostics)}",
      "expected bytes: #{expected.bytesize}",
      "actual bytes: #{actual.bytesize}"
    ]
  )
end

def relative_files(directory)
  Dir.glob(File.join(directory, "**", "*"))
     .select { |path| File.file?(path) }
     .map { |path| path.delete_prefix("#{directory}/") }
     .sort
end

def comparable_file_contents(path)
  if File.extname(path) == ".json"
    pretty_json(JSON.parse(File.read(path)))
  else
    File.read(path)
  end
end

def compare_directories(label, actual_dir, fixture_dir)
  actual_files = relative_files(actual_dir)
  expected_files = relative_files(fixture_dir)
  details = []
  details << "expected files: #{expected_files.inspect}" unless actual_files == expected_files
  details << "actual files: #{actual_files.inspect}" unless actual_files == expected_files

  files_match = actual_files == expected_files
  if files_match
    actual_files.each do |file|
      actual = comparable_file_contents(File.join(actual_dir, file))
      expected = comparable_file_contents(File.join(fixture_dir, file))
      next if actual == expected

      files_match = false
      details << "content differs: #{file}"
      details << "expected bytes: #{expected.bytesize}"
      details << "actual bytes: #{actual.bytesize}"
      break
    end
  end

  print_assertion(label, files_match, details)
end

def run_json_command(label, command, expected_exit:)
  stdout, stderr, status = Open3.capture3(*command)
  body = JSON.parse(stdout)
  required_keys = %w[ok phase errors warnings nextActions]
  success = status.exitstatus == expected_exit && required_keys.all? { |key| body.key?(key) }

  puts "#{success ? "PASS" : "FAIL"} #{label}"
  unless success
    puts "  command: #{command.join(" ")}"
    puts "  expected exit: #{expected_exit}"
    puts "  exit: #{status.exitstatus}"
    puts stdout.lines.map { |line| "  stdout: #{line}" }.join unless stdout.empty?
    puts stderr.lines.map { |line| "  stderr: #{line}" }.join unless stderr.empty?
  end

  [success, body, stdout]
rescue JSON::ParserError => e
  puts "FAIL #{label}"
  puts "  command: #{command.join(" ")}"
  puts "  JSON parse error: #{e.message}"
  puts stdout.lines.map { |line| "  stdout: #{line}" }.join if defined?(stdout) && stdout && !stdout.empty?
  [false, {}, stdout || ""]
end

def artifact_adapter(target)
  case target
  when "compose"
    Ads::Adapters::Compose
  when "kubernetes"
    Ads::Adapters::Kubernetes
  end
end

def forbidden_secret_payload?(text)
  forbidden_keys = [/secretValue:/i, /privateKey:/i, /password:/i, /token:/i]
  forbidden_keys.any? { |pattern| text.match?(pattern) }
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

  expectation_list(expectations, "schema", "rejects").each do |file|
    result = Ads::Processor.validate_for_planning(
      file: file,
      context_file: "contexts/kubernetes-production.yaml"
    )
    checks << print_assertion(
      "planning blocks schema reject #{file}",
      result.blocking? && result.errors.any? { |diagnostic| diagnostic["category"] == "schema-invalid" },
      diagnostics_text(result.diagnostics)
    )
  end

  warning_file = expectation_file(expectation_list(expectations, "conformance", "warns").first)
  normal_warning_result = Ads::Processor.validate_document(file: warning_file)
  strict_warning_result = Ads::Processor.validate_document(file: warning_file, strict_warnings: true)
  checks << print_assertion(
    "planning warnings block only with strict warnings",
    normal_warning_result.warnings.any? && !normal_warning_result.blocking? && strict_warning_result.blocking?,
    diagnostics_text(strict_warning_result.diagnostics)
  )

  %w[
    examples/conformance/invalid/dependency-cycle.yaml
    examples/conformance/invalid/name-normalization-collision.yaml
  ].each do |file|
    result = Ads::Processor.validate_document(file: file)
    expected_category = file.include?("dependency") ? "reference-invalid" : "processor-limitation"
    checks << print_assertion(
      "processor core rejects #{file}",
      result.blocking? && result.errors.any? { |diagnostic| diagnostic["category"] == expected_category },
      diagnostics_text(result.diagnostics)
    )
  end

  expectation_list(expectations, "planningCore", "profileRejects").each do |entry|
    example = expectation_file(entry, "example")
    context = expectation_file(entry, "context")
    result = Ads::Processor.validate_for_planning(file: example, context_file: context)
    text = diagnostics_text(result.diagnostics)
    checks << print_assertion(
      "planning profile rejects #{example} for #{context}",
      result.blocking? && contains_all?(text, expected_diagnostics(entry, required: true)),
      text
    )
  end

  expectation_list(expectations, "planningCore", "redaction").each do |entry|
    example = expectation_file(entry, "example")
    context = expectation_file(entry, "context")
    result, plan = plan_for(example, context)
    plan_text = plan ? pretty_json(plan.to_h) : ""
    forbidden = entry["forbidden"]
    checks << print_assertion(
      "planning redacts secret payloads for #{context}",
      result.ok? && forbidden.is_a?(Array) && forbidden.none? { |value| plan_text.include?(value) },
      forbidden&.map { |value| "forbidden: #{value}" }
    )
  end

  expectation_list(expectations, "plans", "accepts").each do |entry|
    checks << compare_plan_fixture(entry)
  end

  expectation_list(expectations, "plans", "rejects").each do |entry|
    example = expectation_file(entry, "example")
    context = expectation_file(entry, "context")
    result = Ads::Processor.validate_for_planning(file: example, context_file: context)
    text = diagnostics_text(result.diagnostics)
    checks << print_assertion(
      "plan rejects #{example} for #{context}",
      result.blocking? && contains_all?(text, expected_diagnostics(entry, required: true)),
      text
    )
  end

  expectation_list(expectations, "artifacts", "accepts").each do |entry|
    target = expectation_file(entry, "target")
    example = expectation_file(entry, "example")
    context = expectation_file(entry, "context")
    fixture_dir = expectation_file(entry, "fixtureDir")
    adapter = artifact_adapter(target)
    unless adapter
      warn "Unsupported artifact adapter in #{EXPECTATIONS_FILE}: #{entry.inspect}"
      exit 2
    end

    Dir.mktmpdir("ads-artifacts") do |directory|
      output_dir = File.join(directory, "bundle")
      result, plan = plan_for(example, context)
      if plan
        adapter.emit(plan, output_dir)
      end
      checks << compare_directories("artifact fixture #{fixture_dir}", output_dir, fixture_dir)
      text = relative_files(output_dir).map { |file| File.read(File.join(output_dir, file)) }.join("\n")
      checks << print_assertion(
        "artifact redaction #{fixture_dir}",
        !forbidden_secret_payload?(text),
        "artifact output contains secret-like payload fields"
      )
      checks << print_assertion(
        "artifact plan ok #{fixture_dir}",
        result.ok?,
        diagnostics_text(result.diagnostics)
      )
    end
  end

  expectation_list(expectations, "artifacts", "rejects").each do |entry|
    target = expectation_file(entry, "target")
    example = expectation_file(entry, "example")
    context = expectation_file(entry, "context")
    Dir.mktmpdir("ads-artifact-reject") do |directory|
      output_dir = File.join(directory, "bundle")
      success, _body, stdout = run_json_command(
        "artifact rejects #{target} #{example}",
        [
          "bin/ads",
          "emit",
          "--file",
          example,
          "--context",
          context,
          "--target",
          target,
          "--output-dir",
          output_dir,
          "--format",
          "json"
        ],
        expected_exit: 1
      )
      checks << print_assertion(
        "artifact reject diagnostics #{target} #{example}",
        success && expected_diagnostics(entry, required: true).all? { |text| stdout.include?(text) } && !File.exist?(output_dir),
        stdout
      )
    end
  end

  success, body, = run_json_command(
    "cli validate success",
    ["bin/ads", "validate", "--file", "examples/minimal.yaml", "--format", "json"],
    expected_exit: 0
  )
  checks << print_assertion("cli validate envelope ok", success && body["ok"] == true && body["phase"] == "validate")

  success, body, = run_json_command(
    "cli explain success",
    ["bin/ads", "explain", "--file", "examples/minimal.yaml", "--context", "contexts/kubernetes-production.yaml", "--format", "json"],
    expected_exit: 0
  )
  checks << print_assertion(
    "cli explain envelope ok",
    success &&
      body["ok"] == true &&
      body["phase"] == "explain" &&
      body["summary"].is_a?(String) &&
      !body["summary"].empty? &&
      body["target"] == "kubernetes" &&
      body["targetProfile"] == "kubernetes-production" &&
      body["plan"].nil? &&
      body["artifacts"] == [] &&
      body["errors"] == []
  )

  success, body, = run_json_command(
    "cli plan success",
    ["bin/ads", "plan", "--file", "examples/minimal.yaml", "--context", "contexts/kubernetes-production.yaml", "--format", "json"],
    expected_exit: 0
  )
  checks << print_assertion("cli plan envelope ok", success && body["ok"] == true && body["plan"].is_a?(Hash))

  Dir.mktmpdir("ads-cli-emit") do |directory|
    output_dir = File.join(directory, "bundle")
    success, body, = run_json_command(
      "cli emit success",
      [
        "bin/ads",
        "emit",
        "--file",
        "examples/minimal.yaml",
        "--context",
        "contexts/compose-single-host.yaml",
        "--target",
        "compose",
        "--output-dir",
        output_dir,
        "--format",
        "json"
      ],
      expected_exit: 0
    )
    checks << print_assertion("cli emit envelope ok", success && body["ok"] == true && !body["artifacts"].empty?)
  end

  success, body, = run_json_command(
    "cli plan missing context",
    ["bin/ads", "plan", "--file", "examples/minimal.yaml", "--format", "json"],
    expected_exit: 2
  )
  checks << print_assertion("cli plan missing context envelope", success && body["ok"] == false && body.dig("errors", 0, "category") == "invocation-invalid")

  success, body, = run_json_command(
    "cli plan incompatible target",
    ["bin/ads", "plan", "--file", "examples/minimal.yaml", "--context", "contexts/air-gapped.yaml", "--format", "json"],
    expected_exit: 1
  )
  checks << print_assertion("cli incompatible plan envelope", success && body["ok"] == false && body["errors"].any? { |diagnostic| diagnostic["category"] == "network-unresolved" })

  success, body, = run_json_command(
    "cli explain incompatible target",
    ["bin/ads", "explain", "--file", "examples/minimal.yaml", "--context", "contexts/air-gapped.yaml", "--format", "json"],
    expected_exit: 1
  )
  explain_categories = body.fetch("errors", []).map { |diagnostic| diagnostic["category"] }
  checks << print_assertion(
    "cli incompatible explain envelope",
    success &&
      body["ok"] == false &&
      body["phase"] == "explain" &&
      body["targetProfile"] == "air-gapped" &&
      explain_categories.include?("processor-limitation") &&
      explain_categories.include?("network-unresolved") &&
      body["nextActions"].is_a?(Array) &&
      !body["nextActions"].empty? &&
      body["summary"].is_a?(String) &&
      !body["summary"].empty? &&
      body["plan"].nil?
  )

  success, body, = run_json_command(
    "cli emit unsupported target",
    [
      "bin/ads",
      "emit",
      "--file",
      "examples/minimal.yaml",
      "--context",
      "contexts/kubernetes-production.yaml",
      "--target",
      "unknown",
      "--output-dir",
      "/tmp/ads-unsupported",
      "--format",
      "json"
    ],
    expected_exit: 2
  )
  checks << print_assertion("cli unsupported target envelope", success && body.dig("errors", 0, "category") == "invocation-invalid")

  Dir.mktmpdir("ads-cli-conflict") do |directory|
    File.write(File.join(directory, "existing.txt"), "occupied\n")
    success, body, = run_json_command(
      "cli emit output conflict",
      [
        "bin/ads",
        "emit",
        "--file",
        "examples/minimal.yaml",
        "--context",
        "contexts/compose-single-host.yaml",
        "--target",
        "compose",
        "--output-dir",
        directory,
        "--format",
        "json"
      ],
      expected_exit: 2
    )
    checks << print_assertion("cli output conflict envelope", success && body.dig("errors", 0, "category") == "invocation-invalid")
  end

  exit(checks.all? ? 0 : 1)
end
