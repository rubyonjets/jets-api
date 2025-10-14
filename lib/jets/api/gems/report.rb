require "net/http"

class Jets::Api::Gems
  class Report
    include Jets::Api

    def initialize(options = {})
      @options = options
    end

    def report(gems)
      gems.each do |gem_name|
        Jets::Api::Gems.report(gem_name: gem_name)
      end
    end
  end
end
