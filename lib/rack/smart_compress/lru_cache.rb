# frozen_string_literal: true

require "digest"
require "monitor"

module Rack
  module SmartCompress
    class LruCache
      include MonitorMixin

      DEFAULT_MAX_SIZE = 200

      attr_reader :max_size, :hits, :misses

      def initialize(max_size = DEFAULT_MAX_SIZE)
        super()
        @max_size = max_size
        @cache = {}
        @hits = 0
        @misses = 0
      end

      def get(key)
        mon_synchronize do
          if @cache.key?(key)
            @hits += 1
            value = @cache.delete(key)
            @cache[key] = value # Move to end (MRU)
            value
          else
            @misses += 1
            nil
          end
        end
      end

      def fetch(key)
        cached = get(key)
        return cached unless cached.nil?
        return nil unless block_given?

        # Execute expensive compression outside the mutex lock
        value = yield
        put(key, value)
        value
      end

      def put(key, value)
        mon_synchronize do
          @cache.delete(key)
          @cache[key] = value

          if @cache.size > @max_size
            @cache.shift # Remove oldest (LRU)
          end
          value
        end
      end

      def delete(key)
        mon_synchronize { @cache.delete(key) }
      end

      def clear
        mon_synchronize do
          @cache.clear
          @hits = 0
          @misses = 0
        end
      end

      def size
        mon_synchronize { @cache.size }
      end

      def build_key(encoder_name, level, content)
        digest = Digest::SHA256.new
        digest.update(encoder_name.to_s)
        digest.update(":")
        digest.update(level.to_s)
        digest.update(":")
        digest.update(content.to_s)
        digest.hexdigest
      end
    end
  end
end
