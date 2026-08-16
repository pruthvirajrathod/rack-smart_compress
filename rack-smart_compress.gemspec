# frozen_string_literal: true

require_relative "lib/rack/smart_compress/version"

Gem::Specification.new do |spec|
  spec.name          = "rack-smart_compress"
  spec.version       = Rack::SmartCompress::VERSION
  spec.authors       = ["Pruthviraj Rathod"]

  spec.summary       = "High-performance Zstd, Brotli, and Gzip dynamic HTTP compression middleware for Rack & Rails."
  spec.description   = "Rack::SmartCompress intelligently compresses HTTP responses using Zstandard (zstd), Brotli (br), and Gzip with smart payload thresholding, content-type filtering, and zero setup overhead."
  spec.homepage      = "https://github.com/pruthvirajrathod/rack-smart_compress"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/pruthvirajrathod/rack-smart_compress"
  spec.metadata["changelog_uri"] = "https://github.com/pruthvirajrathod/rack-smart_compress/blob/main/CHANGELOG.md"

  spec.files         = Dir["lib/**/*", "LICENSE.txt", "README.md", "CHANGELOG.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "rack", ">= 2.0.0"

  spec.add_development_dependency "bundler", ">= 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "rack-test", "~> 2.1"
  spec.add_development_dependency "brotli", "~> 0.4"
  spec.add_development_dependency "zstd-ruby", "~> 1.5"
end
