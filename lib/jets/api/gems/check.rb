# Assumes gems were just built and checks the filesystem to find and detect for
# compiled gems.  Unless the cli option is set to true, the it'll just check
# based on the gemspecs.
class Jets::Api::Gems
  class Check
    extend Memoist

    attr_reader :missing_gems
    def initialize(options={})
      @options = options
      @missing_gems = [] # keeps track of gems that are not found in any of the Jets Api source
    end

    delegate :endpoint, to: Jets::Api

    def run!
      puts "Jets API endpoint: #{endpoint}" if @options[:verbose]
      run(exit_early: true)
    end

    # Checks whether the gem is found at the Jets Api source.
    def run(exit_early: false)
      puts "Checking project for compiled gems..."
      compiled_gems.each do |gem_name|
        puts "Checking #{gem_name}..." if @options[:verbose]
        exist = Jets::Api::Gems::Exist.new
        data = exist.check(gem_name)
        @missing_gems << data unless data["exist"]
      end

      if exit_early && !@missing_gems.empty?
        # Exits early if not all the linux gems are available.
        # Better to error now than deploy a broken package to AWS Lambda.
        # Apivide users with message about missing gems.
        puts missing_message
        names = @missing_gems.map {|i| i['gem_name']}
        Report.new(@options).report(names) if agree.yes?
        exit 1
      end

      compiled_gems
    end

    def missing?
      !@missing_gems.empty?
    end

    def missing_message
      template = <<-EOL
Your project requires compiled gems that are not currently available.  Unavailable precompiled gems:
<% missing_gems.each do |missing_gem|
   available = missing_gem['available'].reject { |v| missing_gem['gem_name'].include?(v) }
%>
* Unavailable: <%= missing_gem['gem_name'] -%> Available versions: <%= available.join(' ') %>
<% end %>
Your current Jets API endpoint: #{endpoint}

Jets is unable to build a deployment package that will work on AWS Lambda without the required precompiled gems.
To remedy this, you can:

* Use another gem that does not require compilation.
* Create your own custom layer with the gem: http://rubyonjets.com/docs/extras/custom-lambda-layers/
<% if agree.yes? -%>
* No need to report this to us, as we've already been notified.
* Usually, missing gems can be built within a few minutes.
* Some gems may take days or even longer.
<% elsif agree.no? -%>
* You have choosen not to report data to Jets Api so we will not be notified about these missing gems.
* You can edit ~/.jets/agree to change this.
* Reporting gems generally allows Jets Api to build the missing gems within a few minutes.
* You can try redeploying again after a few minutes.
* Non-reported gems may take days or even longer to be built.
<% end -%>

Compiled gems usually take some time to figure out how to build as they each depend on different libraries and packages.
More info: http://rubyonjets.com/docs/jets-pro/

EOL
      erb = ERB.new(template, trim_mode: '-') # trim mode https://stackoverflow.com/questions/4632879/erb-template-removing-the-trailing-line
      erb.result(binding)
    end

    def agree
      Jets::Api::Agree.new
    end
    memoize :agree

    # Context, observations, and history:
    #
    # Two ways to check if gem is compiled.
    #
    #     1. compiled_gem_paths - look for .so and .bundle extension files in the folder itself.
    #     2. gemspec - uses the gemspec metadata.
    #
    # Observations:
    #
    #     * The gemspec approach generally finds more compiled gems than the compiled_gem_paths approach.
    #     * So when using the compiled_gem_paths some compiled are missed and not properly detected like http-parser.
    #     * However, some gemspec found compiled gems like json are weird and they don't work when they get replaced.
    #
    # History:
    #
    #     * Started with compiled_gem_paths approach
    #     * Tried to gemspec approach, but ran into json-2.1.0 gem issues. bundler removes? http://bit.ly/39T8uln
    #     * Went to selective checking approach with `cli: true` option. This helped gather more data.
    #       * jets deploy - compiled_gem_paths
    #       * jets gems:check - gemspec_compiled_gems
    #     * Going back to compiled_gem_paths with:
    #       * Using the `weird_gem?` check to filter out gems removed by bundler. Note: Only happens with specific versions of json.
    #     * Keeping compiled_gem_paths for Jets Afterburner mode. Default to gemspec_compiled_gems otherwise
    #
    #
    def compiled_gems
      # @use_gemspec option  finds compile gems with Gem::Specification
      # The normal build process does not use this and checks the file system.
      # So @use_gemspec is only used for this command:
      #
      #   jets gems:check
      #
      # This is because it seems like some gems like json are remove and screws things up.
      # We'll filter out for the json gem as a hacky workaround, unsure if there are more
      # gems though that exhibit this behavior.
      if @options[:use_gemspec] == false
        # Afterburner mode
        compiled_gems = compiled_gem_paths.map { |p| gem_name_from_path(p) }.uniq
        # Double check that the gems are also in the gemspec list since that
        # one is scoped to Bundler and will only included gems used in the project.
        # This handles the possiblity of stale gems leftover from previous builds
        # in the cache.
        # TODO: figure out if we need
        # compiled_gems.select { |g| gemspec_compiled_gems.include?(g) }
      else
        # default when use_gemspec not set
        #
        #     jets deploy
        #     jets gems:check
        #
        gems = gemspec_compiled_gems
        gems += other_compiled_gems
        gems += registered_compiled_gems
        gems.uniq
      end
    end

    # note 2.7.0/gems vs 2.7.0/extensions
    #
    #   /tmp/jets/demo/stage/opt/ruby/gems/2.7.0/gems/nokogiri-1.11.1-x86_64-darwin/
    #   /tmp/jets/demo/stage/opt/ruby/gems/2.7.0/extensions/x86_64-linux/2.7.0/
    #
    # Also the platform is appended to the gem folder now
    #
    #   /tmp/jets/demo/stage/opt/ruby/gems/2.7.0/gems/nokogiri-1.11.1-x86_64-darwin
    #   /tmp/jets/demo/stage/opt/ruby/gems/2.7.0/gems/nokogiri-1.11.1-x86_64-linux
    #
    # On new 2021 macbook with m1 chip: the gems are being saved in a folder like so:
    #   nokogiri-1.12.5-arm64-darwin
    # The GEM_REGEXP accounts for this case.
    GEM_REGEXP = /-(arm|x)\d+.*-(darwin|linux)/
    def other_compiled_gems
      paths = Dir.glob("#{Jets.build_root}/stage/opt/ruby/gems/#{Jets::Api::Gems.ruby_folder}/gems/*{-darwin,-linux}")
      paths.map { |p| File.basename(p).sub(GEM_REGEXP,'') }
    end

    def registered_compiled_gems
      registered = Jets::Api::Gems::Registered.new
      registered_gems = registered.all # no version numbers in this list

      paths = Dir.glob("#{Jets.build_root}/stage/opt/ruby/gems/#{Jets::Api::Gems.ruby_folder}/gems/*")
      project_gems = paths.map { |p| File.basename(p).sub(GEM_REGEXP,'') }
      project_gems.select do |name|
        name_only = name.sub(/-\d+\.\d+\.\d+.*/,'')
        registered_gems.include?(name_only)
      end
    end

    # Use precompiled gem because the gem could have development header shared
    # object file dependencies.  The shared dependencies are packaged up as part
    # of the precompiled gem so it is available in the Lambda execution environment.
    #
    # Example paths:
    # Macosx:
    #   opt/ruby/gems/2.5.0/extensions/x86_64-darwin-16/2.5.0-static/nokogiri-1.8.1
    #   opt/ruby/gems/2.5.0/extensions/x86_64-darwin-16/2.5.0-static/byebug-9.1.0
    # Official AWS Lambda Linux AMI:
    #   opt/ruby/gems/2.5.0/extensions/x86_64-linux/2.5.0-static/nokogiri-1.8.1
    # Circleci Ubuntu based Linux:
    #   opt/ruby/gems/2.5.0/extensions/x86_64-linux/2.5.0/pg-0.21.0
    def compiled_gem_paths
      Dir.glob("#{Jets.build_root}/stage/opt/ruby/gems/*/extensions/**/**/*.{so,bundle}")
    end

    # Input: opt/ruby/gems/2.5.0/extensions/x86_64-darwin-16/2.5.0-static/byebug-9.1.0
    # Output: byebug-9.1.0
    def gem_name_from_path(path)
      regexp = %r{opt/ruby/gems/\d+\.\d+\.\d+/extensions/.*?/.*?/(.*?)/}
      path.match(regexp)[1] # gem_name
    end

    # So can also check for compiled gems with Gem::Specification
    # But then also includes the json gem, which then bundler removes?
    # We'll figure out the the json gems.
    # https://gist.github.com/tongueroo/16f4aa5ac5393424103347b0e529495e
    #
    # This is a faster way to check but am unsure if there are more gems than just
    # json that exhibit this behavior. So only using this technique for this commmand:
    #
    #   jets gems:check
    #
    # Thanks: https://gist.github.com/aelesbao/1414b169a79162b1d795 and
    #   https://stackoverflow.com/questions/5165950/how-do-i-get-a-list-of-gems-that-are-installed-that-have-native-extensions
    def gemspec_compiled_gems
      specs = Gem::Specification.each.select { |spec| spec.extensions.any?  }
      specs.reject! { |spec| weird_gem?(spec.name) }
      specs.map(&:full_name)
    end

    # Filter out the weird special case gems that bundler deletes?
    # Apibably to fix some bug.
    #
    #   $ bundle show json
    #   The gem json has been deleted. It was installed at:
    #   /home/ec2-user/.rbenv/versions/2.5.1/lib/ruby/gems/2.5.0/gems/json-2.1.0
    #
    def weird_gem?(name)
      command = "bundle show #{name} 2>&1"
      output = `#{command}`
      output.include?("has been deleted")
    end
  end
end
