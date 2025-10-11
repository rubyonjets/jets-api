require "open-uri"

module Jets::Api::Gems::Extract
  class Base
    class NotFound < RuntimeError; end

    attr_reader :project_root
    def initialize(name, options = {})
      @name = name
      @options = options
      ruby_folder = Jets::Api::Gems.ruby_folder
      @downloads_root = options[:downloads_root] || "/tmp/jets/#{Jets.project_name}/jets-api/#{ruby_folder}"
    end

    def clean_downloads(folder)
      path = "#{@downloads_root}/downloads/#{folder}"
      say "Removing cache: #{path}"
      FileUtils.rm_rf(path)
    end

    # Using ` > /dev/null 2>&1` to suppress stderr message:
    #
    #    lchmod (file attributes) error: Function not implemented
    #
    def unzip(zipfile_path, parent_folder_dest)
      sh("cd #{parent_folder_dest} && unzip -qo #{zipfile_path} > /dev/null 2>&1")
    end

    def sh(command)
      say "=> #{command}".color(:green)
      success = system(command)
      abort("Command Failed #{command}") unless success
      success
    end

    # Returns the dest path
    def download_file(url, dest)
      if File.exist?(dest) && ENV["JETS_API_FORCE_DOWNLOAD"].blank?
        say "File already downloaded #{dest}"
        return dest
      end

      say "Downloading..."
      downloaded = URI.open(url, "rb") { |read_file| read_file.read }

      FileUtils.mkdir_p(File.dirname(dest)) # ensure parent folder exists

      File.binwrite(dest, downloaded)

      dest
    end

    @@log_level = :info # default level is :info
    # @@log_level = :debug # uncomment to debug
    def log_level=(val)
      @@log_level = val
    end

    def say(message, level = :info)
      enabled = @@log_level == :debug || level == :debug
      puts(message) if enabled
    end
  end
end
