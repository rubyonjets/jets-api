module Jets::Api
  class Stack < Base
    class << self
      def list(params={})
        params = global_params.merge(params)
        api.get("stacks", params)
      end

      def retrieve(id, params={})
        params = global_params.merge(params)
        api.get("stacks/#{id}", params)
      end
    end
  end
end
