# frozen_string_literal: true

require "etc"
require "zlib"

module Rack
  module SmartCompress
    class CpuAdvisor
      SAMPLE_INTERVAL = 1.0 # Sample at most once per second

      class << self
        def high_load?
          now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          if @last_check.nil? || (now - @last_check) >= SAMPLE_INTERVAL
            @last_check = now
            @cached_high_load = compute_high_load
          end
          @cached_high_load
        end

        def ncpu_count
          @ncpu_count ||= begin
            Etc.nprocessors
          rescue StandardError
            2
          end
        end

        def adjusted_level(encoder_name, default_level)
          return default_level unless high_load?

          case encoder_name
          when "zstd"
            1 # Fastest Zstd level
          when "br"
            1 # Fastest Brotli quality level
          when "gzip", "deflate"
            Zlib::BEST_SPEED # Fastest Gzip level (1)
          else
            default_level
          end
        end

        def reset!
          @last_check = nil
          @cached_high_load = nil
          @ncpu_count = nil
        end

        private

        def compute_high_load
          load_1min = current_load_avg
          return false if load_1min.nil?

          ncpu = ncpu_count
          load_1min > (ncpu * 0.85) # High load threshold (> 85% capacity)
        rescue StandardError
          false
        end

        def current_load_avg
          if File.exist?("/proc/loadavg")
            File.read("/proc/loadavg").split.first.to_f
          else
            nil
          end
        rescue StandardError
          nil
        end
      end
    end
  end
end
