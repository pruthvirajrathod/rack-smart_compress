# frozen_string_literal: true

require "rack/mime"
require "rack/utils"
require "time"

module Rack
  module SmartCompress
    class Static
      DEFAULT_EXTENSIONS = {
        "zstd" => ".zst",
        "br"   => ".br",
        "gzip" => ".gz"
      }.freeze

      class FileBody
        attr_reader :path

        def initialize(path)
          @path = path
        end

        def each
          File.open(@path, "rb") do |file|
            while (chunk = file.read(16_384))
              yield chunk
            end
          end
        end

        def to_path
          @path
        end
      end

      attr_reader :app, :root, :urls, :encodings, :headers, :cascade

      def initialize(app, options = {})
        @app = app
        @root = File.expand_path(options.fetch(:root, "public"))
        @urls = Array(options.fetch(:urls, ["/"])).map(&:to_s)
        @encodings = options.fetch(:encodings, DEFAULT_EXTENSIONS)
        @headers = options.fetch(:headers, {})
        @cascade = options.fetch(:cascade, true)
      end

      def call(env)
        method = env["REQUEST_METHOD"]
        return @app.call(env) unless %w[GET HEAD].include?(method)

        path_info = env["PATH_INFO"].to_s
        return @app.call(env) unless url_match?(path_info)

        clean_path = Rack::Utils.clean_path_info(path_info)
        full_path = File.join(@root, clean_path)

        # Path traversal guard: ensure path is strictly inside @root
        return @app.call(env) unless safe_path?(full_path)

        accept_encoding = env["HTTP_ACCEPT_ENCODING"].to_s
        encoding, compressed_path = find_precompressed_file(full_path, accept_encoding)

        if compressed_path
          serve_file(env, full_path, compressed_path, encoding, method)
        elsif File.file?(full_path) && !@cascade
          serve_file(env, full_path, full_path, nil, method)
        else
          @app.call(env)
        end
      end

      private

      def url_match?(path)
        @urls.any? { |url| url == "/" || path.start_with?(url) }
      end

      def safe_path?(path)
        expanded = File.expand_path(path)
        expanded == @root || expanded.start_with?("#{@root}/")
      end

      def find_precompressed_file(base_path, accept_encoding)
        return [nil, nil] if accept_encoding.strip.empty?

        accepted = parse_accepted_encodings(accept_encoding)

        accepted.each do |enc|
          ext = @encodings[enc]
          next unless ext

          candidate_path = "#{base_path}#{ext}"
          return [enc, candidate_path] if File.file?(candidate_path)
        end

        [nil, nil]
      end

      def parse_accepted_encodings(header)
        encodings = {}
        header.split(",").each do |part|
          next if part.strip.empty?

          enc, qval = part.split(";").map(&:strip)
          next unless enc

          q = 1.0
          if qval && qval.start_with?("q=")
            q = qval.sub("q=", "").to_f rescue 1.0
          end

          encodings[enc.downcase] = q if q > 0.0
        end

        encodings.sort_by { |_, q| -q }.map(&:first)
      end

      def serve_file(env, original_path, served_path, encoding, method)
        stat = File.stat(served_path)
        mtime = stat.mtime.httpdate
        etag = %(W/"#{stat.mtime.to_i.to_s(16)}-#{stat.size.to_s(16)}")

        # Conditional GET checks
        if_none_match = env["HTTP_IF_NONE_MATCH"]
        if_modified_since = env["HTTP_IF_MODIFIED_SINCE"]

        if if_none_match && if_none_match == etag
          return [304, build_headers(original_path, stat, encoding, mtime, etag), []]
        end

        if if_modified_since
          begin
            since_time = Time.httpdate(if_modified_since)
            if stat.mtime <= since_time
              return [304, build_headers(original_path, stat, encoding, mtime, etag), []]
            end
          rescue ArgumentError
            # Invalid date format in header, proceed with full response
          end
        end

        res_headers = build_headers(original_path, stat, encoding, mtime, etag)
        body = method == "HEAD" ? [] : FileBody.new(served_path)

        [200, res_headers, body]
      end

      def build_headers(original_path, stat, encoding, mtime, etag)
        ext = File.extname(original_path)
        mime_type = Rack::Mime.mime_type(ext, "application/octet-stream")

        headers = {
          "content-type"   => mime_type,
          "content-length" => stat.size.to_s,
          "last-modified"  => mtime,
          "etag"           => etag,
          "vary"           => "Accept-Encoding"
        }

        headers["content-encoding"] = encoding if encoding

        @headers.each do |key, value|
          headers[key.to_s.downcase] = value
        end

        headers
      end
    end
  end
end
