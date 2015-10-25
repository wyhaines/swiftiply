require 'em-http'
module Swiftcore
	module Swiftiply
		module ManagerProtocols
			class RestBasedClusterManager
				def self.call(callsite, params)
					EventMachine::HttpRequest.new(callsite).get
					true
				rescue Exception
					false
				end
			end
		end		
	end
end