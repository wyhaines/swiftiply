begin
	load_attempted ||= false
	require 'eventmachine'
rescue LoadError => e
	unless load_attempted
		load_attempted = true
		require 'rubygems'
	end
	raise e
end

module Swiftcore
	module Swiftiply
		class ProxyBag
			@client_q = []
			@server_q = []
			@ctime = Time.now
			@server_unavailable_timeout = 3

			class << self

				def key
					@key
				end

				def key=(val)
					@key = val
				end

				def server_unavailable_timeout
					@server_unavailable_timeout
				end

				def server_unavailable_timeout=(val)
					@server_unavailable_timeout = val
				end

				def add_frontend_client clnt
					clnt.create_time = @ctime
					@client_q.unshift(clnt) unless match_client_to_server_now(clnt)
				end

				def add_server srvr
					@server_q.unshift(srvr) unless match_server_to_client_now(srvr)
				end

				def remove_server srvr
					@server_q.delete srvr
				end

				def remove_client clnt
					@client_q.delete clnt
				end

				def match_clients_to_servers
					while @server_q.first && @client_q.first
						server = @server_q.pop
						client = @client_q.pop
						server.associate = client
						client.associate = server
						client.push
					end
				end

				def match_client_to_server_now(client)
					if @server_q.first
						server = @server_q.pop
						server.associate = client
						client.associate = server
						client.push
						true
					else
						false
					end
				end
	
				def match_server_to_client_now(server)
					if @client_q.first
						client = @client_q.pop
						server.associate = client
						client.associate = server
					client.push
						true
					else
						false
					end
				end

				def expire_clients
					now = Time.now
					unless @server_q.first
						while c = @client_q.pop
							if (now - c.create_time) >= @server_unavailable_timeout
								c.send_503_response
							else
								@client_q.push c
								break
							end
						end
					end
				end

				def update_ctime
					@ctime = Time.now
				end

			end
		end


		class ClusterProtocol < EventMachine::Connection
			attr_accessor :create_time, :associate

			def initialize *args
				@data = []
				super
			end

			def post_init
				ProxyBag.add_frontend_client self
			end

			def receive_data data
				@data.unshift data
				push
			end

			def send_503_response
				send_data [
					"HTTP/1.0 503 Server Unavailable\r\n",
					"Content-type: text/plain\r\n",
					"Connection: close\r\n",
					"\r\n",
					"Server Unavailable"
				].join
				close_connection_after_writing
			end
	
			def push
				if @associate
					while data = @data.pop
						@associate.send_data data
					end
				end
			end

			def unbind
				ProxyBag.remove_client(self) unless @associate
			end
		end

		class BackendProtocol < EventMachine::Connection
			attr_accessor :associate

			Crnrn = "\r\n\r\n".freeze
			Rrnrn = /\r\n\r\n/

			def post_init
				setup
				ProxyBag.add_server self
			end

			def setup
				@headers = ''
				@headers_completed = false
				@content_length = nil
				@content_sent = 0
			end

			def receive_data data
				# In HTTP, the client talks first so the server will NEVER
				# say anything unless there is an associate.
				#@associate.send_data data
				unless @headers_completed 
					@headers_completed = true if data.index(Crnrn)
					if @headers_completed
						h,d = data.split(Rrnrn)
						@headers << h << Crnrn
						@headers =~ /Content-Length:\s*(\d+)/
						@content_length = $1.to_i
						@associate.send_data @headers
						@associate.send_data d
						@content_sent += d.length
					else
						@headers << data
					end
				end
	
				if @headers_completed 
					if @content_sent < @content_length
						@associate.send_data data
						@content_sent += data.length
					else
						@associate.close_connection_after_writing
						@associate = nil
						setup
						ProxyBag.add_server self
					end
				end
			end

			def unbind
				if @associate
					@associate.close_connection_after_writing
				else
					ProxyBag.remove_server(self)
				end
			end
		end

		def self.run(cluster_address,cluster_port,backend_address,backend_port,unavailable_timeout = 3, key = nil)
			EventMachine.run do
				EventMachine.start_server cluster_address, cluster_port, ClusterProtocol
				EventMachine.start_server backend_address, backend_port, BackendProtocol
				ProxyBag.server_unavailable_timeout = unavailable_timeout
				ProxyBag.key = key
				EventMachine.add_periodic_timer(1) { ProxyBag.expire_clients }
				EventMachine.add_periodic_timer(1) { ProxyBag.update_ctime }
			end
		end
	end
end

