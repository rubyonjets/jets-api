require "aws-sdk-core"

module Jets::Api
  module Core
    extend Memoist

    @@max_retries = 3

    # Always translate raw json response to ruby Hash
    def request(klass, path, data = {})
      raw_response = data.delete(:raw_response)
      url = url(path)
      req = build_request(klass, url, data)
      @retries = 0
      begin
        resp = http.request(req) # send request
        raw_response ? resp : load_json(url, resp)
      rescue SocketError, OpenURI::HTTPError, OpenSSL::SSL::SSLError, Errno::ECONNREFUSED => e
        @retries += 1
        if @retries <= @@max_retries
          delay = 2**@retries
          puts "Error: #{e.class} #{e.message} retrying after #{delay} seconds..." if ENV["JETS_API_DEBUG"]
          sleep delay
          retry
        else
          puts "Error: #{e.class} #{e.message} giving up after #{@retries} retries"
          raise Jets::Api::RequestError.new(e)
        end
      end
    end

    def build_request(klass, url, data = {})
      req = klass.new(url) # url includes query string and uri.path does not, must used url
      set_headers!(req)
      if [Net::HTTP::Delete, Net::HTTP::Patch, Net::HTTP::Post, Net::HTTP::Put].include?(klass)
        text = JSON.dump(data)
        req.body = text
        req.content_length = text.bytesize
      end
      req
    end

    def set_headers!(req)
      req["Authorization"] = token if token
      req["x-account"] = account if account
      req["Content-Type"] = "application/vnd.api+json"
    end

    def token
      Jets::Api.token
    end

    def load_json(url, res)
      uri = URI(url)
      if ENV["JETS_API_DEBUG"]
        puts "res.code #{res.code}"
        puts "res.body #{res.body}"
      end
      if processable?(res.code)
        JSON.load(res.body)
      else
        puts "Error: Non-successful http response status code: #{res.code}"
        puts "headers: #{res.each_header.to_h.inspect}"
        puts "Jets API #{url}" if ENV["JETS_API_DEBUG"]
        raise "Jets API called failed: #{uri.host}"
      end
    end

    # 422 Unprocessable Entity: Server understands the content type of the request entity, and
    # the syntax of the request entity is correct, but it was unable to process the contained
    # instructions.
    def processable?(http_code)
      http_code =~ /^2/ || http_code =~ /^4/
    end

    def http
      uri = URI(endpoint)
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = http.read_timeout = 30
      if uri.scheme == "https"
        http.use_ssl = true
        # Fix for Ruby 3.4+ where SSL context is frozen by default
        # Create a new SSL context to avoid frozen object modification
        if http.respond_to?(:ssl_context=)
          http.ssl_context = OpenSSL::SSL::SSLContext.new
        end
      end
      http
    end
    memoize :http

    # API does not include the /. IE: https://app.terraform.io/api/v2
    def url(path)
      "#{endpoint}/#{path}"
    end

    def get(path, query = {})
      path = path_with_query(path, query)
      request(Net::HTTP::Get, path, raw_response: query[:raw_response])
    end

    def path_with_query(path, query = {})
      return path if query.empty?
      separator = path.include?("?") ? "&" : "?"
      "#{path}#{separator}#{query.to_query}"
    end

    def post(path, data = {})
      request(Net::HTTP::Post, path, data)
    end

    def patch(path, data = {})
      request(Net::HTTP::Patch, path, data)
    end

    def delete(path, data = {})
      request(Net::HTTP::Delete, path, data)
    end

    def account
      sts.get_caller_identity.account
    rescue
      nil
    end
    memoize :account

    def sts
      Aws::STS::Client.new
    end
    memoize :sts
  end
end
