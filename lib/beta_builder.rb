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
        :xcodebuild_path => "/usr/bin/xcodebuild",
        :xcrun_path => "/usr/bin/xcrun",
        :xcodeargs => nil,
        :packageargs => nil,
        :project_file_path => nil,
        :workspace_name => nil,
        :workspace_path => nil,
        :ipa_destination_path => "./pkg",
        :zip_ipa_and_dsym => true,
        :scheme => nil,
        :app_name => nil,
        :arch => nil,
        :skip_clean => ENV.fetch('SKIPCLEAN', false),
        :verbose => ENV.fetch('VERBOSE', false),
        :sdk => "iphoneos",
        :app_info_plist => nil,
        :scm => nil,
        :skip_scm_tagging => true,
        :skip_version_increment => true,
        :spec_file => nil
      )
      @namespace = namespace
      yield @configuration if block_given?
      define
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
        
        if xcodeargs
            args.concat xcodeargs if xcodeargs.is_a? Array
            args << "#{xcodeargs}" if xcodears.is_a? String
        end
        
        args
      end
      
      def app_file_name
        raise ArgumentError, "app_name or target must be set in the BetaBuilder configuration block" if app_name.nil? && target.nil?
        if app_name
          "#{app_name}.app"
        else
          "#{target}.app"
        end
      end
      
      def app_info_plist_path
        if app_info_plist != nil then 
          File.expand_path app_info_plist
        else 
          nil
        end
      end

      def build_number
        # no plist is found, return a nil version
        if (app_info_plist_path == nil)  || (!File.exists? app_info_plist_path) then
          return nil
        end

        # read the plist and extract data
        plist = CFPropertyList::List.new(:file => app_info_plist_path)
        data = CFPropertyList.native_types(plist.value)
        data["CFBundleVersion"]
      end

      def next_build_number
        # if we don't have a current version, we don't have a next version :)
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
        if build_number == nil then
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
        for dir in Dir[File.join(File.expand_path("~/Library/Developer/Xcode/DerivedData"), "#{workspace_name}-*")]
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

      def dsym_name
        "#{app_name}#{built_app_long_version_suffix}.dSYM.zip"
      end

      def dsym_path
        File.join(File.expand_path(ipa_destination_path), dsym_name)
      end

      def app_bundle_path
        "#{ipa_destination_path}/#{app_name}.app"
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
        
        desc "Package the release as a distributable archive"
        task :package => :build do
          # there is no need for IPA or dSYM unless we have a device build,
          # so do that part only on iphoneos SDKs
          # likewise, there is no need to keep the .app folder around if we're building for ARM
          # so skip this part on iphoneos SDK
          if(@configuration.sdk.eql? "iphoneos") then
            package_ipa
            package_dsym
            package_final_artifact
          else 
            # clean the pkg folder: create it if it doesn't exist yet
            FileUtils.mkdir_p @configuration.ipa_destination_path unless  File.exists? @configuration.ipa_destination_path
            # and remove an existing app_bundle_path if it exists
            FileUtils.rm_rf @configuration.app_bundle_path unless !File.exists? @configuration.app_bundle_path

            # now we can properly copy the app bundle path over.
            FileUtils.cp_r @configuration.built_app_path, "#{@configuration.ipa_destination_path}"
          end
        end

        desc "Builds an IPA from the built .app"
        def package_ipa
          print "Packaging and Signing..."          
          raise "** PACKAGE FAILED ** No Signing Identity Found" unless @configuration.signing_identity
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
          if @configuration.packageargs then
            cmd.concat @configuration.packageargs if @configuration.packageargs.is_a? Array
            cmd << @configuration.packageargs if @configuration.packageargs.is_a? String
          end
          puts "Running #{cmd.join(" ")}" if @configuration.verbose
          cmd << "2>&1 %s build.output" % (@configuration.verbose ? '| tee' : '>')
          cmd = cmd.join(" ")
          system(cmd)
          
          # zip the dSYM over to the dist folder
          puts "Done"
        end

        desc "Zips the dSYM to the package folder"
        def package_dsym
          print "Packaging dSYM..."  

          # copy the dSYM to the pkg destination
          FileUtils.cp_r @configuration.built_dsym_path, @configuration.ipa_destination_path

          # the version is pulled from a path relative location, so fetch BEFORE
          # we Dir.chdir
          dsym_name = @configuration.dsym_name
          dsym_target_path = @configuration.dsym_path

          # move to pkg destination and zip the dSYM
          current_dir = Dir.pwd
          Dir.chdir @configuration.ipa_destination_path

          cmd = []
          cmd << "zip"
          cmd << "-r"
          cmd << dsym_target_path
          cmd << "#{@configuration.app_name}.app.dSYM"
                  
          puts "Running #{cmd.join(" ")}" if @configuration.verbose
          cmd << "2>&1 %s ../build.output" % (@configuration.verbose ? '| tee' : '>')
          cmd = cmd.join(" ")
          system(cmd)
          # back to working directory
          Dir.chdir current_dir
        end

        desc "Packages the final artifact (IPA + dSYM)"
        def package_final_artifact
          # keep track of current working dir
          current_dir = Dir.pwd
          Dir.chdir @configuration.ipa_destination_path

          # zip final package
          cmd = []
          cmd << "zip"
          cmd << @configuration.zipped_package_name
          cmd << @configuration.dsym_name
          cmd << @configuration.ipa_name
          cmd << "2>&1 %s ../build.output" % (@configuration.verbose ? '| tee' : '>')
          system cmd.join " "

          # delete all the artifacts but the .app. which will be needed by the automation builds
          File.delete @configuration.dsym_name unless !File.exists? @configuration.dsym_name
          FileUtils.rm_rf "#{@configuration.app_name}.app.dSYM" unless !File.exists? "#{@configuration.app_name}.app.dSYM"

          # back to working directory
          Dir.chdir current_dir

          puts "Done"
          puts "ZIP package: #{@configuration.zipped_package_name}"
        end

        desc "Tag SCM and prepares for next release (increments build number)"
        task :release => :package do
          release
        end

        desc "For CocoaPod libraries: Tags SCM, pushes to cocoapod and increments build number"
        task :cocoapod_release => :build do
          raise "CocoaPod repo is not set, aborting cocoapod_release task." unless @configuration.pod_repo != nil
          raise "Spec file is not set, aborting cocoapod_release task." unless @configuration.spec_file != nil

          # tag and push current pod
          @configuration.release_strategy.tag_current_version
          push_pod

          # increment version numbers
          if increment_pod_and_plist_number then
              # and push appropriately
              @configuration.release_strategy.prepare_for_next_pod_release
          end
        end

        def push_pod
          cmd = []
          cmd << "pod"
          cmd << "push"
          cmd << @configuration.pod_repo
          # cmd << "--local-only"
          cmd << "--allow-warnings"

          print "Pushing to CocoaPod..."
          system (cmd.join " ")
          puts "Done."
        end

        def increment_pod_and_plist_number
          old_build_number = @configuration.build_number
          if !prepare_for_next_release then 
            return false
          end

          # bump the spec version and save it
          spec_content = File.open(@configuration.spec_file, "r").read
          old_version = "version = '#{old_build_number}'"
          new_version = "version = '#{@configuration.build_number}'"

          spec_content = spec_content.sub old_version, new_version

          File.open(@configuration.spec_file, "w") {|f|
            f.write spec_content
          }

          true
        end

        if @configuration.deployment_strategy
          desc "Prepare your app for deployment"
          task :deploy_and_release => :package do
            # deploy first
            @configuration.deployment_strategy.deploy

            # then release
            release
          end
        end

        def release
            # tag first, then prepare for next release and 
            # commit the updated plist
            if !@configuration.skip_scm_tagging then
              @configuration.release_strategy.tag_current_version
            end

            if prepare_for_next_release then
              @configuration.release_strategy.prepare_for_next_release
            end
        end

        def prepare_for_next_release
          if @configuration.skip_version_increment then
            return false
          end
          
          next_build_number = @configuration.next_build_number
          if next_build_number == nil then
            return false
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
          return true
        end
      end
    end
  end
end
