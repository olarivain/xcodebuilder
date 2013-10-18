require 'rake/tasklib'
require 'ostruct'
require 'fileutils'
require 'cfpropertylist'
require File.dirname(__FILE__) + '/xcode_builder/configuration'
require File.dirname(__FILE__) + '/xcode_builder/build_output_parser'

module XcodeBuilder
  class XcodeBuilder
    attr_reader :configuration

    def initialize(namespace = :xcbuild, &block)
      @configuration = Configuration.new(
        :configuration => "Adhoc",
        :build_dir => "build",
        :xcodebuild_extra_args => nil,
        :xcrun_extra_args => nil,
        :project_file_path => nil,
        :workspace_file_path => nil,
        :sdk => "iphoneos",
        :scheme => nil,
        :app_name => nil,
        :app_extension => "app",
        :signing_identity => nil,
        :package_destination_path => "./pkg",
        :zip_artifacts => false,
        :skip_dsym => false,
        :arch => nil,
        :skip_clean => ENV.fetch('SKIPCLEAN', false),
        :verbose => ENV.fetch('VERBOSE', false),
        :info_plist => nil,
        :scm => nil,
        :tag_vcs => false,
        :increment_plist_version => false,
        :pod_repo => nil,
        :podspec_file => nil,
        :upload_dsym => false
      )
      @namespace = namespace
      yield @configuration if block_given?

      # expand the info plist path, as it's likely to be relative and we'll be fucking
      # around with the cwd later on.
      @configuration.info_plist = File.expand_path @configuration.info_plist unless @configuration.info_plist == nil
    end

    def xcodebuild(*args)
      # we're using tee as we still want to see our build output on screen
      cmd = []
      cmd << "/usr/bin/xcodebuild"
      cmd.concat args
      puts "Running: #{cmd.join(" ")}" if @configuration.verbose
      cmd << "2>&1 %s build.output" % (@configuration.verbose ? '| tee' : '>')
      cmd = cmd.join(" ")
      system(cmd)
    end
    
    # desc "Clean the Build"
    def clean
      unless @configuration.skip_clean
        print "Cleaning Project..."
        xcodebuild @configuration.build_arguments, "clean"
        puts "Done"
      end
    end
    
    # desc "Build the beta release of the app"
    def build
      clean unless @configuration.skip_clean

      print "Building Project..."
      xcodebuild @configuration.build_arguments, "build"
      raise "** BUILD FAILED **" if BuildOutputParser.new(File.read("build.output")).failed?
      puts "Done"
    end
    
    # desc "Package the release as a distributable archive"
    def package
      build
      # there is no need for IPA or dSYM unless we have a device/macosx build,
      # so do that part only on iphoneos/macosx SDKs
      #
      if(@configuration.sdk.eql? "iphoneos") then
        package_ios_app
        package_dsym
        package_artifact unless !@configuration.zip_artifacts
      elsif (@configuration.sdk.eql? "macosx") then
        package_macos_app
        package_dsym
        package_artifact unless !@configuration.zip_artifacts
      else
        package_simulator_app
      end
    end

    # desc "Builds an IPA from the built .app"
    def package_ios_app
      print "Packaging and Signing..."          
      raise "** PACKAGE FAILED ** No Signing Identity Found" unless @configuration.signing_identity
      # trash and create the dist IPA path if needed
      FileUtils.rm_rf @configuration.package_destination_path unless !File.exists? @configuration.package_destination_path
      FileUtils.mkdir_p @configuration.package_destination_path
    
      # Construct the IPA and Sign it
      cmd = []
      cmd << "/usr/bin/xcrun"
      cmd << "-sdk #{@configuration.sdk}"
      cmd << "PackageApplication"
      cmd << "-v '#{@configuration.built_app_path}'"
      cmd << "-o '#{@configuration.ipa_path}'"
      cmd << "--sign '#{@configuration.signing_identity}'" unless @configuration.signing_identity == nil
      cmd << "--embed '#{@configuration.provisioning_profile}'"
      if @configuration.xcrun_extra_args then
        cmd.concat @configuration.xcrun_extra_args if @configuration.xcrun_extra_args.is_a? Array
        cmd << @configuration.xcrun_extra_args if @configuration.xcrun_extra_args.is_a? String
      end
      puts "Running #{cmd.join(" ")}" if @configuration.verbose
      cmd << "2>&1 %s build.output" % (@configuration.verbose ? '| tee' : '>')
      cmd = cmd.join(" ")
      system(cmd)
      
      # zip the dSYM over to the dist folder
      puts "Done"
    end

    def package_macos_app
      # clean the pkg folder: create it if it doesn't exist yet
      FileUtils.mkdir_p "\"#{@configuration.package_destination_path}\"" unless  File.exists? "\"#{@configuration.package_destination_path}\""
      # and remove an existing app_bundle_path if it exists
      FileUtils.rm_rf "\"#{@configuration.app_bundle_path}\"" unless !File.exists? "\"#{@configuration.app_bundle_path}\""

      # now we can properly copy the app bundle path over.
      FileUtils.cp_r "\"#{@configuration.built_app_path}\"", "\"#{@configuration.package_destination_path}\""
    end

    def package_simulator_app
      # clean the pkg folder: create it if it doesn't exist yet
      FileUtils.mkdir_p "\"#{@configuration.package_destination_path}\"" unless  File.exists? "\"#{@configuration.package_destination_path}\""
      # and remove an existing app_bundle_path if it exists
      FileUtils.rm_rf "\"#{@configuration.app_bundle_path}\"" unless !File.exists? "\"#{@configuration.app_bundle_path}\""

      # now we can properly copy the app bundle path over.
      FileUtils.cp_r "\"#{@configuration.built_app_path}\"", "\"#{@configuration.package_destination_path}\""
    end

    # desc "Zips the dSYM to the package folder"
    def package_dsym
      return if @configuration.skip_dsym
      print "Packaging dSYM..."  

      # copy the dSYM to the pkg destination
      FileUtils.cp_r @configuration.built_dsym_path, @configuration.package_destination_path

      # the version is pulled from a path relative location, so fetch BEFORE
      # we Dir.chdir
      dsym_name = @configuration.dsym_name
      dsym_target_path = @configuration.dsym_path

      # move to pkg destination and zip the dSYM
      current_dir = Dir.pwd
      Dir.chdir @configuration.package_destination_path

      cmd = []
      cmd << "zip"
      cmd << "-r"
      cmd << "\"#{dsym_target_path}\""
      cmd << "\"#{@configuration.app_name}.#{@configuration.app_extension}.dSYM\""
              
      puts "Running #{cmd.join(" ")}" if @configuration.verbose
      cmd << "2>&1 %s ../build.output" % (@configuration.verbose ? '| tee' : '>')
      cmd = cmd.join(" ")
      system(cmd)

      FileUtils.rm_rf "#{@configuration.app_name}.#{@configuration.app_extension}.dSYM" unless !File.exists? "#{@configuration.app_name}.#{@configuration.app_extension}.dSYM"

      # back to working directory
      Dir.chdir current_dir
      puts "Done."
    end

    # desc "Packages the final artifact (IPA + dSYM)"
    def package_artifact
      # keep track of current working dir
      current_dir = Dir.pwd
      Dir.chdir @configuration.package_destination_path

      # zip final package
      cmd = []
      cmd << "zip"
      cmd << "-r"
      cmd << "\"#{@configuration.zipped_package_name}\""
      cmd << "\"#{@configuration.dsym_name}\"" unless @configuration.skip_dsym
      cmd << "\"#{@configuration.ipa_name}\"" unless !@configuration.sdk.eql? "iphoneos"
      cmd << "\"#{@configuration.app_name}.#{@configuration.app_extension}\"" unless !@configuration.sdk.eql? "macosx"
      cmd << "2>&1 %s ../build.output" % (@configuration.verbose ? '| tee' : '>')

      system cmd.join " "

      # delete all the artifacts but the .app. which will be needed by the automation builds
      FileUtils.rm_rf @configuration.dsym_name unless !File.exists? @configuration.dsym_name
      FileUtils.rm_rf @configuration.ipa_name unless !File.exists? @configuration.ipa_name

      # back to working directory
      Dir.chdir current_dir

      puts "Done"
      puts "ZIP package: #{@configuration.zipped_package_name}"
    end

    # desc "For CocoaPod libraries: dry run, tags SCM, pushes to cocoapod and increments build number"
    def pod_release
      raise "CocoaPod repo is not set, aborting cocoapod_release task." unless @configuration.pod_repo != nil
      raise "Spec file is not set, aborting cocoapod_release task." unless @configuration.podspec_file != nil

      # make a dry run first
      pod_dry_run

      # tag source as needed
      if @configuration.release_strategy != nil then
        @configuration.release_strategy.tag_current_version
      end

      # and push pod pod
      push_pod

      # ask release strategy to bump the release number
      if @configuration.release_strategy != nil then
          @configuration.release_strategy.prepare_for_next_pod_release
      end
      puts "Pod successfully released"
    end

    # runs a pod dry run before tagging
    def pod_dry_run
      clean unless @configuration.skip_clean

      print "Pod dry run..."
      result = system "pod lib lint --only-errors"
      raise "** Pod dry run failed **" if !result
      puts "Done"
    end

    def push_pod
      cmd = []
      cmd << "pod"
      cmd << "push"
      cmd << @configuration.pod_repo
      cmd << "--allow-warnings"

      print "Pushing to CocoaPod..."
      result = system(cmd.join " ")
      raise "** Pod push failed **" if !result
      puts "Done."
    end

    def deploy
      package
      @configuration.deployment_strategy.deploy
    end

    def release
      # deploy or package depending on configuration
      if @configuration.deployment_strategy then
        deploy
      else 
        package
      end

      # tag first, then prepare for next release and 
      # commit the updated plist
      if @configuration.tag_vcs then
        @configuration.release_strategy.tag_current_version
      end

      if @configuration.release_strategy != nil then
        @configuration.release_strategy.prepare_for_next_release
      end
      puts "App successfully released"
    end
  end
end
