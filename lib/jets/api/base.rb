module Jets::Api
  class Base
    include Jets::Api
    delegate :global_params, to: :class
    class << self
      include Jets::Api

      def global_params
        Jets.boot
        params = {}
        params[:jets_env] = Jets.env.to_s
        params[:jets_extra] = Jets.extra.to_s if Jets.extra
        params[:name] = Jets.project_namespace
        params[:region] = Jets.aws.region
        params[:account] = Jets.aws.account
        params[:project_id] = Jets.project_name
        params[:jets_api_version] = Jets::Api::VERSION
        params[:jets_version] = Jets::VERSION
        params[:ruby_version] = RUBY_VERSION
        params[:ruby_folder] = Jets::Api::Gems.ruby_folder
        params
      end
    end
  end
end
