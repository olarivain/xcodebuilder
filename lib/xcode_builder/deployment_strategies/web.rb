require 'rest_client'
require 'json'
require 'fileutils'

module XcodeBuilder
  module DeploymentStrategies
    class Web < Strategy

      def prepare
        puts "Nothing to prepare!" if @configuration.verbose
      end
      
      def deploy
        puts "Deploying to the web server : '#{@configuration.server_url}'"

        payload = {
            :ipa_file => File.new(@configuration.ipa_path, 'rb'),
        }
        statusCode = 0
        begin
            response = RestClient::Request.new(:method => :post, :url => "#{@configuration.server_url}", :user => "#{@configuration.server_user}", :password => "#{@configuration.server_password}", :payload => payload).execute
            statusCode = response.code
        rescue => e
            puts "Web upload failed with exception:\n#{e}Response\n#{e.response}"
        end
        if (statusCode == 200) || (statusCode == 201)
            puts "Web upload completed"
        else
            puts "Web upload failed" 
        end
      end
    end
  end
end
