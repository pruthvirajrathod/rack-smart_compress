# frozen_string_literal: true

require "zlib"

module Rack
  module SmartCompress
    class Configuration
      DEFAULT_MIN_SIZE = 1024 # 1 KB

      DEFAULT_ENCODINGS = %w[zstd br gzip deflate].freeze

      DEFAULT_MIME_TYPES = [
        "text/html",
        "text/plain",
        "text/css",
        "text/javascript",
        "text/xml",
        "application/json",
        "application/javascript",
        "application/x-javascript",
        "application/xml",
        "application/xhtml+xml",
        "application/rss+xml",
        "application/atom+xml",
        "application/wasm",
        "image/svg+xml"
      ].freeze

      DEFAULT_EXCLUDED_MIME_TYPES = [
        "image/jpeg",
        "image/png",
        "image/gif",
        "image/webp",
        "image/avif",
        "audio/",
        "video/",
        "application/zip",
        "application/x-gzip",
        "application/pdf"
      ].freeze

      attr_accessor :min_size,
                    :encodings,
                    :mime_types,
                    :exclude_mime_types,
                    :cache,
                    :cache_size,
                    :dynamic_levels,
                    :zstd_level,
                    :brotli_level,
                    :gzip_level,
                    :deflate_level,
                    :if_condition,
                    :unless_condition,
                    :instrumentation,
                    :static_assets,
                    :static_root,
                    :static_urls,
                    :static_headers,
                    :static_cascade

      def initialize
        @min_size = DEFAULT_MIN_SIZE
        @encodings = DEFAULT_ENCODINGS.dup
        @mime_types = DEFAULT_MIME_TYPES.dup
        @exclude_mime_types = DEFAULT_EXCLUDED_MIME_TYPES.dup
        @cache = false
        @cache_size = 200
        @dynamic_levels = false
        @zstd_level = 3
        @brotli_level = 4
        @gzip_level = Zlib::DEFAULT_COMPRESSION
        @deflate_level = Zlib::DEFAULT_COMPRESSION
        @if_condition = nil
        @unless_condition = nil
        @instrumentation = true
        @static_assets = false
        @static_root = "public"
        @static_urls = ["/"]
        @static_headers = {}
        @static_cascade = true
      end

      # Convenience aliases for :if and :unless
      def if(&block)
        if block_given?
          @if_condition = block
        else
          @if_condition
        end
      end

      def if=(val)
        @if_condition = val
      end

      def unless(&block)
        if block_given?
          @unless_condition = block
        else
          @unless_condition
        end
      end

      def unless=(val)
        @unless_condition = val
      end

      def to_h
        {
          min_size: @min_size,
          encodings: @encodings,
          mime_types: @mime_types,
          exclude_mime_types: @exclude_mime_types,
          cache: @cache,
          cache_size: @cache_size,
          dynamic_levels: @dynamic_levels,
          zstd_level: @zstd_level,
          brotli_level: @brotli_level,
          gzip_level: @gzip_level,
          deflate_level: @deflate_level,
          if: @if_condition,
          unless: @unless_condition,
          instrumentation: @instrumentation,
          static_assets: @static_assets,
          static_root: @static_root,
          static_urls: @static_urls,
          static_headers: @static_headers,
          static_cascade: @static_cascade
        }
      end
    end
  end
end
