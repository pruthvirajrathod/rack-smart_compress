# frozen_string_literal: true

require "spec_helper"

RSpec.describe Rack::SmartCompress::LruCache do
  subject(:cache) { described_class.new(3) }

  it "stores and retrieves items" do
    cache.put("a", 1)
    expect(cache.get("a")).to eq(1)
    expect(cache.hits).to eq(1)
  end

  it "records misses when item is absent" do
    expect(cache.get("missing")).to be_nil
    expect(cache.misses).to eq(1)
  end

  it "evicts the least recently used item when max size is exceeded" do
    cache.put("a", 1)
    cache.put("b", 2)
    cache.put("c", 3)

    # Access "a" to make it MRU
    cache.get("a")

    # Insert "d" -> should evict "b" (since "a" was accessed and "c" was inserted after "b")
    cache.put("d", 4)

    expect(cache.get("a")).to eq(1)
    expect(cache.get("b")).to be_nil
    expect(cache.get("c")).to eq(3)
    expect(cache.get("d")).to eq(4)
  end

  it "executes fetch block outside lock and caches result" do
    calls = 0
    res1 = cache.fetch("k1") { calls += 1; "val1" }
    res2 = cache.fetch("k1") { calls += 1; "val1" }

    expect(res1).to eq("val1")
    expect(res2).to eq("val1")
    expect(calls).to eq(1)
    expect(cache.hits).to eq(1)
    expect(cache.misses).to eq(1)
  end

  it "handles multi-threaded concurrent access safely" do
    threads = 10.times.map do |t|
      Thread.new do
        20.times do |i|
          key = "key_#{i % 5}"
          cache.fetch(key) { "payload_#{key}" }
        end
      end
    end
    threads.each(&:join)

    expect(cache.size).to be <= 3
  end

  it "builds deterministic hash keys" do
    key1 = cache.build_key("zstd", 3, "hello world")
    key2 = cache.build_key("zstd", 3, "hello world")
    key3 = cache.build_key("gzip", 3, "hello world")

    expect(key1).to eq(key2)
    expect(key1).not_to eq(key3)
  end
end
