# frozen_string_literal: true

require "zlib"
require "stringio"
require_relative "base"

module Rack
  module SmartCompress
    module Encoders
      class Gzip < Base
        ENCODING_NAME = "gzip"

        class << self
          def available?
            true
          end

          def compress(content, level: nil)
            compression_level = level || Zlib::DEFAULT_COMPRESSION
            io = StringIO.new
            io.set_encoding(Encoding::BINARY)
            writer = Zlib::GzipWriter.new(io, compression_level)
            writer.write(content)
            writer.close
            io.string
          end
        end
      end
    end
  end
end
