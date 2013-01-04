module BetaBuilder
  module ReleaseStrategies
    class Git < ReleaseStrategy
      attr_accessor :branch, :origin

      def tag_current_version
        build_number = @configuration.build_number
        raise "build number cannot be empty on release" unless  (build_number != nil) && (!build_number.empty?) 

        puts "Relasing with Git"
        print "Tagging version #{build_number}"
        cmd = []

        cmd << "git"
        cmd << "tag"
        # -f sounds brutal to start with, so let's give it a try without
#        cmd << "-f"
        cmd << "v#{build_number}"
        cmd << "2>&1 %s git.output" % (@configuration.verbose ? '| tee' : '>')

        puts
        system(cmd.join " ")

        puts "Done"

        print "Pushing tag to #{@origin} on branch #{@branch}"
        cmd = []

        cmd << "git"
        cmd << "push"
        cmd << "--tags"
        cmd << "#{@origin}"
        cmd << @branch
        cmd << "2>&1 %s git.output" % (@configuration.verbose ? '| tee' : '>')

        puts
        system(cmd.join " ")

        puts "Done"

      end

      def prepare_for_next_release
        build_number = @configuration.build_number
        raise "build number cannot be empty on release" unless  (build_number != nil) && (!build_number.empty?) 

        puts "Preparing for next release with Git"
        print "Updating Info.plist to version #{build_number}"
        cmd = []

        # stage the info plist
        cmd << "git"
        cmd << "add"
        cmd << @configuration.app_info_plist
        cmd.join " "
        puts
        system(cmd.join " ")

        cmd = []
        cmd << "git"
        cmd << "commit"
        cmd << "-m"
        cmd << '"Preparing for next release..."'
        cmd << "2>&1 %s git.output" % (@configuration.verbose ? '| tee' : '>')
        puts
        system(cmd.join " ")
        puts "Done"

        print "Pushing new build number to #{@origin} on branch #{@branch}"
        cmd = []

        cmd = []
        cmd << "git"
        cmd << "push"
        cmd << "#{@origin}"
        cmd << @branch
        cmd << "2>&1 %s git.output" % (@configuration.verbose ? '| tee' : '>')
        puts
        system(cmd.join " ")

        puts "Done"
      end
    end
  end
end
