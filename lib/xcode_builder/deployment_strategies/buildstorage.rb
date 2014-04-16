module XcodeBuilder
  module DeploymentStrategies
    class BuildStorage < Strategy

      def prepare
        puts "Nothing to prepare!" if @configuration.verbose
      end
      
      def deploy
        puts "Deploying to build storage server"
        cmd = []
        cmd.push "curl"
        cmd.push "--user #{@configuration.storage_user}:#{@configuration.storage_password}"
        cmd.push "-X POST"
        cmd.push "-F ipa_file=@#{@configuration.ipa_path}"
        cmd.push "#{@configuration.storage_url}"
        cmd = cmd.join(" ")
        puts "* Running `#{cmd}`" if @configuration.verbose

        system(cmd)
      
      end
    end
  end
end
