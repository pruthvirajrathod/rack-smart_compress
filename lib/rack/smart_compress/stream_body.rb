# frozen_string_literal: true

require "stringio"
require "zlib"

module Rack
  module SmartCompress
    class StreamBody
      attr_reader :body, :encoder_name, :encoder_class, :level

      def initialize(body, encoder_name, encoder_class, level: nil)
        @body = body
        @encoder_name = encoder_name
        @encoder_class = encoder_class
        @level = level
        @closed = false
      end

      def each(&block)
        return enum_for(:each) unless block_given?

        begin
          case encoder_name
          when "gzip"
            stream_gzip(&block)
          when "deflate"
            stream_deflate(&block)
          when "zstd"
            stream_zstd(&block)
          when "br"
            stream_brotli(&block)
          else
            @body.each { |chunk| yield encoder_class.compress(chunk.to_s, level: level) }
          end
        ensure
          close
        end
      end

      def close
        return if @closed

        @closed = true
        @body.close if @body.respond_to?(:close)
      end

      private

      def stream_gzip
        io = StringIO.new
        io.set_encoding(Encoding::BINARY)
        writer = Zlib::GzipWriter.new(io, level || Zlib::DEFAULT_COMPRESSION)

        @body.each do |chunk|
          chunk_str = chunk.to_s
          next if chunk_str.empty?

          writer.write(chunk_str)
          writer.flush
          data = io.string.dup
          io.truncate(0)
          io.rewind
          yield data unless data.empty?
        end

        writer.close
        final_data = io.string
        yield final_data unless final_data.empty?
      end

      def stream_deflate
        deflater = Zlib::Deflate.new(level || Zlib::DEFAULT_COMPRESSION)

        @body.each do |chunk|
          chunk_str = chunk.to_s
          next if chunk_str.empty?

          data = deflater.deflate(chunk_str, Zlib::SYNC_FLUSH)
          yield data unless data.empty?
        end

        final_data = deflater.finish
        yield final_data unless final_data.empty?
        deflater.close
      end

      def stream_zstd
        if defined?(::Zstd::StreamingCompress)
          compressor = ::Zstd::StreamingCompress.new(level: level || 3)
          @body.each do |chunk|
            chunk_str = chunk.to_s
            next if chunk_str.empty?

            data = compressor.compress(chunk_str)
            yield data unless data.nil? || data.empty?
          end
          final_data = compressor.finish
          yield final_data unless final_data.nil? || final_data.empty?
        else
          buffer = String.new
          @body.each { |chunk| buffer << chunk.to_s }
          yield encoder_class.compress(buffer, level: level)
        end
      end

      def stream_brotli
        if defined?(::Brotli::Compressor)
          compressor = ::Brotli::Compressor.new(quality: level || 4)
          @body.each do |chunk|
            chunk_str = chunk.to_s
            next if chunk_str.empty?

            data = compressor.process(chunk_str)
            yield data unless data.nil? || data.empty?
          end
          final_data = compressor.finish
          yield final_data unless final_data.nil? || final_data.empty?
        else
          buffer = String.new
          @body.each { |chunk| buffer << chunk.to_s }
          yield encoder_class.compress(buffer, level: level)
        end
      end
    end
  end
end
