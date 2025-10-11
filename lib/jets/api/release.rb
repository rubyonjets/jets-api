module Jets::Api
  class Release < Base
    class << self
      def list(params = {})
        params = global_params.merge(params)
        api.get("releases", params)
      end

      def retrieve(id, params = {})
        params = global_params.merge(params)
        api.get("releases/#{id}", params)
      end

      def create(params = {})
        params = global_params.merge(params)
        api.post("releases", params)
      end
    end
  end
end
