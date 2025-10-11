module Jets::Api
  class Project < Base
    class << self
      def list(params = {})
        params = global_params.merge(params)
        api.get("projects", params)
      end
    end
  end
end
