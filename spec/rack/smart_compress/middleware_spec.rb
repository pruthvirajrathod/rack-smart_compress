# frozen_string_literal: true

require "spec_helper"
require "brotli"
require "zstd-ruby"

RSpec.describe Rack::SmartCompress::Middleware do
  include Rack::Test::Methods

  let(:large_json_body) { { status: "success", data: "x" * 2000 }.to_json }
  let(:small_json_body) { { status: "ok" }.to_json }

  let(:app_headers) { { "Content-Type" => "application/json" } }
  let(:app_status) { 200 }
  let(:app_body) { [large_json_body] }

  let(:dummy_app) do
    lambda do |env|
      [app_status, app_headers.dup, app_body]
    end
  end

  let(:options) { {} }
  let(:app) { Rack::SmartCompress::Middleware.new(dummy_app, options) }

  describe "HTTP Accept-Encoding negotiation" do
    context "when client requests gzip" do
      it "compresses the response with gzip and sets Content-Encoding header" do
        get "/", {}, { "HTTP_ACCEPT_ENCODING" => "gzip" }

        expect(last_response.headers["Content-Encoding"]).to eq("gzip")
        expect(last_response.headers["Vary"]).to include("Accept-Encoding")
        expect(last_response.body.bytesize).to be < large_json_body.bytesize

        gz = Zlib::GzipReader.new(StringIO.new(last_response.body))
        expect(gz.read).to eq(large_json_body)
      end
    end

    context "when client requests deflate" do
      it "compresses the response with deflate" do
        get "/", {}, { "HTTP_ACCEPT_ENCODING" => "deflate" }

        expect(last_response.headers["Content-Encoding"]).to eq("deflate")
        expect(Zlib::Inflate.inflate(last_response.body)).to eq(large_json_body)
      end
    end

    context "when client requests zstd" do
      it "compresses the response with zstd" do
        get "/", {}, { "HTTP_ACCEPT_ENCODING" => "zstd" }

        expect(last_response.headers["Content-Encoding"]).to eq("zstd")
        decompressed = Zstd.decompress(last_response.body)
        expect(decompressed).to eq(large_json_body)
      end
    end

    context "when client requests br (brotli)" do
      it "compresses the response with brotli" do
        get "/", {}, { "HTTP_ACCEPT_ENCODING" => "br" }

        expect(last_response.headers["Content-Encoding"]).to eq("br")
        decompressed = Brotli.inflate(last_response.body)
        expect(decompressed).to eq(large_json_body)
      end
    end

    context "when client requests multiple encodings with q-values" do
      it "prefers highest weighted encoding supported" do
        get "/", {}, { "HTTP_ACCEPT_ENCODING" => "gzip;q=0.5, deflate;q=0.9" }

        expect(last_response.headers["Content-Encoding"]).to eq("deflate")
      end
    end

    context "when client requests wildcard *" do
      it "selects the first available enabled encoding" do
        get "/", {}, { "HTTP_ACCEPT_ENCODING" => "*" }

        expect(last_response.headers["Content-Encoding"]).to eq("zstd")
        decompressed = Zstd.decompress(last_response.body)
        expect(decompressed).to eq(large_json_body)
      end
    end

    context "when client explicitly rejects an encoding with q=0" do
      it "skips rejected encoding and picks the next available" do
        get "/", {}, { "HTTP_ACCEPT_ENCODING" => "zstd;q=0, br;q=0.8, gzip;q=0.5" }

        expect(last_response.headers["Content-Encoding"]).to eq("br")
      end
    end

    context "when client sends no Accept-Encoding header" do
      it "leaves the response uncompressed" do
        get "/"

        expect(last_response.headers["Content-Encoding"]).to be_nil
        expect(last_response.body).to eq(large_json_body)
      end
    end
  end

  describe "RFC 9110 & RFC 9111 HTTP Standards Compliance" do
    context "when response contains a strong ETag" do
      let(:app_headers) { { "Content-Type" => "application/json", "ETag" => %("abcdef123456") } }

      it "weakens the ETag to W/\"...\" on compression" do
        get "/", {}, { "HTTP_ACCEPT_ENCODING" => "gzip" }

        expect(last_response.headers["Content-Encoding"]).to eq("gzip")
        expect(last_response.headers["ETag"]).to eq(%(W/"abcdef123456"))
      end
    end

    context "when response already contains a weak ETag" do
      let(:app_headers) { { "Content-Type" => "application/json", "ETag" => %(W/"alreadyweak") } }

      it "preserves the weak ETag without double-prefixing" do
        get "/", {}, { "HTTP_ACCEPT_ENCODING" => "gzip" }

        expect(last_response.headers["ETag"]).to eq(%(W/"alreadyweak"))
      end
    end

    context "when response has Cache-Control: no-transform" do
      let(:app_headers) { { "Content-Type" => "application/json", "Cache-Control" => "no-cache, no-transform" } }

      it "skips compression and leaves payload untouched" do
        get "/", {}, { "HTTP_ACCEPT_ENCODING" => "zstd" }

        expect(last_response.headers["Content-Encoding"]).to be_nil
        expect(last_response.body).to eq(large_json_body)
      end
    end

    context "when response is 206 Partial Content" do
      let(:app_status) { 206 }
      let(:app_headers) { { "Content-Type" => "application/json", "Content-Range" => "bytes 0-500/2000" } }

      it "skips dynamic compression to preserve byte ranges" do
        get "/", {}, { "HTTP_ACCEPT_ENCODING" => "gzip" }

        expect(last_response.headers["Content-Encoding"]).to be_nil
        expect(last_response.status).to eq(206)
      end
    end
  end

  describe "Rails Rack::BodyProxy handling" do
    let(:proxy_body) { Rack::BodyProxy.new([large_json_body]) {} }
    let(:dummy_app) do
      lambda do |env|
        [200, { "Content-Type" => "application/json" }, proxy_body]
      end
    end

    it "treats array-backed BodyProxy as buffered, setting Content-Length and caching" do
      get "/", {}, { "HTTP_ACCEPT_ENCODING" => "zstd" }

      expect(last_response.headers["Content-Encoding"]).to eq("zstd")
      expect(last_response.headers["Content-Length"]).not_to be_nil
      expect(last_response.headers["Content-Length"].to_i).to be < large_json_body.bytesize
    end
  end

  describe "Feature 2: In-Memory LRU Cache" do
    let(:options) { { cache: true, cache_size: 50 } }

    it "caches compressed responses and records hits" do
      expect(app.cache.hits).to eq(0)

      # First request (Cache Miss)
      get "/", {}, { "HTTP_ACCEPT_ENCODING" => "gzip" }
      expect(last_response.headers["Content-Encoding"]).to eq("gzip")
      expect(app.cache.hits).to eq(0)
      expect(app.cache.misses).to eq(1)

      # Second identical request (Cache Hit)
      get "/", {}, { "HTTP_ACCEPT_ENCODING" => "gzip" }
      expect(last_response.headers["Content-Encoding"]).to eq("gzip")
      expect(app.cache.hits).to eq(1)
    end
  end

  describe "Feature 5: Custom Filter Rules (:if and :unless)" do
    context "when :if condition evaluates to false" do
      let(:options) { { if: ->(env, status, headers) { env["HTTP_X_COMPRESS"] == "true" } } }

      it "skips compression if header is missing" do
        get "/", {}, { "HTTP_ACCEPT_ENCODING" => "gzip" }
        expect(last_response.headers["Content-Encoding"]).to be_nil

        get "/", {}, { "HTTP_ACCEPT_ENCODING" => "gzip", "HTTP_X_COMPRESS" => "true" }
        expect(last_response.headers["Content-Encoding"]).to eq("gzip")
      end
    end

    context "when :unless condition evaluates to true" do
      let(:options) { { unless: ->(env, status, headers) { env["PATH_INFO"] == "/skip" } } }

      it "skips compression for /skip path" do
        get "/skip", {}, { "HTTP_ACCEPT_ENCODING" => "gzip" }
        expect(last_response.headers["Content-Encoding"]).to be_nil
      end
    end
  end

  describe "Feature 1: Streaming Chunked Body" do
    class StreamingBody
      def each
        yield "Chunk 1: " + ("a" * 1000)
        yield "Chunk 2: " + ("b" * 1000)
      end
    end

    let(:app_body) { StreamingBody.new }

    it "streams compressed chunks without buffering full payload" do
      get "/", {}, { "HTTP_ACCEPT_ENCODING" => "gzip" }

      expect(last_response.headers["Content-Encoding"]).to eq("gzip")

      gz = Zlib::GzipReader.new(StringIO.new(last_response.body))
      expect(gz.read).to eq("Chunk 1: " + ("a" * 1000) + "Chunk 2: " + ("b" * 1000))
    end
  end

  describe "Feature 6: Dynamic CPU Advisor" do
    let(:options) { { dynamic_levels: true } }

    it "adjusts compression levels dynamically under high load" do
      allow(Rack::SmartCompress::CpuAdvisor).to receive(:high_load?).and_return(true)
      expect(Rack::SmartCompress::CpuAdvisor.adjusted_level("zstd", 3)).to eq(1)
      expect(Rack::SmartCompress::CpuAdvisor.adjusted_level("gzip", 6)).to eq(Zlib::BEST_SPEED)

      get "/", {}, { "HTTP_ACCEPT_ENCODING" => "gzip" }
      expect(last_response.headers["Content-Encoding"]).to eq("gzip")
    end
  end

  describe "Telemetry & Instrumentation" do
    it "invokes custom instrumentation callback on compression" do
      recorded_events = []
      custom_options = {
        instrumentation: ->(payload) { recorded_events << payload }
      }
      custom_app = Rack::SmartCompress::Middleware.new(dummy_app, custom_options)
      custom_session = Rack::Test::Session.new(Rack::MockSession.new(custom_app))

      custom_session.get("/", {}, { "HTTP_ACCEPT_ENCODING" => "zstd" })

      expect(recorded_events.size).to eq(1)
      event = recorded_events.first
      expect(event[:encoder]).to eq("zstd")
      expect(event[:original_size]).to eq(large_json_body.bytesize)
      expect(event[:compressed_size]).to be < large_json_body.bytesize
      expect(event[:cache_hit]).to be(false)
    end
  end
end
