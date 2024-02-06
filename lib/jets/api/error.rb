module Jets::Api
  class Error < StandardError
    def initialize(message = nil, http_status: nil, http_body: nil,
                   json_body: nil, http_headers: nil, code: nil)
      @message = message
      @http_status = http_status
      @http_body = http_body
      @http_headers = http_headers || {}
      @json_body = json_body
      @code = code
      @request_id = @http_headers["request-id"]
      super(message)
    end

    class Connection < Error
    end

    class BadRequest < Error
    end

    class Unauthorized < Error
    end

    class Forbidden < Error
    end

    class NotFound < Error
    end

    class TooManyRequests < Error
    end

    class InternalServerError < Error
    end

    class ServiceUnavailable < Error
    end
  end
end
