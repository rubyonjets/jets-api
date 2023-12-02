class Jets::Api::Gems
  class Exist
    include Jets::Api

    # gem_name IE: nokogiri-1.1.1
    def check(gem_name)
      Jets::Api::Gems.exist(gem_name: gem_name) # data = {"exist": ..., "available"}
    rescue Jets::Api::RequestError => e
      puts "WARNING: #{e.class}: #{e.message}"
      {"exist" => false, gem_name: gem_name, available: [] }
    end
  end
end
