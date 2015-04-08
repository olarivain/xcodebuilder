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
        :configuration => "Release",
        :build_dir => "build",
        :project_file_path => nil,
        :workspace_file_path => nil,
        :scheme => nil,
        :app_name => nil,
        :signing_identity => nil,
        :package_destination_path => "./pkg",
        :skip_clean => false,
        :verbose => false,
        :info_plist => nil,
        :scm => nil,
        :pod_repo => nil,
        :podspec_file => nil,
        :xcodebuild_extra_args => nil,
        :xcrun_extra_args => nil,
        :timestamp_build => nil,
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
      cmd << "xcrun xcodebuild"
      cmd.concat args
      puts "Running: #{cmd.join(" ")}" if @configuration.verbose
      cmd << "| xcpretty && exit ${PIPESTATUS[0]}"
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

      # update the long version number with the date
      @configuration.timestamp_plist if @configuration.timestamp_build

      print "Building Project..."
      success = xcodebuild @configuration.build_arguments, "build"
      raise "** BUILD FAILED **" unless success
      puts "Done"
    end
    
    # desc "Package the release as a distributable archive"
    def package
      build

      print "Packaging and Signing..."        
      if (@configuration.signing_identity != nil) then 
        puts "" 
        print "Signing identity: #{@configuration.signing_identity}" 
      end

      # trash and create the dist IPA path if needed
      FileUtils.rm_rf @configuration.package_destination_path unless !File.exists? @configuration.package_destination_path
      FileUtils.mkdir_p @configuration.package_destination_path
    
      # Construct the IPA and Sign it
      cmd = []
      cmd << "/usr/bin/xcrun"
      cmd << "-sdk iphoneos"
      cmd << "PackageApplication"
      cmd << "'#{@configuration.built_app_path}'"
      cmd << "-o '#{@configuration.ipa_path}'"
      cmd << "--sign '#{@configuration.signing_identity}'" unless @configuration.signing_identity == nil

      if @configuration.xcrun_extra_args then
        cmd.concat @configuration.xcrun_extra_args if @configuration.xcrun_extra_args.is_a? Array
        cmd << @configuration.xcrun_extra_args if @configuration.xcrun_extra_args.is_a? String
      end

      puts "Running #{cmd.join(" ")}" if @configuration.verbose
      cmd << "2>&1 /dev/null"
      cmd = cmd.join(" ")
      system(cmd)
      
      puts ""
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

      puts ""
      puts "App successfully released"
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
      print "Pod dry run..."
      result = system "pod lib lint #{@configuration.podspec_file} --allow-warnings"
      raise "** Pod dry run failed **" if !result
      puts "Done"
    end

    def push_pod
      cmd = []
      cmd << "pod repo push"
      cmd << @configuration.pod_repo
      cmd << @configuration.podspec_file
      cmd << "--allow-warnings"

      print "Pushing to CocoaPod..."
      result = system(cmd.join " ")
      raise "** Pod push failed **" if !result
      puts "Done."
    end
  end
end
