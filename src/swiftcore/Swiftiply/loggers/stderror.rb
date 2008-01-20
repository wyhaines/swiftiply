module Swiftcore
	module Swiftiply
		module Loggers
			class Stderror
				def initialize(*args);end
				
				def log(severity, msg)
					$stderr.puts "#{Time.now.asctime}:#{severity}:#{msg}"
				end
			end
		end
	end
end