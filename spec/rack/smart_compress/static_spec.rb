# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Rack::SmartCompress::Static do
  include Rack::Test::Methods

  let(:tmp_dir) { Dir.mktmpdir("smart_compress_static_test") }

  let(:dummy_app) do
    lambda do |env|
      [404, { "Content-Type" => "text/plain" }, ["Downstream App 404"]]
    end
  end

  let(:options) do
    {
      root: tmp_dir,
      urls: ["/assets", "/static"],
      headers: { "Cache-Control" => "public, max-age=31536000, immutable" }
    }
  end

  let(:app) { described_class.new(dummy_app, options) }

  before do
    FileUtils.mkdir_p(File.join(tmp_dir, "assets"))
    FileUtils.mkdir_p(File.join(tmp_dir, "static"))

    # Create dummy static assets and their pre-compressed counterparts
    File.write(File.join(tmp_dir, "assets", "app.js"), "console.log('original uncompressed js');")
    File.write(File.join(tmp_dir, "assets", "app.js.zst"), "ZSTD_PRECOMPRESSED_DATA")
    File.write(File.join(tmp_dir, "assets", "app.js.br"), "BROTLI_PRECOMPRESSED_DATA")
    File.write(File.join(tmp_dir, "assets", "app.js.gz"), "GZIP_PRECOMPRESSED_DATA")

    # Single-format asset
    File.write(File.join(tmp_dir, "assets", "style.css"), "body { color: red; }")
    File.write(File.join(tmp_dir, "assets", "style.css.gz"), "GZIP_STYLE_DATA")

    # Uncompressed-only asset
    File.write(File.join(tmp_dir, "static", "plain.txt"), "hello plain world")
  end

  after do
    FileUtils.rm_rf(tmp_dir)
  end

  describe "Pre-compressed asset serving" do
    it "serves .zst file with Content-Encoding: zstd when requested" do
      get "/assets/app.js", {}, { "HTTP_ACCEPT_ENCODING" => "zstd, gzip" }

      expect(last_response.status).to eq(200)
      expect(last_response.headers["Content-Encoding"]).to eq("zstd")
      expect(last_response.headers["Content-Type"]).to include("javascript")
      expect(last_response.headers["Vary"]).to eq("Accept-Encoding")
      expect(last_response.headers["Cache-Control"]).to eq("public, max-age=31536000, immutable")
      expect(last_response.body).to eq("ZSTD_PRECOMPRESSED_DATA")
    end

    it "serves .br file with Content-Encoding: br when requested" do
      get "/assets/app.js", {}, { "HTTP_ACCEPT_ENCODING" => "br;q=1.0, gzip;q=0.5" }

      expect(last_response.status).to eq(200)
      expect(last_response.headers["Content-Encoding"]).to eq("br")
      expect(last_response.headers["Content-Type"]).to include("javascript")
      expect(last_response.body).to eq("BROTLI_PRECOMPRESSED_DATA")
    end

    it "serves .gz file with Content-Encoding: gzip when requested" do
      get "/assets/app.js", {}, { "HTTP_ACCEPT_ENCODING" => "gzip" }

      expect(last_response.status).to eq(200)
      expect(last_response.headers["Content-Encoding"]).to eq("gzip")
      expect(last_response.headers["Content-Type"]).to include("javascript")
      expect(last_response.body).to eq("GZIP_PRECOMPRESSED_DATA")
    end

    it "falls back to available .gz when .zst is requested but missing" do
      get "/assets/style.css", {}, { "HTTP_ACCEPT_ENCODING" => "zstd, gzip" }

      expect(last_response.status).to eq(200)
      expect(last_response.headers["Content-Encoding"]).to eq("gzip")
      expect(last_response.headers["Content-Type"]).to eq("text/css")
      expect(last_response.body).to eq("GZIP_STYLE_DATA")
    end

    it "falls back to downstream app when uncompressed and cascade is true" do
      get "/assets/app.js" # No Accept-Encoding

      expect(last_response.status).to eq(404)
      expect(last_response.body).to eq("Downstream App 404")
    end
  end

  describe "HTTP Methods & Conditional Requests" do
    it "handles HEAD requests by returning headers with empty body" do
      env = { "REQUEST_METHOD" => "HEAD", "PATH_INFO" => "/assets/app.js", "HTTP_ACCEPT_ENCODING" => "zstd" }
      status, headers, body = app.call(env)

      expect(status).to eq(200)
      expect(headers["content-encoding"]).to eq("zstd")
      expect(headers["content-length"]).to eq("ZSTD_PRECOMPRESSED_DATA".bytesize.to_s)
      expect(body).to be_empty
    end

    it "returns 304 Not Modified when If-None-Match matches ETag" do
      get "/assets/app.js", {}, { "HTTP_ACCEPT_ENCODING" => "zstd" }
      etag = last_response.headers["ETag"]
      expect(etag).not_to be_nil

      get "/assets/app.js", {}, { "HTTP_ACCEPT_ENCODING" => "zstd", "HTTP_IF_NONE_MATCH" => etag }
      expect(last_response.status).to eq(304)
      expect(last_response.body).to be_empty
    end

    it "returns 304 Not Modified when If-Modified-Since is in the future" do
      future_time = (Time.now + 3600).httpdate
      get "/assets/app.js", {}, { "HTTP_ACCEPT_ENCODING" => "zstd", "HTTP_IF_MODIFIED_SINCE" => future_time }

      expect(last_response.status).to eq(304)
      expect(last_response.body).to be_empty
    end
  end

  describe "Security & Path Traversal Guards" do
    it "prevents directory traversal attacks and forwards to app" do
      get "/assets/../../../../etc/passwd", {}, { "HTTP_ACCEPT_ENCODING" => "gzip" }

      expect(last_response.status).to eq(404)
      expect(last_response.body).to eq("Downstream App 404")
    end

    it "bypasses requests for URLs not in the configured urls list" do
      get "/other/app.js", {}, { "HTTP_ACCEPT_ENCODING" => "zstd" }

      expect(last_response.status).to eq(404)
      expect(last_response.body).to eq("Downstream App 404")
    end
  end
end
