module Jets::Api
  class Sig < Base
    class << self
      def create(params={})
        params = global_params.merge(params)
        resp = api.post("sigs", params)
        puts "DEBUG resp:"
        pp resp
        resp
      end

      def update(id, params={})
        params = global_params.merge(params)
        api.put("sigs/#{id}", params)
      end
    end
  end
end
