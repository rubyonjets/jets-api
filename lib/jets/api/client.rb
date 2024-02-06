require 'aws-sdk-core'
require 'open-uri'

module Jets::Api
  class Client
    extend Memoist
    include Jets::Api::Logging
    @@max_retries = 3

    # Always translate raw json response to ruby Hash
    def execute_request(klass, path, data={}, headers={})
      url = url(path)
      req = build_request(klass, url, data, headers)
      http_resp = http_request(req)

      if handle_as_error?(http_resp.code)
        handle_error_response!(http_resp)
      end

      resp = Jets::Api::Response.new(http_resp)
      log.info "resp.data:"
      pp resp.data
      log.info "resp.http_body:"
      log.info JSON.pretty_generate(JSON.load(resp.http_body))
      exit
    end

    def handle_error_response!(http_resp)
      begin
        resp = Jets::Api::Response.new(http_resp)
        raise Jets::Api::Error, "Indeterminate error" unless resp.data[:error]
      rescue JSON::ParserError, Jets::Api::Error
        raise general_api_error(http_resp)
      end

      error = if resp.data[:error].is_a?(String) # Internal Server Error
                Jets::Api::Error.new(resp.data[:error], http_status: resp.http_status)
              else
                specific_api_error(resp)
              end

      raise error
    end

    def general_api_error(http_resp)
      Jets::Api::Error.new(http_resp.body, http_status: http_resp.code)
    end

    def specific_api_error(resp)
      message = resp.data[:error][:message]
      http_status = resp.http_status

      case resp.http_status
      when 400, 404
        Jets::Api::Error::BadRequest.new(message, http_status: http_status)
      when 401
        Jets::Api::Error::Unauthorized.new(message, http_status: http_status)
      when 403
        Jets::Api::Error::Forbidden.new(message, http_status: http_status)
      when 422
        Jets::Api::Error::UnprocessableEntity.new(message, http_status: http_status)
      when 429
        Jets::Api::Error::TooManyRequests.new(message, http_status: http_status)
      when 500
        Jets::Api::Error::InternalServerError.new(message, http_status: http_status)
      else
        Jets::Api::Error.new(message, http_status: http_status)
      end
    end

    def handle_as_error?(http_status)
      http_status.to_i >= 400
    end

    def build_request(klass, url, data={}, headers={})
      req = klass.new(url) # url includes query string and uri.path does not, must used url
      set_headers!(req)
      if [Net::HTTP::Delete, Net::HTTP::Patch, Net::HTTP::Post, Net::HTTP::Put].include?(klass)
        text = JSON.dump(data)
        # log.info "POST data:"
        # log.info JSON.pretty_generate(data)
        req.body = text
        req.content_length = text.bytesize
        req.content_type = 'application/json'
      end
      req
    end

    def http_request(req, retries=0)
      http.request(req) # send request. returns raw response
    rescue SocketError, OpenURI::HTTPError, OpenSSL::SSL::SSLError, Errno::ECONNREFUSED => error
      retries += 1
      if retries <= @@max_retries
        delay = 2**retries
        log.debug "Error: #{error.class} #{error.message} retrying after #{delay} seconds..."
        sleep delay
        retry
      else
        message = "Unexpected error #{error.class.name} communicating the Jets API. "
        message += " Request was tried #{retries} times."
        raise Jets::Api::Error::Connection,
              message + "\nNetwork error: #{error.message}"
      end
    end

    def http
      uri = URI(endpoint)
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = http.read_timeout = 30
      http.use_ssl = true if uri.scheme == 'https'
      http
    end
    memoize :http

    # API does not include the /. IE: https://app.terraform.io/api/v2
    def url(path)
      path = "/#{path}" unless path.starts_with?("/")
      "#{endpoint}#{path}"
    end

    def set_headers!(req, headers={})
      headers.each { |k,v| req[k] = v }
      req['Authorization'] = token if token
      req['x-account'] = account if account
      req['x-session'] = session if session
      req
    end

    # 422 Unprocessable Entity: Server understands the content type of the request entity, and
    # the syntax of the request entity is correct, but it was unable to process the contained
    # instructions.
    # TODO: remove? or rename to ha
    def processable?(http_code)
      http_code =~ /^2/ || http_code =~ /^4/
    end

    def session
      session_path = "#{ENV['HOME']}/.jets/session.yml"
      if File.exist?(session_path)
        data = YAML.load_file(session_path)
        data['secret_token']
      end
    end

    def token
      Jets::Api.token
    end

    def get(path, query={})
      path = path_with_query(path, query)
      execute_request(Net::HTTP::Get, path)
    end

    def path_with_query(path, query={})
      return path if query.empty?
      separator = path.include?("?") ? "&" : "?"
      "#{path}#{separator}#{query.to_query}"
    end

    def post(path, data={})
      execute_request(Net::HTTP::Post, path, data)
    end

    def put(path, data={})
      execute_request(Net::HTTP::Put, path, data)
    end

    def patch(path, data={})
      execute_request(Net::HTTP::Patch, path, data)
    end

    def delete(path, data={})
      execute_request(Net::HTTP::Delete, path, data)
    end

    def account
      sts.get_caller_identity.account rescue nil
    end
    memoize :account

    def sts
      Aws::STS::Client.new
    end
    memoize :sts

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
    memoize :endpoint
  end
end
