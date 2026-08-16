# frozen_string_literal: true

require "spec_helper"

RSpec.describe Rack::SmartCompress::Configuration do
  after do
    Rack::SmartCompress.reset_config!
  end

  it "initializes with default options" do
    config = described_class.new
    expect(config.min_size).to eq(1024)
    expect(config.encodings).to eq(%w[zstd br gzip deflate])
    expect(config.cache).to be(false)
    expect(config.cache_size).to eq(200)
    expect(config.dynamic_levels).to be(false)
    expect(config.zstd_level).to eq(3)
    expect(config.brotli_level).to eq(4)
  end

  it "allows global configuration via Rack::SmartCompress.configure" do
    Rack::SmartCompress.configure do |c|
      c.min_size = 2048
      c.cache = true
      c.cache_size = 500
      c.dynamic_levels = true
    end

    expect(Rack::SmartCompress.configuration.min_size).to eq(2048)
    expect(Rack::SmartCompress.configuration.cache).to be(true)
    expect(Rack::SmartCompress.configuration.cache_size).to eq(500)
    expect(Rack::SmartCompress.configuration.dynamic_levels).to be(true)
  end

  it "resets configuration cleanly" do
    Rack::SmartCompress.configure do |c|
      c.min_size = 4096
    end

    Rack::SmartCompress.reset_config!
    expect(Rack::SmartCompress.configuration.min_size).to eq(1024)
  end
end
