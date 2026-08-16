# frozen_string_literal: true

require_relative "configuration"
require_relative "encoders/base"
require_relative "encoders/zstd"
require_relative "encoders/brotli"
require_relative "encoders/gzip"
require_relative "encoders/deflate"
require_relative "lru_cache"
require_relative "stream_body"
require_relative "cpu_advisor"

module Rack
  module SmartCompress
    class Middleware
      ENCODERS = {
        "zstd" => Encoders::Zstd,
        "br" => Encoders::Brotli,
        "gzip" => Encoders::Gzip,
        "deflate" => Encoders::Deflate
      }.freeze

      attr_reader :app, :options, :cache

      def initialize(app, options = {})
        @app = app
        default_config = Rack::SmartCompress.configuration.to_h
        @options = default_config.merge(options)

        @min_size = @options.fetch(:min_size, Configuration::DEFAULT_MIN_SIZE)
        @mime_types = @options.fetch(:mime_types, Configuration::DEFAULT_MIME_TYPES)
        @exclude_mime_types = @options.fetch(:exclude_mime_types, Configuration::DEFAULT_EXCLUDED_MIME_TYPES)
        @enabled_encodings = @options.fetch(:encodings, Configuration::DEFAULT_ENCODINGS)
        @if_condition = @options[:if]
        @unless_condition = @options[:unless]
        @dynamic_levels = @options.fetch(:dynamic_levels, false)
        @instrumentation = @options.fetch(:instrumentation, true)

        if @options[:cache] || @options[:cache_size]
          cache_size = @options.is_a?(Integer) ? @options[:cache_size] : (@options[:cache_size] || LruCache::DEFAULT_MAX_SIZE)
          @cache = LruCache.new(cache_size)
        else
          @cache = nil
        end
      end

      def call(env)
        status, headers, body = @app.call(env)

        return [status, headers, body] if no_body_status?(status)
        return [status, headers, body] if already_encoded?(headers)
        return [status, headers, body] if no_transform?(headers)
        return [status, headers, body] if partial_content?(status, headers)
        return [status, headers, body] unless custom_rules_pass?(env, status, headers)

        accept_encoding = env["HTTP_ACCEPT_ENCODING"].to_s
        encoder_name, encoder_class = negotiate_encoder(accept_encoding)
        return [status, headers, body] unless encoder_class

        content_type = get_header(headers, "content-type")
        return [status, headers, body] unless compressible_mime_type?(content_type)

        level = options[:"#{encoder_name}_level"]
        level = CpuAdvisor.adjusted_level(encoder_name, level) if @dynamic_levels

        # Handle streaming responses
        if streaming_body?(body) || options[:stream]
          new_headers = headers.dup
          set_header(new_headers, "content-encoding", encoder_name)
          delete_header(new_headers, "content-length") # Chunked stream size is dynamic
          append_vary(new_headers, "Accept-Encoding")
          weaken_etag(new_headers)
          stream_wrapper = StreamBody.new(body, encoder_name, encoder_class, level: level)
          return [status, new_headers, stream_wrapper]
        end

        body_string = extract_body_string(body)
        return [status, headers, body] if body_string.bytesize < @min_size

        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        compressed_body, compressed_size, cache_hit = compress_with_cache(encoder_name, encoder_class, level, body_string)
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000.0).round(3)

        body.close if body.respond_to?(:close)

        new_headers = headers.dup
        set_header(new_headers, "content-encoding", encoder_name)
        set_header(new_headers, "content-length", compressed_size.to_s)
        append_vary(new_headers, "Accept-Encoding")
        weaken_etag(new_headers)

        record_telemetry(encoder_name, body_string.bytesize, compressed_size, duration_ms, cache_hit, env)

        [status, new_headers, compressed_body]
      end

      private

      def custom_rules_pass?(env, status, headers)
        if @if_condition.respond_to?(:call)
          return false unless @if_condition.call(env, status, headers)
        end

        if @unless_condition.respond_to?(:call)
          return false if @unless_condition.call(env, status, headers)
        end

        true
      end

      def compress_with_cache(encoder_name, encoder_class, level, body_string)
        if @cache
          cache_key = @cache.build_key(encoder_name, level, body_string)
          cache_hit = true
          cached_result = @cache.get(cache_key)

          if cached_result.nil?
            cache_hit = false
            res = encoder_class.encode_body(body_string, level: level)
            cached_result = [res, res.first.bytesize]
            @cache.put(cache_key, cached_result)
          end

          [cached_result[0], cached_result[1], cache_hit]
        else
          res = encoder_class.encode_body(body_string, level: level)
          [res, res.first.bytesize, false]
        end
      end

      def record_telemetry(encoder_name, original_size, compressed_size, duration_ms, cache_hit, env)
        return unless @instrumentation

        payload = {
          encoder: encoder_name,
          original_size: original_size,
          compressed_size: compressed_size,
          duration_ms: duration_ms,
          cache_hit: cache_hit,
          path: env["PATH_INFO"]
        }

        if defined?(ActiveSupport::Notifications)
          ActiveSupport::Notifications.instrument("rack_smart_compress.compress", payload)
        end

        if @instrumentation.respond_to?(:call)
          @instrumentation.call(payload)
        end
      end

      def streaming_body?(body)
        return false if body.is_a?(Array)
        return false if body.respond_to?(:to_ary)
        return false if body.respond_to?(:to_str)

        if defined?(Rack::BodyProxy) && body.is_a?(Rack::BodyProxy)
          target = body.instance_variable_get(:@body)
          if target
            return false if target.is_a?(Array) || target.respond_to?(:to_ary) || target.respond_to?(:to_str)
          end
        end

        body.respond_to?(:each)
      end

      def no_body_status?(status)
        status < 200 || status == 204 || status == 205 || status == 304
      end

      def partial_content?(status, headers)
        status == 206 || !get_header(headers, "content-range").nil?
      end

      def no_transform?(headers)
        cache_control = get_header(headers, "cache-control")
        cache_control && cache_control.downcase.include?("no-transform")
      end

      def already_encoded?(headers)
        !get_header(headers, "content-encoding").nil?
      end

      def weaken_etag(headers)
        etag = get_header(headers, "etag")
        if etag && !etag.empty? && !etag.start_with?("W/")
          set_header(headers, "etag", %(W/#{etag}))
        end
      end

      def compressible_mime_type?(content_type)
        return false if content_type.nil? || content_type.empty?

        type = content_type.split(";").first.to_s.strip.downcase

        return false if @exclude_mime_types.any? { |ex| type.start_with?(ex) || type.include?(ex) }

        @mime_types.any? { |mime| type == mime || type.start_with?(mime) } ||
          type.end_with?("+json") || type.end_with?("+xml")
      end

      def negotiate_encoder(accept_encoding)
        return [nil, nil] if accept_encoding.strip.empty?

        requested, disallowed = parse_accept_encoding(accept_encoding)

        # 1. First check explicit requested encodings by q-value
        requested.each do |enc, q_val|
          next unless q_val > 0.0

          if enc == "*"
            # Wildcard: pick first available enabled encoding not explicitly disallowed
            @enabled_encodings.each do |candidate|
              next if disallowed.include?(candidate)
              encoder_class = ENCODERS[candidate]
              return [candidate, encoder_class] if encoder_class&.available?
            end
          elsif @enabled_encodings.include?(enc) && !disallowed.include?(enc)
            encoder_class = ENCODERS[enc]
            return [enc, encoder_class] if encoder_class&.available?
          end
        end

        [nil, nil]
      end

      def parse_accept_encoding(header)
        encodings = {}
        disallowed = []

        header.split(",").each do |part|
          next if part.strip.empty?

          enc, qval = part.split(";").map(&:strip)
          next unless enc

          q = 1.0
          if qval && qval.start_with?("q=")
            q = qval.sub("q=", "").to_f rescue 1.0
          end

          enc_down = enc.downcase
          if q <= 0.0
            disallowed << enc_down
          else
            encodings[enc_down] = q
          end
        end

        [encodings.sort_by { |_, q| -q }.to_h, disallowed]
      end

      def extract_body_string(body)
        buffer = String.new
        if body.respond_to?(:each)
          body.each { |part| buffer << part.to_s }
        else
          buffer << body.to_s
        end
        buffer
      end

      def get_header(headers, name)
        return headers[name] if headers.key?(name)

        down_name = name.downcase
        headers.each do |key, value|
          return value if key.to_s.downcase == down_name
        end
        nil
      end

      def set_header(headers, name, value)
        matching_key = headers.keys.find { |k| k.to_s.downcase == name.downcase } || name
        headers[matching_key] = value
      end

      def delete_header(headers, name)
        matching_key = headers.keys.find { |k| k.to_s.downcase == name.downcase }
        headers.delete(matching_key) if matching_key
      end

      def append_vary(headers, vary_val)
        current = get_header(headers, "vary")
        if current.nil? || current.empty?
          set_header(headers, "vary", vary_val)
        elsif !current.split(",").map(&:strip).include?(vary_val)
          set_header(headers, "vary", "#{current}, #{vary_val}")
        end
      end
    end
  end
end
