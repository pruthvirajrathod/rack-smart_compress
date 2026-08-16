# frozen_string_literal: true

require "benchmark"
require "json"
require "zlib"
require_relative "../lib/rack/smart_compress"

puts "=" * 60
puts "  Rack::SmartCompress Performance Benchmark  "
puts "=" * 60

sample_data = {
  users: (1..1000).map { |i| { id: i, name: "User #{i}", email: "user#{i}@example.com", active: true, tags: ["ruby", "rails", "performance"] } }
}

json_payload = sample_data.to_json
payload_bytes = json_payload.bytesize

puts "\nOriginal JSON Payload Size: #{(payload_bytes / 1024.0).round(2)} KB"
puts "-" * 60

encoders = {
  "Gzip" => Rack::SmartCompress::Encoders::Gzip,
  "Deflate" => Rack::SmartCompress::Encoders::Deflate,
  "Brotli" => Rack::SmartCompress::Encoders::Brotli,
  "Zstd" => Rack::SmartCompress::Encoders::Zstd
}

results = {}

encoders.each do |name, encoder_class|
  unless encoder_class.available?
    puts "#{name}: [SKIPPED - Native gem not installed]"
    next
  end

  compressed = nil
  time = Benchmark.realtime do
    100.times do
      compressed = encoder_class.compress(json_payload)
    end
  end

  compressed_bytes = compressed.bytesize
  ratio = ((1.0 - (compressed_bytes.to_f / payload_bytes)) * 100).round(2)
  avg_ms = ((time / 100.0) * 1000).round(3)

  results[name] = {
    size_kb: (compressed_bytes / 1024.0).round(2),
    ratio: ratio,
    avg_ms: avg_ms
  }
end

puts sprintf("%-12s | %-12s | %-12s | %-12s", "Algorithm", "Compressed Size", "Compression %", "Avg Speed (ms)")
puts "-" * 60

results.each do |name, stats|
  puts sprintf("%-12s | %-12s | %-12s | %-12s", name, "#{stats[:size_kb]} KB", "#{stats[:ratio]}%", "#{stats[:avg_ms]} ms")
end

puts "=" * 60
