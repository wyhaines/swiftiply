# Encoding:ascii-8bit

module Swiftcore
  module Swiftiply
    class Config
      class RestUpdater

        def initialize(config)
          @config = config
        end

        def start
          host = @config[Chost] || '127.0.0.1'
          port = @config[Cport] || 9949
        end

        class RestUpdaterProtocol < EventMachine::Connection
          def receive_data data

          end
        end

      end
    end
  end
end
