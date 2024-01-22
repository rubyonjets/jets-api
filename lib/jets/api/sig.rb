module Jets::Api
  class Sig < Base
    class << self
      def create(params={})
        params = global_params.merge(params)
        api.post("sigs", params)
      end

      def update(id, params={})
        params = global_params.merge(params)
        api.put("sigs/#{id}", params)
      end
    end
  end
end
