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
    extend Memoist
    extend self

    def api
      Jets::Api::Client.new
    end
    memoize :api

    def token
      Jets::Api::Config.instance.token
    end

    cattr_writer :logger
    def logger
      @@logger ||= default_logger
    end

    def default_logger
      logger = ActiveSupport::Logger.new($stderr)
      logger.formatter = ActiveSupport::Logger::SimpleFormatter.new # no timestamps
      logger.level = ENV['JETS_LOG_LEVEL'] || :info
      logger
    end
  end
end

require 'jets/api/error' # load all error classes
