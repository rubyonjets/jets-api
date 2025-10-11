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
      cleanup_incompatible_platform_variants
    end

    # Removes incompatible platform variants to prevent RubyGems from choosing the wrong one
    # For AWS Lambda, we want to keep only x86_64-linux variants and remove others
    def cleanup_incompatible_platform_variants
      gems_dir = "#{Jets.build_root}/stage/opt/ruby/gems/#{Jets::Api::Gems.ruby_folder}/gems"
      specs_dir = "#{Jets.build_root}/stage/opt/ruby/gems/#{Jets::Api::Gems.ruby_folder}/specifications"
      return unless Dir.exist?(gems_dir)

      # Find all gem directories for this gem name
      gem_dirs = Dir.glob("#{gems_dir}/#{gem_name}-*").select do |path|
        File.directory?(path) && File.basename(path).start_with?(gem_name)
      end

      # Group by base gem name (without platform suffix)
      gem_groups = {}
      gem_dirs.each do |dir|
        name = File.basename(dir)
        # Handle platform-specific gem names like nokogiri-1.18.10-x86_64-linux-gnu
        base_name = name.sub(/-(x86_64-linux-gnu|aarch64-linux-gnu|arm64-linux-gnu|i386-linux-gnu|powerpc-linux-gnu|sparc-linux-gnu|mips-linux-gnu|riscv-linux-gnu|loongarch-linux-gnu|sw_64-linux-gnu|hppa-linux-gnu|ia64-linux-gnu|s390-linux-gnu|x86_64|arm64|aarch64|i386|powerpc|sparc|mips|riscv|loongarch|sw_64|hppa|ia64|s390).*/, "")
        gem_groups[base_name] ||= []
        gem_groups[base_name] << {dir: dir, name: name}
      end

      # For each gem group, clean up platform variants
      gem_groups.each { |base_name, variants| cleanup_gem_variants(base_name, variants, specs_dir) }
    end

    # Clean up platform variants for a specific gem group
    def cleanup_gem_variants(base_name, variants, specs_dir)
      return if variants.size <= 1 # No cleanup needed if only one variant

      say "Found #{variants.size} platform variants for #{base_name}:"
      variants.each { |v| say "  - #{v[:name]}" }

      # Always favor base gem variants (without platform suffix) - these are from Jets API
      # Remove all platform-specific variants
      base_variants = variants.select { |v| !v[:name].match(/-[^-]+-[^-]+$/) }
      platform_variants = variants - base_variants

      keep_variants = base_variants.any? ? base_variants : variants
      remove_variants = platform_variants

      say "Keeping: #{keep_variants.map { |v| v[:name] }.join(", ")}"
      say "Removing: #{remove_variants.map { |v| v[:name] }.join(", ")}"

      # Remove incompatible variants
      remove_variants.each do |variant|
        say "Removing incompatible variant: #{variant[:name]}"
        FileUtils.rm_rf(variant[:dir])

        # Also remove the corresponding gemspec
        gemspec_path = "#{specs_dir}/#{variant[:name]}.gemspec"
        FileUtils.rm_f(gemspec_path) if File.exist?(gemspec_path)
      end
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
