# The Swiftiply logging support is really written with Analogger in mind, since
# the ideal logging solution should provide a minimal performance impact.

require 'swiftcore/Analogger/EMClient'

module Swiftcore
	module Swiftiply
		module Loggers
			class Analogger
				def new(params)
					lp = []
					lp << params['service'] || 'swiftiply'
					lp << params['host'] || '127.0.0.1'
					lp << (params['port'] && params['port'].to_i) || 6766
					lp << params['key']
					::Swiftcore::Analogger::Client.new(*lp)
				end
			end
		end
	end
end