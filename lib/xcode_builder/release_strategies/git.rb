module XcodeBuilder
  module ReleaseStrategies
    class Git < ReleaseStrategy
      attr_accessor :branch, :origin, :tag_name

      def prepare
        
        if @origin == nil then
            @origin = "origin"
        end

        if @branch == nil then
            @branch = "master"
        end

        if @tag_name == nil then
            @tag_name = "v#{@configuration.build_number}"
        end
      end

      def tag_current_version
        puts "Relasing with Git"
        print "Tagging version #{@tag_name}"
        cmd = []

        #first, tag
        cmd << "git"
        cmd << "tag"
        cmd << @tag_name

        cmd << "2>&1 %s git.output" % (@configuration.verbose ? '| tee' : '>')
        result = system(cmd.join " ")
        raise "Could not tag repository" unless result
        puts
        puts "Done"

        # then push tags to the remote server
        print "Pushing tag to #{@origin} on branch #{@branch}"
        cmd = []

        cmd << "git"
        cmd << "push"
        cmd << "--tags"
        cmd << @origin
        cmd << @branch
        cmd << "2>&1 %s git.output" % (@configuration.verbose ? '| tee' : '>')
        system(cmd.join " ")
        raise "Could not push to #{@origin}" unless result
        
        puts
        puts "Done"

      end

      def prepare_for_next_pod_release
        build_number = @configuration.build_number
        next_build_number = @configuration.next_build_number

        raise "build number cannot be empty on release" unless  (build_number != nil) && (!build_number.empty?) 

        # increment the build number
        @configuration.increment_pod_number

        # commit
        print "Committing #{@configuration.info_plist} and #{@configuration.podspec_file} with version #{build_number}"
        stage_files [@configuration.info_plist, @configuration.podspec_file]
        commit_and_push_with_message "Preparing for next pod release #{next_build_number}..."
       
        puts "Done"
      end

      def prepare_for_next_release
        build_number = @configuration.build_number
        next_build_number = @configuration.next_build_number

        raise "build number cannot be empty on release" unless  (build_number != nil) && (!build_number.empty?) 
        
        # increment the build number
        @configuration.increment_plist_number
        
        print "Committing #{@configuration.info_plist} with version #{next_build_number}"

        stage_files [@configuration.info_plist]
        commit_and_push_with_message "[Xcodebuilder] Releasing build #{build_number}"
       
        puts "Done"
      end

      def stage_files files
        cmd = []
        
        cmd << "git"
        cmd << "add"
        files.each do |value|
            cmd <<  value
        end
        system(cmd.join " ")
      end 

      def commit_and_push_with_message message
         # then commit it
        cmd = []
        cmd << "git"
        cmd << "commit"
        cmd << "-m"
        cmd << "'#{message}'"
        cmd << "2>&1 %s git.output" % (@configuration.verbose ? '| tee' : '>')
        system(cmd.join " ")
        puts
        puts "Done"

        # now, push the updated plist
        print "Pushing update to #{@origin}/#{@branch}"
        cmd = []
        cmd << "git"
        cmd << "push"
        cmd << @origin
        cmd << @branch
        cmd << "2>&1 %s git.output" % (@configuration.verbose ? '| tee' : '>')
        
        result = system(cmd.join " ")
        raise "Could not push #{@branch} to #{@origin}" unless result
        puts 
      end
    end
  end
end
