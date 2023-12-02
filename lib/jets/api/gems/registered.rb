class Jets::Api::Gems
  class Registered
    include Jets::Api

    def all
      resp = Jets::Api::Gems.registered
      resp["gems"]
    rescue Jets::Api::RequestError => e
      puts "WARNING: #{e.class}: #{e.message}"
      []
    end
  end
end