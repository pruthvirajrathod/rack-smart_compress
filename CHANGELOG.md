# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-08-16

### Added
- Pre-Compressed Static Asset Middleware (`Rack::SmartCompress::Static`) supporting build-time `.zst`, `.br`, and `.gz` static files with 0% runtime CPU overhead.
- Configuration DSL via `Rack::SmartCompress.configure { |c| ... }` and `Rack::SmartCompress.configuration`.
- Dedicated Rails configuration hook via `config.smart_compress` namespace.
- RFC 9110 §8.8.1 ETag weakening (`W/"..."`) for dynamically compressed responses.
- RFC 9111 `Cache-Control: no-transform` support (skips compression when present).
- 206 Partial Content and `Content-Range` skipping to protect byte-range requests.
- Wildcard `Accept-Encoding: *` and explicit `q=0` rejection handling.
- Real chunked streaming for Brotli (`Brotli::Compressor`).
- ActiveSupport / Custom callable telemetry instrumentation (`rack_smart_compress.compress`).
- GitHub Actions CI workflow supporting Ruby 3.0, 3.1, 3.2, 3.3, and 3.4.

### Fixed
- Fixed Zstd streaming class typo (`Zstd::StreamingCompress` instead of non-existent `Zstd::StreamingCompressor`).
- Fixed `Rack::BodyProxy` streaming misclassification in Rails applications.
- Relieved LRU cache mutex contention by computing compression outside the lock.
- Optimized LRU cache key hashing to eliminate large memory allocations.
- Added 1-second load average sampling cooldown to prevent `/proc/loadavg` syscall overhead on high-frequency requests.

## [0.1.0] - Initial Release
- Initial release with Zstandard, Brotli, Gzip, and Deflate compression support.
