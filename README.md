# ⚡ `rack-smart_compress`

> High-performance **Zstandard (`zstd`)**, **Brotli (`br`)**, and **Gzip (`gzip`)** dynamic HTTP compression & pre-compressed static asset middleware for Rack and Ruby on Rails applications.

[![Gem Version](https://img.shields.io/gem/v/rack-smart_compress.svg?color=blue&style=flat-square)](https://rubygems.org/gems/rack-smart_compress)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%203.0-ruby.svg?style=flat-square)](https://www.ruby-lang.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](https://opensource.org/licenses/MIT)

`Rack::SmartCompress` replaces traditional `Rack::Deflater` by automatically negotiating modern, hyper-efficient compression algorithms like **Zstd** and **Brotli** with fallback to Gzip. It applies smart payload thresholding, LRU caching, and content-type filtering to cut outgoing server bandwidth by up to **40%** with zero setup friction.

---

## 🥊 Why `Rack::SmartCompress` vs `Rack::Deflater`?

| Feature | `Rack::Deflater` | `rack-brotli` | `Rack::SmartCompress` ⚡ |
| :--- | :---: | :---: | :---: |
| **Zstandard (`zstd`) Support** | ❌ | ❌ | ✅ **Native** |
| **Brotli (`br`) Support** | ❌ | ✅ | ✅ **Native** |
| **Gzip & Deflate Fallback** | ✅ | ❌ | ✅ **Native** |
| **Chunked Stream Compression** | ⚠️ Buffers | ❌ | ✅ **True Chunk Streaming** |
| **Pre-Compressed Static Assets (`.zst`, `.br`, `.gz`)** | ❌ | ❌ | ✅ **0% CPU Overhead** |
| **RFC 9110 ETag Weakening (`W/"..."`)** | ⚠️ Partial | ❌ | ✅ **RFC Compliant** |
| **`Cache-Control: no-transform` Respect** | ❌ | ❌ | ✅ **RFC Compliant** |
| **206 Partial Content / Range Protection** | ⚠️ Buggy | ❌ | ✅ **Protected** |
| **In-Memory LRU Payload Cache** | ❌ | ❌ | ✅ **Thread-Safe LRU** |
| **Dynamic CPU Load Advisor** | ❌ | ❌ | ✅ **Automatic** |
| **Rails Railtie Auto-Inject** | ❌ | ❌ | ✅ **`config.smart_compress`** |
| **ActiveSupport Telemetry Instrumentation** | ❌ | ❌ | ✅ **Built-in** |

---

## ✨ Features

- 🏎️ **Next-Gen Encodings:** Native support for **Zstandard (`zstd`)**, **Brotli (`br`)**, **Gzip**, and **Deflate**.
- 📦 **Pre-Compressed Static Assets:** `Rack::SmartCompress::Static` serves build-time `.zst`, `.br`, and `.gz` files with **0% runtime CPU overhead**.
- 🌊 **True Chunked Streaming:** Progressive, non-buffering stream compression for Zstandard (`Zstd::StreamingCompress`), Brotli (`Brotli::Compressor`), and Gzip.
- 🧠 **Smart Payload Filtering:** Automatically skips tiny payloads (< 1KB) where compression overhead increases latency without savings.
- 🛡️ **RFC 9110 & 9111 Compliant:** Automatic strong-to-weak ETag conversion (`W/"..."`), `Cache-Control: no-transform` respect, and 206 Partial Content / `Content-Range` protection.
- 🛑 **Media & Binary Exclusion:** Skips already compressed assets (`images`, `audio`, `video`, `zip`, `pdf`).
- ⚡ **Auto-Negotiation:** Respects HTTP `Accept-Encoding` quality weights (`qvalue`) and `*` wildcard sent by modern browsers and HTTP clients.
- 📦 **Rails Auto-Integration:** Includes a built-in Railtie with `config.smart_compress` support.
- 📊 **Telemetry & Observability:** Emits `rack_smart_compress.compress` notifications via `ActiveSupport::Notifications` or custom callbacks.
- 🛡️ **Rack 2 & Rack 3 Compatible:** Fully compliant with modern Rack specifications.

---

## 📦 Installation

Add this line to your application's `Gemfile`:

```ruby
gem "rack-smart_compress"
```

To enable native **Brotli** and **Zstandard** compression drivers, add their gems to your Gemfile:

```ruby
gem "brotli", "~> 0.4"     # Optional: enables Brotli (br) compression
gem "zstd-ruby", "~> 1.5"  # Optional: enables Zstandard (zstd) compression
```

Then execute:

```bash
$ bundle install
```

---

## 🚀 Quick Start

### Ruby on Rails Integration

In Rails, `Rack::SmartCompress` automatically attaches to your middleware stack via Railtie.

Configure options in `config/initializers/smart_compress.rb` or `config/environments/production.rb`:

```ruby
Rails.application.configure do
  config.smart_compress.min_size = 1024                  # Only compress responses >= 1 KB
  config.smart_compress.encodings = %w[zstd br gzip deflate]
  config.smart_compress.cache = true                     # Enable in-memory LRU payload caching
  config.smart_compress.cache_size = 200                 # Cache up to 200 warm response payloads
  config.smart_compress.dynamic_levels = true            # Dynamically drop compression levels under high CPU load
  config.smart_compress.if = ->(env, status, headers) { env["HTTP_X_NO_COMPRESS"].nil? }

  # Optional: Enable pre-compressed static asset serving (.zst, .br, .gz)
  config.smart_compress.static_assets = true
  config.smart_compress.static_headers = { "Cache-Control" => "public, max-age=31536000, immutable" }
end
```

### Global Configuration (Sinatra / Hanami / Pure Rack)

```ruby
# config.ru or boot.rb
require "rack/smart_compress"

Rack::SmartCompress.configure do |config|
  config.min_size = 1024
  config.cache = true
  config.encodings = %w[zstd br gzip]
end

use Rack::SmartCompress::Middleware
run YourRackApp.new
```

### Serving Pre-Compressed Static Assets (`.zst`, `.br`, `.gz`)

If your asset pipeline (Vite Ruby, Propshaft, Webpacker, esbuild) pre-compresses static assets into `.zst`, `.br`, and `.gz` files:

```ruby
# config.ru
use Rack::SmartCompress::Static,
  root: "public",
  urls: ["/assets", "/packs"],
  headers: { "Cache-Control" => "public, max-age=31536000, immutable" }

run YourRackApp.new
```

When a browser requests `/assets/bundle.js` with `Accept-Encoding: zstd, br, gzip`, `Rack::SmartCompress::Static` will:
1. Detect `bundle.js.zst` on disk.
2. Serve it directly via streaming IO with **0% runtime CPU usage**.
3. Set `Content-Type: application/javascript`, `Content-Encoding: zstd`, and `Vary: Accept-Encoding`.

---

## ⚙️ Configuration Options

| Option | Default | Description |
| :--- | :--- | :--- |
| `min_size` | `1024` (1 KB) | Minimum response body size in bytes required to trigger compression. |
| `encodings` | `%w[zstd br gzip deflate]` | Priority order of compression algorithms to allow. |
| `cache` | `false` | Enable thread-safe in-memory LRU payload caching for warm endpoints. |
| `cache_size` | `200` | Maximum number of compressed payloads to cache in memory. |
| `dynamic_levels` | `false` | Automatically drops compression levels under high CPU load to preserve low latency. |
| `if` | `nil` | Proc/Lambda `->(env, status, headers)` returning true to compress. |
| `unless` | `nil` | Proc/Lambda `->(env, status, headers)` returning true to skip compression. |
| `mime_types` | `[text/*, application/json, ...]` | List of compressible MIME types. Supports `+json` and `+xml` suffixes. |
| `exclude_mime_types` | `[image/*, video/*, audio/*, zip, pdf]` | List of MIME type prefixes to explicitly skip. |
| `zstd_level` | `3` | Zstandard compression level (1-22). |
| `brotli_level` | `4` | Brotli compression quality level (0-11). |
| `instrumentation` | `true` | Emits `rack_smart_compress.compress` via `ActiveSupport::Notifications` or block callback. |
| `static_assets` | `false` | Enables pre-compressed static asset serving in Rails. |
| `static_root` | `"public"` | Root directory for static asset resolution. |
| `static_urls` | `["/"]` | URL prefixes intercepted by static pre-compressed asset middleware. |

---

## 📊 Benchmark & Performance

Run the built-in benchmark script to compare performance against your payloads:

```bash
$ bundle exec rake benchmark
```

**Sample Benchmark Output (108 KB JSON API payload):**

```
============================================================
  Rack::SmartCompress Performance Benchmark  
============================================================
Algorithm    | Compressed Size | Compression % | Avg Speed (ms)
------------------------------------------------------------
Zstd         | 3.07 KB         | 97.16%        | 0.085 ms
Brotli       | 2.66 KB         | 97.54%        | 0.355 ms
Gzip         | 8.16 KB         | 92.45%        | 0.498 ms
Deflate      | 8.15 KB         | 92.46%        | 0.478 ms
============================================================
```

- **Zstandard (`zstd`)** delivers the fastest compression/decompression throughput (sub-0.1ms).
- **Brotli (`br`)** delivers the smallest payload size over the wire.

---

## 🧪 Running Tests

Run all unit and end-to-end integration tests:

```bash
$ bundle exec rake
```

Or individual suites:

```bash
$ bundle exec rspec       # RSpec unit tests (45 examples)
$ bundle exec rake e2e    # Comprehensive End-to-End integration suite (18 tests)
```

---

## 📄 License

This gem is available as open source under the terms of the [MIT License](LICENSE.txt).
