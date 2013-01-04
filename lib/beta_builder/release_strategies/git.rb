module BetaBuilder
  module ReleaseStrategies
    class Git < Strategy

      def tag build_number branch
        raise "build number cannot be empty on release" unless  (version_number != nil) && (!version_number.empty?) 

        puts "Relasing with Git"
        print "Tagging version #{build_number}"
        cmd = []

        cmd << "git"
        cmd << "tag"
        cmd << "-f"
        cmd << "v#{version_number}"

        cmd.join " "
        system(cmd)

        puts "Done"

        print "Pushing to origin on branch #{branch}"
        cmd = []

        cmd << "git"
        cmd << "push"
        cmd << "--tags"
        cmd << "origin"
        cmd << branch
        system(cmd)

        puts "Done"

      end

      def prepare_for_version build_number branch
      end
    end
  end
end
