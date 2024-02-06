module Jets::Api::Core
  class Response
    attr_reader(
      :http_body,
      :http_headers,
      :http_status,
      :request_id,
    )
    def initialize(http_resp)
      @http_resp = http_resp
      @http_body = http_resp.body
      @http_headers = http_resp.to_hash
      @http_status = http_resp.code.to_i
      @request_id = http_resp["request-id"]
    end

    def data
      JSON.parse(@http_resp.body, symbolize_names: true)
    rescue JSON::ParserError
      raise general_api_error(@http_resp)
    end

    def general_api_error(http_resp)
      puts "general_api_error CALLED".color(:purple)
      Jets::Api::Error.new(http_resp)
    end
  end
end
