# Config looks for a list of backends which are defined statically and puts them into a queue.
module Swiftcore
	module Swiftiply
		module Proxies
			class TraditionalStaticDirectory
				# servers:
				#   - http://site.com:port/url
				#   - http://site2.com:port2/url2
				def self.config(conf,new_config)
					@queue = ::Swiftcore.const_defined?(:Deque) ? Swiftcore::Deque.new : []
					servers = conf[Cservers]
					if Array === servers
						servers.each do |server|
							queue.push server
						end
					elsif servers
						queue.push servers
					end
				end

				def self.queue
					@queue
				end

				def self.backend_class
					@backend_class
				end

				def self.backend_class=(val)
					@backend_class = val
				end

				def initialize(*args)
					@queue = self.class.queue
					@backend_class = self.class.backend_class
				end

				# The queue is circular. Any element that is popped off the end is shifted back onto the front and vice versa.
				def pop
					server = @queue.pop
					host, port = server.split(C_colon,2)
					@queue.unshift server
					host ||= C_localhost
					port ||= C80
					EventMachine.connect(host,port,@backend_class)
				rescue Exception # In an ideal world, we do something useful with regard to logging/reporting this exception.
					false
				end

				def unshift(val)
					@queue.unshift val
				end

				def push(val)
					@queue.push val
				end

				def delete(val)
					@queue.delete val
				end

				def requeue(*args); end

				def status
				end
			end
		end
	end
end
