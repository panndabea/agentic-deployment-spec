# frozen_string_literal: true

require "json"

module Ads
  class Plan
    attr_reader :data

    def initialize(data)
      @data = data
    end

    def self.from_json(json)
      new(JSON.parse(json))
    end

    def [](key)
      data[key]
    end

    def api_version
      data["apiVersion"]
    end

    def kind
      data["kind"]
    end

    def target_profile
      data.dig("target", "profile")
    end

    def diagnostics
      data["diagnostics"] || []
    end

    def errors
      diagnostics.select { |diagnostic| diagnostic["severity"] == "error" }
    end

    def to_h
      data
    end

    def to_json(*args)
      data.to_json(*args)
    end
  end
end
