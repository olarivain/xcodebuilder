require 'pathname'
require 'Date'
require File.dirname(__FILE__) + '/deployment_strategies'
require File.dirname(__FILE__) + '/release_strategies'

module XcodeBuilder
  class Configuration < OpenStruct
    def release_notes_text
      return release_notes.call if release_notes.is_a? Proc
      release_notes
    end

    def build_arguments
      args = []
      if workspace_file_path
        raise "A scheme is required if building from a workspace" unless scheme
        args << "-workspace '#{workspace_file_path}'"
        args << "-scheme '#{scheme}'"
      else
        args << "-target '#{target}'" unless target == nil
        args << "-scheme '#{scheme}'" unless scheme == nil
        args << "-project '#{project_file_path}'" if project_file_path
      end

      # args << "-sdk #{sdk}"

      args << "-configuration '#{configuration}'"
      args << "BUILD_DIR=\"#{File.expand_path build_dir}\""

      if xcodebuild_extra_args
          args.concat xcodebuild_extra_args if xcodebuild_extra_args.is_a? Array
          args << "#{xcodebuild_extra_args}" if xcodebuild_extra_args.is_a? String
      end

      args
    end

    def app_file_name
      raise ArgumentError, "app_name or target must be set in the BetaBuilder configuration block" if app_name.nil?
      "#{app_name}.app"
    end

    def build_number
      # we have a podspec file, so try to get the version out of that
      if (podspec_file != nil)  && (File.exists? podspec_file) then
        # get hte version out of the pod file
        return build_number_from_podspec
      end
      return nil
    end

    def build_number_from_podspec
      file = File.open(podspec_file, "r")
      begin
        version_line = file.gets
      end while version_line.eql? "\n"

      if match = version_line.match(/\s*version\s*=\s*["'](.*)["']\s*/i)
        version = match.captures
      end
      return version[0]
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

    def increment_pod_number
      if !increment_plist_version then
        return false
      end

      if podspec_file == nil then
        return false
      end

      # keep the old build number around
      old_build_number = build_number

      # bump the spec version and save it
      spec_content = File.open(podspec_file, "r").read
      old_version = "version = '#{old_build_number}'"
      new_version = "version = '#{next_build_number}'"

      spec_content = spec_content.sub old_version, new_version

      File.open(podspec_file, "w") {|f|
        f.write spec_content
      }

      true
    end

    def timestamp_plist
      if info_plist == nil then
        return false
      end

      Array(info_plist).each {|current_plist|
        # read the plist and extract data
        plist = CFPropertyList::List.new(:file => File.expand_path(current_plist))
        data = CFPropertyList.native_types(plist.value)

        # re inject new version number into the data
        data["CFBundleVersion"] = DateTime.now.strftime("%Y-%m-%d %k:%M")

        # recreate the plist and save it
        plist.value = CFPropertyList.guess(data)
        plist.save(current_plist, CFPropertyList::List::FORMAT_XML)
      }
    end

    def ipa_name
      prefix = app_name == nil ? target : app_name
      "#{prefix}#{built_app_long_version_suffix}.ipa"
    end

    def built_app_long_version_suffix
      if build_number == nil then
        ""
      else
        "-#{build_number}"
      end
    end

    def built_app_path
      File.join("#{build_dir}", "#{configuration}-#{sdk}", "#{app_file_name}")
    end

    def ipa_path
      File.join(File.expand_path(package_destination_path), ipa_name)
    end

    def app_bundle_path
      "#{package_destination_path}/#{app_name}.app"
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
end
