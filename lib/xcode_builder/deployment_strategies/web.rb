module XcodeBuilder
  module DeploymentStrategies
    class Web < Strategy

      def prepare
        puts "Nothing to prepare!" if @configuration.verbose
      end
      
      def deploy
        puts "Deploying to the web server : '#{@configuration.server_url}'"
        cmd = []
        cmd.push "curl"
        cmd.push "--user #{@configuration.server_user}:#{@configuration.server_password}"
        cmd.push "-X POST"
        cmd.push "-F ipa_file=@#{@configuration.ipa_path}"
        cmd.push "#{@configuration.server_url}"
        cmd = cmd.join(" ")
        puts "* Running `#{cmd}`" if @configuration.verbose

        system(cmd)
      
      end
    end
  end
end
