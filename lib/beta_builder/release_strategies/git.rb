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

      def prepare_for_next_release
        build_number = @configuration.build_number
        raise "build number cannot be empty on release" unless  (build_number != nil) && (!build_number.empty?) 
        cmd = []
        print "Committing #{@configuration.app_info_plist} with version #{build_number}"
        # stage the info plist
        cmd << "git"
        cmd << "add"
        cmd << @configuration.app_info_plist
        system(cmd.join " ")

        # then commit it
        cmd = []
        cmd << "git"
        cmd << "commit"
        cmd << "-m"
        cmd << '"Preparing for next release..."'
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
        puts "Done"
      end
    end
  end
end
