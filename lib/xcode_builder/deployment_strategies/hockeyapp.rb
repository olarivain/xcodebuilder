require 'rest_client'
require 'json'
require 'tmpdir'
require 'fileutils'

module XcodeBuilder
  module DeploymentStrategies
    class HockeyApp < Strategy
      include Rake::DSL
      include FileUtils
      ENDPOINT = "https://rink.hockeyapp.net/api/2/apps/upload"
      
      def extended_configuration_for_strategy
        proc do
          def generate_release_notes(&block)
            self.release_notes = block if block
          end
        end
      end
      
      def deploy
        release_notes = get_notes
        payload = {
          :api_token          => @configuration.api_token,
          :ipa               => File.new(@configuration.ipa_path, 'rb'),
          :notes              => release_notes,
          :status             => 2,
          :teams => (@configuration.teams || []).join(","),
        }
        
        print "Uploading build to HockeyApp..."        
        
        statusCode = 0
        begin
          response = RestClient.post(ENDPOINT, payload, :accept => :json, :'X-HockeyAppToken' => @configuration.api_token)
          statusCode = response.code
        rescue => e
          puts "HockeyApp upload failed with exception:\n#{e}Response\n#{e.response}"
        end
        
        if (statusCode == 201) || (statusCode == 200)
          puts "Done."

        end
      end
      
      private
      
      def get_notes
        notes = @configuration.release_notes_text
        notes || get_notes_using_editor || get_notes_using_prompt
      end
      
      def get_notes_using_editor
        return unless (editor = ENV["EDITOR"])

        dir = Dir.mktmpdir
        begin
          filepath = "#{dir}/release_notes"
          system("#{editor} #{filepath}")
          @configuration.release_notes = File.read(filepath)
        ensure
          rm_rf(dir)
        end
      end
      
      def get_notes_using_prompt
        puts "Enter the release notes for this build (hit enter twice when done):\n"
        @configuration.release_notes = gets_until_match(/\n{2}$/).strip
      end
      
      def gets_until_match(pattern, string = "")
        if (string += STDIN.gets) =~ pattern
          string
        else
          gets_until_match(pattern, string)
        end
      end
    end
  end
end
