module BetaBuilder
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
        # -f sounds brutal to start with, so let's give it a try without
#        cmd << "-f"
        cmd << @tag_name

        cmd << "2>&1 %s git.output" % (@configuration.verbose ? '| tee' : '>')
        system(cmd.join " ")
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
        
        puts
        puts "Done"

      end

      def prepare_for_next_pod_release
        build_number = @configuration.build_number
        raise "build number cannot be empty on release" unless  (build_number != nil) && (!build_number.empty?) 

        print "Committing #{@configuration.app_info_plist} and #{@configuration.spec_file} with version #{build_number}"
        
        stage_files [@configuration.app_info_plist, @configuration.spec_file]
        commit_and_push_with_message "Preparing for next pod release..."
       
        puts "Done"
      end

      def prepare_for_next_release
        build_number = @configuration.build_number
        raise "build number cannot be empty on release" unless  (build_number != nil) && (!build_number.empty?) 
        
        print "Committing #{@configuration.app_info_plist} with version #{build_number}"

        stage_files [@configuration.app_info_plist]
        commit_and_push_with_message "Preparing for next release..."
       
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
        
        system(cmd.join " ")
        puts 
      end
    end
  end
end
