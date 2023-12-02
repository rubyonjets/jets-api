require 'open-uri'

module Jets::Api
  class Client
    include Core
    delegate :endpoint, to: Jets::Api
  end
end
