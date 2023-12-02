module Jets::Api
  class Gems < Base
    class << self
      def download(params={})
        params = global_params.merge(params)
        api.post("gems/download", params)
      end

      def exist(params={})
        params = global_params.merge(params)
        api.post("gems/exist", params)
      end

      def report(params={})
        params = global_params.merge(params)
        api.post("gems/report", params)
      end

      def registered(params={})
        params = global_params.merge(params)
        api.post("gems/registered", params)
      end

      def ruby_folder
        major, minor, _ = RUBY_VERSION.split('.')
        [major, minor, '0'].join('.') # 2.5.1 => 2.5.0
      end
    end
  end
end
