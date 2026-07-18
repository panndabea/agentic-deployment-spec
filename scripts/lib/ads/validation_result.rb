# frozen_string_literal: true

module Ads
  class ValidationResult
    attr_reader :file,
                :context_file,
                :document,
                :context,
                :target_profile,
                :diagnostics,
                :strict_warnings

    def initialize(file:, context_file:, document:, context:, target_profile:, diagnostics:, strict_warnings: false)
      @file = file
      @context_file = context_file
      @document = document
      @context = context
      @target_profile = target_profile
      @diagnostics = diagnostics
      @strict_warnings = strict_warnings
    end

    def errors
      diagnostics.select { |diagnostic| diagnostic["severity"] == "error" }
    end

    def warnings
      diagnostics.select { |diagnostic| diagnostic["severity"] == "warning" }
    end

    def ok?
      !blocking?
    end

    def blocking?
      !errors.empty? || (strict_warnings && !warnings.empty?)
    end
  end
end
