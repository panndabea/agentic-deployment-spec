# frozen_string_literal: true

module Ads
  module Diagnostic
    SECRET_BINDING_ALLOWLIST = %w[
      name
      source
      ref
      injection
      reload
      for
      purpose
    ].freeze

    SECRET_PAYLOAD_EXACT_KEYS = %w[
      value
      secretvalue
      secret_value
      privatekey
      private_key
      credential
      credentials
      password
      token
      data
    ].freeze

    REDACTED = "[REDACTED]".freeze

    module_function

    def secret_payload_key?(key)
      normalized = key.to_s.gsub(/[^A-Za-z0-9]/, "").downcase
      return true if SECRET_PAYLOAD_EXACT_KEYS.include?(normalized)

      normalized.include?("password") ||
        normalized.include?("credential") ||
        normalized.include?("privatekey") ||
        normalized.end_with?("token") ||
        normalized.end_with?("secretvalue")
    end

    def redact(value, binding_allowlist: false)
      case value
      when Hash
        value.each_with_object({}) do |(key, entry), redacted|
          key_string = key.to_s
          next if binding_allowlist && !SECRET_BINDING_ALLOWLIST.include?(key_string)

          redacted[key_string] = if secret_payload_key?(key_string)
                                   REDACTED
                                 else
                                   redact(entry, binding_allowlist: false)
                                 end
        end
      when Array
        value.map { |entry| redact(entry, binding_allowlist: false) }
      else
        value
      end
    end
  end
end
