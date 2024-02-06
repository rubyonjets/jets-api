module Jets::Api
  module Logging
    delegate :logger, to: "Jets::Api"
    def log
      logger
    end
  end
end
