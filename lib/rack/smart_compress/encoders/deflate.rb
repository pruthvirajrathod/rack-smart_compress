# frozen_string_literal: true

require "zlib"
require_relative "base"

module Rack
  module SmartCompress
    module Encoders
      class Deflate < Base
        ENCODING_NAME = "deflate"

        class << self
          def available?
            true
          end

          def compress(content, level: nil)
            compression_level = level || Zlib::DEFAULT_COMPRESSION
            Zlib::Deflate.deflate(content, compression_level)
          end
        end
      end
    end
  end
end
