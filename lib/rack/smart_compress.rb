# frozen_string_literal: true

require_relative "smart_compress/version"
require_relative "smart_compress/configuration"
require_relative "smart_compress/middleware"
require_relative "smart_compress/static"
require_relative "smart_compress/railtie" if defined?(Rails)

module Rack
  module SmartCompress
    class << self
      def new(app, options = {})
        Middleware.new(app, options)
      end

      def configuration
        @configuration ||= Configuration.new
      end

      def configure
        yield(configuration) if block_given?
        configuration
      end

      def reset_config!
        @configuration = Configuration.new
      end
    end
  end
end
