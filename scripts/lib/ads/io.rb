# frozen_string_literal: true

module Ads
  module IO
    module_function

    def safe_load_yaml(path)
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
  end
end
