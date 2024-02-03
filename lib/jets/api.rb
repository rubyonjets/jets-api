require "jets"

$:.unshift(File.expand_path("../../", __FILE__))
require "jets/api/autoloader"
Jets::Api::Autoloader.setup

require "memoist"
require "yaml"

require "cli-format"
CliFormat.default_format = "table"

module Jets
  module Api
    class RequestError < StandardError
      def initialize(original_error)
        message = "#{original_error.class} #{original_error.message}"
        super(message)
      end
    end

    extend Memoist
    def api
      Jets::Api::Client.new
    end
    memoize :api

    def token
      Jets::Api::Config.instance.token
    end
    module_function :token

    def endpoint
      return ENV['JETS_API'] if ENV['JETS_API']
      # Avoid production calls for now
      return "http://localhost:8881/v2"

      major = Jets::VERSION.split('.').first.to_i
      if major >= 6
        'https://api.rubyonjets.com/v2'
      else
        'https://api.rubyonjets.com/v1'
      end
    end
    module_function :endpoint
  end
end
