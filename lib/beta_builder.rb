require 'rake/tasklib'
require 'ostruct'
require 'fileutils'
require 'cfpropertylist'
require File.dirname(__FILE__) + '/beta_builder/archived_build'
require File.dirname(__FILE__) + '/beta_builder/deployment_strategies'
require File.dirname(__FILE__) + '/beta_builder/release_strategies'
require File.dirname(__FILE__) + '/beta_builder/build_output_parser'

module BetaBuilder
  class Tasks < ::Rake::TaskLib
    def initialize(namespace = :beta, &block)
      @configuration = Configuration.new(
        :configuration => "Adhoc",
        :build_dir => "build",
        :auto_archive => false,
        :archive_path  => File.expand_path("~/Library/Developer/Xcode/Archives"),
        :xcodebuild_path => "/usr/bin/xcodebuild",
        :xcrun_path => "/usr/bin/xcrun",
        :xcodeargs => nil,
        :packageargs => nil,
        :project_file_path => nil,
        :workspace_path => nil,
        :ipa_destination_path => "./",
        :zip_ipa_and_dsym => true,
        :scheme => nil,
        :app_name => nil,
        :arch => nil,
        :xcode4_archive_mode => false,
        :skip_clean => ENV.fetch('SKIPCLEAN', false),
        :verbose => ENV.fetch('VERBOSE', false),
        :dry_run => ENV.fetch('DRY', false),
        :set_version_number => false,
        :sdk => "iphoneos",
        :copy_app_bundle => false,
        :include_version_in_package => false,
        :app_info_plist => nil,
        :scm => nil

      )
      @namespace = namespace
      yield @configuration if block_given?
      define
    end

    def ipa_destination_path=(val)
      @ipa_destination_path = File.expand val
    end

    def app_info_plist=(val)
      @app_info_plist = val
      if val != nil 
        @app_info_plist_path = File.expand app_info_plist
      end
    end

    def xcodebuild(*args)
      # we're using tee as we still want to see our build output on screen
      cmd = []
      cmd << @configuration.xcodebuild_path
      cmd.concat args
      puts "Running: #{cmd.join(" ")}" if @configuration.verbose
      cmd << "2>&1 %s build.output" % (@configuration.verbose ? '| tee' : '>')
      cmd = cmd.join(" ")
      system(cmd)
    end

    class Configuration < OpenStruct
      def release_notes_text
        return release_notes.call if release_notes.is_a? Proc
        release_notes
      end
      def build_arguments
        args = []
        if workspace_path
          raise "A scheme is required if building from a workspace" unless scheme
          args << "-workspace '#{workspace_path}'"
          args << "-scheme '#{scheme}'"
        else
          args << "-target '#{target}'"
          args << "-project '#{project_file_path}'" if project_file_path
        end

        args << "-sdk #{sdk}"
        
        args << "-configuration '#{configuration}'"
        args << "-arch '#{arch}'" unless arch.nil?
        args << "VERSION_LONG='#{build_number_git}'" if set_version_number
        
        if xcodeargs
            args.concat xcodeargs if xcodeargs.is_a? Array
            args << "#{xcodeargs}" if xcodears.is_a? String
        end
        
        args
      end

      def archive_name
        app_name || target
      end
      
      def app_file_name
        raise ArgumentError, "app_name or target must be set in the BetaBuilder configuration block" if app_name.nil? && target.nil?
        if app_name
          "#{app_name}.app"
        else
          "#{target}.app"
        end
      end

      def build_number
        if (app_info_plist_path == nil) || (!File.exists? app_info_plist_path) then
          return nil
        end

        # read the plist and extract data
        plist = CFPropertyList::List.new(:file => app_info_plist_path)
        data = CFPropertyList.native_types(plist.value)
        data["CFBundleVersion"]
      end

      def next_build_number
        if build_number == nil then
          return nil
        end

        # get a hold on the build number and increment it
        version_components = build_number.split(".")
        new_build_number = version_components.pop.to_i + 1
        version_components.push new_build_number.to_s
        version_components.join "."
      end

      def built_app_long_version_suffix
        if !include_version_in_package || build_number == nil then
          ""
        else 
          "-#{build_number}"
        end
      end

      def ipa_name
        prefix = app_name == nil ? target : app_name
        "#{prefix}#{built_app_long_version_suffix}.ipa"
      end      
      
      def built_app_path
        if build_dir == :derived
          File.join("#{derived_build_dir}", "#{configuration}-#{sdk}", "#{app_file_name}")
        else
          File.join("#{build_dir}", "#{configuration}-#{sdk}", "#{app_file_name}")
        end
      end
      
      def built_dsym_path
        "#{built_app_path}.dSYM"
      end
      
      def derived_build_dir 
        for dir in Dir[File.join(File.expand_path("~/Library/Developer/Xcode/DerivedData"), "#{app_name}-*")]
          return "#{dir}/Build/Products" if File.read( File.join(dir, "info.plist") ).match workspace_path
        end
      end
      
      
      def derived_build_dir_from_build_output
        output = BuildOutputParser.new(File.read("build.output"))
        output.build_output_dir  
      end

      def zipped_package_name
        "#{app_name}#{built_app_long_version_suffix}.zip"
      end

      def ipa_path
        File.join(File.expand_path(ipa_destination_path), ipa_name)
      end

      def dsym_path
        File.join(File.expand_path(ipa_destination_path), "#{app_name}#{built_app_long_version_suffix}.dSYM.zip")
      end

      def app_bundle_path
        ipa_destination_path
      end
      
      def build_number_git
        `git describe --tags --abbrev=1`.chop
      end
      
      def deploy_using(strategy_name, &block)
        if DeploymentStrategies.valid_strategy?(strategy_name.to_sym)
          self.deployment_strategy = DeploymentStrategies.build(strategy_name, self)
          self.deployment_strategy.configure(&block)
        else
          raise "Unknown deployment strategy '#{strategy_name}'."
        end
      end

      def release_using(strategy_name, &block)
        if ReleaseStrategies.valid_strategy?(strategy_name.to_sym)
          self.release_strategy = ReleaseStrategies.build(strategy_name, self)
          self.release_strategy.configure(&block)
          self.release_strategy.prepare
        else
          raise "Unknown release strategy '#{strategy_name}'."
        end
      end
    end
    
    private
    
    def define
      namespace(@namespace) do        
        desc "Clean the Build"
        task :clean do
          unless @configuration.skip_clean
            print "Cleaning Project..."
            xcodebuild @configuration.build_arguments, "clean"
            puts "Done"
          end
        end
        
        desc "Build the beta release of the app"
        task :build => :clean do
          print "Building Project..."
          xcodebuild @configuration.build_arguments, "build"
          raise "** BUILD FAILED **" if BuildOutputParser.new(File.read("build.output")).failed?
          puts "Done"
        end
        
        desc "Package the beta release as an IPA file"
        task :package => :build do
          # there is no need for IPA or dSYM unless we have a device build,
          # so do that part only on iphoneos SDKs
          if(@configuration.sdk.eql? "iphoneos") then
            package_device_build
          end

          if @configuration.copy_app_bundle then
            # FileUtils.rm_rf @configuration.app_bundle_path unless !File.exists? @configuration.app_bundle_path
            # FileUtils.mkdir_p @configuration.app_bundle_path
            FileUtils.cp_r @configuration.built_app_path, @configuration.app_bundle_path
          end
        end

        def package_device_build
          if @configuration.auto_archive
              Rake::Task["#{@namespace}:archive"].invoke
            end
            print "Packaging and Signing..."          
            raise "** PACKAGE FAILED ** No Signing Identity Found" unless @configuration.signing_identity
            # raise "** PACKAGE FAILED ** No Provisioning Profile Found" unless @configuration.provisioning_profile
            
            # trash and create the dist IPA path if needed
            FileUtils.rm_rf @configuration.ipa_destination_path unless !File.exists? @configuration.ipa_destination_path
            FileUtils.mkdir_p @configuration.ipa_destination_path
          
            # Construct the IPA and Sign it
            cmd = []
            cmd << @configuration.xcrun_path
            cmd << "-sdk #{@configuration.sdk}"
            cmd << "PackageApplication"
            cmd << "-v '#{@configuration.built_app_path}'"
            cmd << "-o '#{@configuration.ipa_path}'"
            cmd << "--sign '#{@configuration.signing_identity}'"
            cmd << "--embed '#{@configuration.provisioning_profile}'" unless @configuration.signing_identity == nil
            if @configuration.packageargs
              cmd.concat @configuration.packageargs if @configuration.packageargs.is_a? Array
              cmd << @configuration.packageargs if @configuration.packageargs.is_a? String
            end
            puts "Running #{cmd.join(" ")}" if @configuration.verbose
            cmd << "2>&1 %s build.output" % (@configuration.verbose ? '| tee' : '>')
            cmd = cmd.join(" ")
            system(cmd)
            
            # zip the dSYM over to the dist folder
            puts "Done"
            print "Zipping dSYM..."  

            # copy the dSYM to the pkg destination
            FileUtils.cp_r @configuration.built_dsym_path, @configuration.ipa_destination_path

            # move to pkg destination and zip the dSYM
            current_dir = Dir.pwd
            Dir.chdir @configuration.ipa_destination_path

            cmd = []
            cmd << "zip"
            cmd << "-r"
            cmd << "#{@configuration.app_name}.app.dSYM.zip"
            cmd << "#{@configuration.app_name}.app.dSYM"
                    
            puts "Running #{cmd.join(" ")}" if @configuration.verbose
            cmd << "2>&1 %s build.output" % (@configuration.verbose ? '| tee' : '>')
            cmd = cmd.join(" ")
            system(cmd)

            

            if @configuration.zip_ipa_and_dsym then
              cmd = []
              cmd << "zip"
              cmd << @configuration.zipped_package_name
              cmd << "#{@configuration.app_name}.app.dSYM.zip"
              cmd << @configuration.ipa_name
              cmd << "2>&1 %s build.output" % (@configuration.verbose ? '| tee' : '>')
              puts
              puts cmd.join " "
              system cmd.join " "

              # File.delete @configuration.dsym_path unless !File.exists? @configuration.dsym_path
              # File.delete @configuration.ipa_path unless !File.exists? @configuration.ipa_path
              puts "Done"
              puts "ZIP package: #{@configuration.zipped_package_path}"
            else
              puts "Done"
              puts "IPA File: #{@configuration.ipa_path}" if @configuration.verbose
              puts "dSYM File: #{@configuration.dsym_path}" if @configuration.verbose
            end

            # back to working directory
            Dir.chdir current_dir
        end

        desc "Build and archive the app"
        task :archive => :build do
          puts "Archiving build..."
          archive = BetaBuilder.archive(@configuration)
          output_path = archive.save_to(@configuration.archive_path)
          puts "Archive saved to #{output_path}."
        end

        if @configuration.deployment_strategy
          desc "Prepare your app for deployment"
          task :prepare => :package do
            @configuration.deployment_strategy.prepare
          end
          
          desc "Deploy the beta using your chosen deployment strategy"
          task :deploy => :prepare do
            @configuration.deployment_strategy.deploy
          end
          
          desc "Deploy the last build"
          task :redeploy do
            @configuration.deployment_strategy.prepare
            @configuration.deployment_strategy.deploy
          end
        end

        desc "Tag SCM and prepares for next release (increments build number)"
        task :release => :package do
          # tag tree
          @configuration.release_strategy.tag_current_version

          # increment the build number
          prepare_for_next_release

          @configuration.release_strategy.prepare_for_next_release
        end

        def prepare_for_next_release
          next_build_number = @configuration.next_build_number
          if next_build_number == nil then
            return
          end


          print "Updating #{@configuration.app_info_plist} to version #{next_build_number}"

          # read the plist and extract data
          plist = CFPropertyList::List.new(:file => @configuration.app_info_plist_path)
          data = CFPropertyList.native_types(plist.value)

          # re inject new version number into the data
          data["CFBundleVersion"] = next_build_number

          # recreate the plist and save it
          plist.value = CFPropertyList.guess(data)
          plist.save(@configuration.app_info_plist_path, CFPropertyList::List::FORMAT_XML)
          puts "Done"
        end
      end
    end
  end
end
