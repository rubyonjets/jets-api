require "net/http"

class Jets::Api::Gems
  class Report
    include Jets::Api

    def initialize(options = {})
      @options = options
    end

    def report(gems)
      threads = []
      gems.each do |gem_name|
        threads << Thread.new do
          Jets::Api::Gems.report(gem_name: gem_name)
        end
      end
      # Wait for request to finish because the command might finish before
      # the Threads even send the request. So we join them just case
      threads.each(&:join)
    end
  end
end
