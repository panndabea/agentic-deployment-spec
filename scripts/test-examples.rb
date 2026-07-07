#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"
require "rbconfig"

REPO_ROOT = File.expand_path("..", __dir__)
RUBY = RbConfig.ruby
SCHEMA_FILE = "schemas/ads.schema.json"

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

Dir.chdir(REPO_ROOT) do
  schema = schema_command
  unless schema
    warn "Missing check-jsonschema or uvx; install one to run schema fixture tests."
    exit 2
  end

  schema_positive = ["examples/minimal.yaml"] + Dir["examples/conformance/invalid/*.yaml"].sort
  schema_negative = Dir["examples/invalid/*.yaml"].sort
  conformance_positive = ["examples/minimal.yaml"]
  conformance_negative = Dir["examples/conformance/invalid/*.yaml"].sort
  target_context_positive = Dir["contexts/*.yaml"].sort
  target_context_negative = Dir["contexts/invalid/*.yaml"].sort

  checks = []

  schema_positive.each do |file|
    checks << run_command(
      "schema accepts #{file}",
      schema + ["--schemafile", SCHEMA_FILE, file],
      expect_success: true
    )
  end

  schema_negative.each do |file|
    checks << run_command(
      "schema rejects #{file}",
      schema + ["--schemafile", SCHEMA_FILE, file],
      expected_exit: 1
    )
  end

  conformance_positive.each do |file|
    checks << run_command(
      "conformance accepts #{file}",
      [RUBY, "scripts/ads-conformance-check.rb", file],
      expect_success: true
    )
  end

  conformance_negative.each do |file|
    checks << run_command(
      "conformance rejects #{file}",
      [RUBY, "scripts/ads-conformance-check.rb", file],
      expected_exit: 1
    )
  end

  target_context_positive.each do |context|
    checks << run_command(
      "target context #{context} accepts examples/minimal.yaml",
      [RUBY, "scripts/ads-conformance-check.rb", "--context", context, "examples/minimal.yaml"],
      expect_success: true
    )
  end

  target_context_negative.each do |context|
    checks << run_command(
      "target context #{context} rejects examples/minimal.yaml",
      [RUBY, "scripts/ads-conformance-check.rb", "--context", context, "examples/minimal.yaml"],
      expected_exit: 1,
      stdout_includes: %w[
        capability-unsupported
        secret-unbound
        approval-handler-missing
        observability-sink-missing
      ]
    )
  end

  exit(checks.all? ? 0 : 1)
end
