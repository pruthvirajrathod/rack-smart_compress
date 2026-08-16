# frozen_string_literal: true

module Rack
  module SmartCompress
    module Encoders
      class Base
        class << self
          def available?
            true
          end

          def compress(body, level: nil)
            raise NotImplementedError, "#{name}.compress must be implemented"
          end

          def encode_body(body, level: nil)
            compressed = []
            if body.respond_to?(:each)
              buffer = String.new
              body.each { |chunk| buffer << chunk.to_s }
              compressed << compress(buffer, level: level)
            else
              compressed << compress(body.to_s, level: level)
            end
            compressed
          end
        end
      end
    end
  end
end
