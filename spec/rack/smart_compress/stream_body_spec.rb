# frozen_string_literal: true

require "spec_helper"
require "brotli"
require "zstd-ruby"

RSpec.describe Rack::SmartCompress::StreamBody do
  class MockStream
    attr_reader :closed

    def initialize(chunks)
      @chunks = chunks
      @closed = false
    end

    def each
      @chunks.each { |c| yield c }
    end

    def close
      @closed = true
    end
  end

  let(:chunks) { ["chunk 1 - " + ("x" * 100), "chunk 2 - " + ("y" * 100)] }
  let(:mock_body) { MockStream.new(chunks) }

  describe "Gzip streaming" do
    it "streams compressed chunks and closes source body" do
      stream = described_class.new(mock_body, "gzip", Rack::SmartCompress::Encoders::Gzip)
      compressed = String.new
      stream.each { |chunk| compressed << chunk }

      expect(mock_body.closed).to be(true)

      gz = Zlib::GzipReader.new(StringIO.new(compressed))
      expect(gz.read).to eq(chunks.join)
    end
  end

  describe "Deflate streaming" do
    it "streams compressed chunks and closes source body" do
      stream = described_class.new(mock_body, "deflate", Rack::SmartCompress::Encoders::Deflate)
      compressed = String.new
      stream.each { |chunk| compressed << chunk }

      expect(mock_body.closed).to be(true)

      decompressed = Zlib::Inflate.inflate(compressed)
      expect(decompressed).to eq(chunks.join)
    end
  end

  describe "Zstd streaming" do
    it "streams compressed chunks via Zstd::StreamingCompress" do
      stream = described_class.new(mock_body, "zstd", Rack::SmartCompress::Encoders::Zstd)
      compressed = String.new
      stream.each { |chunk| compressed << chunk }

      expect(mock_body.closed).to be(true)

      decompressed = Zstd.decompress(compressed)
      expect(decompressed).to eq(chunks.join)
    end
  end

  describe "Brotli streaming" do
    it "streams compressed chunks via Brotli::Compressor" do
      stream = described_class.new(mock_body, "br", Rack::SmartCompress::Encoders::Brotli)
      compressed = String.new
      stream.each { |chunk| compressed << chunk }

      expect(mock_body.closed).to be(true)

      decompressed = Brotli.inflate(compressed)
      expect(decompressed).to eq(chunks.join)
    end
  end
end
