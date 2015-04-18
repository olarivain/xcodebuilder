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
        :pod_repo_sources => nil,
        :watch_app => false
      )
      @namespace = namespace
      yield @configuration if block_given?
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

    def resolved_repos
      master_repo = ["https://github.com/CocoaPods/Specs.git"]
      if @configuration.pod_repo_sources == nil then
        return master_repo
      end

      return master_repo + Array(@configuration.pod_repo_sources)
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
      success = xcodebuild @configuration.build_arguments, "archive"
      raise "** BUILD FAILED **" unless success
      puts "Done"
    end
    
    # desc "Package the release as a distributable archive"
    def package
      build

      print "Packaging and Signing..."        
      # trash and create the dist IPA path if needed
      FileUtils.rm_rf @configuration.package_destination_path unless !File.exists? @configuration.package_destination_path
      FileUtils.mkdir_p @configuration.package_destination_path
    
      # Construct the IPA and Sign it
      cmd = []
      cmd << "-exportArchive"
      cmd << "-exportFormat"
      cmd << "ipa"
      cmd << "-exportWithOriginalSigningIdentity"
      cmd << "-archivePath"
      cmd << "'#{File.expand_path @configuration.xcarchive_path}'"
      cmd << "-exportPath"
      cmd << "'#{File.expand_path @configuration.ipa_path}'"

      # puts "Running #{cmd.join(" ")}" if @configuration.verbose
      # cmd << "2>&1 /dev/null"
      # cmd = cmd.join(" ")
      # system(cmd)
      xcodebuild cmd ""

      if @configuration.watch_app then
        reinject_wk_stub_in_ipa
      end

      puts ""
      puts "Done."
    end

    def reinject_wk_stub_in_ipa
      puts ""
      put "Reinject WK support into signed IPA..."
      # create a tmp folder
      tmp_folder = @configuration.package_destination_path + "tmp"
      FileUtils.mkdir_p tmp_folder

      # copy the ipa to it
      FileUtils.cp "#{File.expand_path @configuration.ipa_path}", tmp_folder

      # evaluate this here because this is based on pwd
      full_ipa_path = @configuration.ipa_path
      # keep track of current folder so can cd back to it and cd to tmp folder
      current_folder = `pwd`.gsub("\n", "")
      Dir.chdir tmp_folder

      # unzip ipa and get rid of it
      `unzip '#{@configuration.ipa_name}'`
      FileUtils.rm @configuration.ipa_name

      # now reinject the shiznit in
      FileUtils.mkdir "WatchKitSupport"
      #get the xcode path
      base = `xcode-select --print-path`.gsub("\n", "")
      wk_path = "#{base}/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/Library/Application Support/WatchKit/*"
      FileUtils.cp_r Dir.glob(wk_path), "WatchKitSupport"

      # now zip the fucker
      `zip -r '#{full_ipa_path}' *`
      Dir.chdir current_folder
      FileUtils.rm_rf tmp_folder
      put " Done."
      puts ""
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
      repos = resolved_repos.join ","
      result = system "pod lib lint #{@configuration.podspec_file} --allow-warnings --sources=#{repos}"
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
