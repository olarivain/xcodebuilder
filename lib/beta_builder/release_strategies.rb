module BetaBuilder
  module ReleaseStrategies
    def self.valid_strategy?(strategy_name)
      strategies.keys.include?(strategy_name.to_sym)
    end

    def self.build(strategy_name, configuration)
      strategies[strategy_name.to_sym].new(configuration)
    end

    class ReleaseStrategy
      def initialize(configuration)
        @configuration = configuration
      end

      def configure(&block)
        yield self
      end
    end

    def prepare
        puts "Nothing to prepare!" if @configuration.verbose
      end

    private

    def self.strategies
      {:git => Git}
    end
  end
end

require File.dirname(__FILE__) + '/release_strategies/git'

