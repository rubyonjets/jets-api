require "gems"

module Jets::Api::Gems::Extract
  class Gem < Base
    VERSION_PATTERN = /-(\d+\.\d+.*)/
    include Jets::Api

    def run
      say "Will download and extract gem: #{full_gem_name}"
      clean_downloads(:gems) if @options[:clean]
      zipfile_path = download_gem
      remove_current_gem if Jets.config.pro.clean || Jets.config.gems.clean
      unzip_file(zipfile_path)
      say("Gem #{full_gem_name} unpacked at #{project_root}")
    end

    def unzip_file(zipfile_path)
      dest = "#{Jets.build_root}/stage/opt"
      say "Unpacking into #{dest}"
      FileUtils.mkdir_p(dest)
      unzip(zipfile_path, dest)
    end

    # ensure that we always have the full gem name
    def full_gem_name
      return @full_gem_name if @full_gem_name

      if @name.match(VERSION_PATTERN)
        @full_gem_name = @name
        return @full_gem_name
      end

      # name doesnt have a version yet, so grab the latest version and add it
      version = Api.versions(@name).first
      @full_gem_name = "#{@name}-#{version["number"]}"
    end

    def gem_name
      full_gem_name.gsub(VERSION_PATTERN, "") # folder: byebug
    end

    # Downloads and extracts the linux gem into the proper directory.
    # Extracts to: . (current directory)
    #
    # It produces a `bundled` folder.
    # The folder contains the re-produced directory structure. Example with
    # the gem: byebug-9.1.0
    #
    #   vendor/gems/ruby/2.5.0/extensions/x86_64-darwin-16/2.5.0-static/byebug-9.1.0
    #
    def download_gem
      # download - also move to /tmp/jets/demo/compiled_gems folder
      begin
        @retries ||= 0
        url = gem_url
        basename = File.basename(url).gsub(/\?.*/, "") # remove query string info
        tarball_dest = download_file(url, download_path(basename))
      rescue OpenURI::HTTPError => e
        url_without_query = url.gsub(/\?.*/, "")
        puts "Error downloading #{url_without_query}"
        @retries += 1
        if @retries < 3
          sleep 1
          puts "Retrying download. Retry attempt: #{@retries}"
          retry
        else
          raise e
        end
      end

      unless tarball_dest
        message = "Url: #{url} not found"
        if @options[:exit_on_error]
          say message
          exit
        else
          raise NotFound.new(message)
        end
      end
      say "Downloaded to: #{tarball_dest}"
      tarball_dest
    end

    # full_gem_name: byebug-9.1.0
    def gem_url
      resp = Jets::Api::Gems.download(gem_name: full_gem_name)
      if resp["download_url"]
        resp["download_url"]
      else
        puts resp["message"].color(:red)
        exit 1
      end
    end

    def download_path(filename)
      "#{@downloads_root}/downloads/gems/#{filename}"
    end

    # Finds any currently install gems that matched with the gem name and version
    # and remove them first.
    # We clean up the current install gems first in case it was previously installed
    # and has different *.so files that can be accidentally required.  This
    # happened with the pg gem.
    def remove_current_gem
      say "Removing current #{full_gem_name} gem installation:"
      gem_dirs = Dir.glob("#{project_root}/**/*").select do |path|
        File.directory?(path) &&
          path =~ %r{vendor/gems} &&
          File.basename(path) == full_gem_name
      end
      gem_dirs.each do |dir|
        say "  rm -rf #{dir}"
        FileUtils.rm_rf(dir)
      end
    end
  end
end
