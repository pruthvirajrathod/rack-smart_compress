# frozen_string_literal: true

require_relative "base"

module Rack
  module SmartCompress
    module Encoders
      class Brotli < Base
        ENCODING_NAME = "br"

        class << self
          def available?
            return @available if defined?(@available)

            @available = begin
              require "brotli"
              true
            rescue LoadError
              false
            end
          end

          def compress(content, level: nil)
            raise LoadError, "brotli gem is not available" unless available?

            compression_level = level || 4
            ::Brotli.deflate(content, quality: compression_level)
          end
        end
      end
    end
  end
end
