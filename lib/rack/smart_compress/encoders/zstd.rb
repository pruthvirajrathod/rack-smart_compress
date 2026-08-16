# frozen_string_literal: true

require_relative "base"

module Rack
  module SmartCompress
    module Encoders
      class Zstd < Base
        ENCODING_NAME = "zstd"

        class << self
          def available?
            return @available if defined?(@available)

            @available = begin
              require "zstd-ruby"
              true
            rescue LoadError
              false
            end
          end

          def compress(content, level: nil)
            raise LoadError, "zstd-ruby gem is not available" unless available?

            compression_level = level || 3
            ::Zstd.compress(content, level: compression_level)
          end
        end
      end
    end
  end
end
