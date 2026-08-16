# frozen_string_literal: true

module Rack
  module SmartCompress
    class Railtie < ::Rails::Railtie
      config.smart_compress = Configuration.new

      initializer "rack_smart_compress.insert_middleware" do |app|
        options = app.config.smart_compress.to_h

        # If static assets enabled or public directory exists, insert Static before ActionDispatch::Static
        if options[:static_assets]
          static_options = {
            root: options[:static_root] || app.paths["public"].first,
            urls: options[:static_urls] || ["/"],
            headers: options[:static_headers] || {},
            cascade: options[:static_cascade] != false
          }

          if defined?(ActionDispatch::Static) && app.middleware.include?(ActionDispatch::Static)
            app.middleware.insert_before ActionDispatch::Static, Rack::SmartCompress::Static, static_options
          else
            app.middleware.use Rack::SmartCompress::Static, static_options
          end
        end

        if defined?(ActionDispatch::Static) && app.middleware.include?(ActionDispatch::Static)
          app.middleware.insert_after ActionDispatch::Static, Rack::SmartCompress::Middleware, options
        else
          app.middleware.use Rack::SmartCompress::Middleware, options
        end
      end
    end
  end
end if defined?(::Rails::Railtie)
