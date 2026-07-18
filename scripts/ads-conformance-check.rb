#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"

require_relative "lib/ads/processor"

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
    target_context = Ads::Processor.load_target_context(options[:context_path])
  rescue StandardError => e
    warn e.message
    exit 2
  end
end

results = []

ARGV.each do |path|
  begin
    document = Ads::Processor.load_yaml(path)
    diagnostics = Ads::Processor.check_document(document, target_context)
  rescue StandardError => e
    diagnostics = []
    Ads::Processor.add_diagnostic(
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

output = Ads::Processor.formatted_output(results, options[:format])

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
