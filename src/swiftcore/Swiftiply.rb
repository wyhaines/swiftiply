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
		Ccluster_address = 'cluster_address'.freeze
		Ccluster_port = 'cluster_port'.freeze
		CBackendAddress = 'BackendAddress'.freeze
		CBackendPort = 'BackendPort'.freeze
		Cmap = 'map'.freeze
		Cincoming = 'incoming'.freeze
		Ckeepalive = 'keepalive'.freeze
		Cdaemonize = 'daemonize'.freeze
		Curl = 'url'.freeze
		Chost = 'host'.freeze
		Cport = 'port'.freeze
		Coutgoing = 'outgoing'.freeze
		Ctimeout = 'timeout'.freeze
		Cdefault = 'default'.freeze

		# The ProxyBag is a class that holds the client and the server queues,
		# and that is responsible for managing them, matching them, and expiring
		# them, if necessary.

		class ProxyBag
			@client_q = Hash.new {|h,k| h[k] = []}
			@server_q = Hash.new {|h,k| h[k] = []}
			@ctime = Time.now
			@server_unavailable_timeout = 6

			class << self

				def now
					@ctime
				end

				# Returns the access key.  If an access key is set, then all new backend
				# connections must send the correct access key before being added to
				# the cluster as a valid backend.

				def key
					@key
				end

				# Sets the access key.

				def key=(val)
					@key = val
				end

				def default_name
					@default_name
				end

				def default_name=(val)
					@default_name = val
				end

				# This timeout is the amount of time a connection will sit in queue
				# waiting for a backend to process it.

				def server_unavailable_timeout
					@server_unavailable_timeout
				end

				# Sets the server unavailable timeout value.

				def server_unavailable_timeout=(val)
					@server_unavailable_timeout = val
				end

				# Pushes a front end client (web browser) into the queue of clients
				# waiting to be serviced if there's no server available to handle
				# it right now.

				def add_frontend_client clnt
					clnt.create_time = @ctime
					@client_q[clnt.name].unshift(clnt) unless match_client_to_server_now(clnt)
				end

				# Pushes a backend server into the queue of servers waiting for a
				# client to service if there are no clients waiting to be serviced.

				def add_server srvr
					@server_q[srvr.name].unshift(srvr) unless match_server_to_client_now(srvr)
				end

				# Deletes the provided server from the server queue.

				def remove_server srvr
					@server_q[srvr.name].delete srvr
				end

				# Removes the named client from the client queue.
				# TODO: Try replacing this with a linked list.  Performance
				# here has to suck when the list is long.

				def remove_client clnt
					@client_q[clnt.name].delete clnt
				end

				# Walks through the client and server queues, matching
				# waiting clients with waiting servers until the queue
				# runs out of one or the other.  DEPRECATED

				def match_clients_to_servers
					while @server_q.first && @client_q.first
						server = @server_q.pop
						client = @client_q.pop
						server.associate = client
						client.associate = server
						client.push
					end
				end

				# Tries to match the client passed as an argument to a
				# server.

				def match_client_to_server_now(client)
					if server = @server_q[client.name].pop
						#server = @server_q[client.name].pop
						server.associate = client
						client.associate = server
						client.push
						true
					else
						false
					end
				end
	
				# Tries to match the server passed as an argument to a
				# client.

				def match_server_to_client_now(server)
					if client = @client_q[server.name].pop
						#client = @client_q[server.name].pop
						server.associate = client
						client.associate = server
					client.push
						true
					else
						false
					end
				end

				# Walk through the waiting clients if there is no server
				# available to process clients and expire any clients that
				# have been waiting longer than @server_unavailable_timeout
				# seconds.  Clients which are expired will receive a 503
				# response.

				def expire_clients
					now = Time.now
					@server_q.each_key do |name|
						unless @server_q[name].first
							while c = @client_q[name].pop
								if (now - c.create_time) >= @server_unavailable_timeout
									c.send_503_response
								else
									@client_q[name].push c
									break
								end
							end
						end
					end
				end

				# This is called by a periodic timer once a second to update
				# the time.

				def update_ctime
					@ctime = Time.now
				end

			end
		end

		# The ClusterProtocol is the subclass of EventMachine::Connection used
		# to communicate between Swiftiply and the web browser clients.

		class ClusterProtocol < EventMachine::Connection
			attr_accessor :create_time, :associate, :name

			Crnrn = "\r\n\r\n".freeze
			Rrnrn = /\r\n\r\n/
			R_colon = /:/

			# Initialize the @data array, which is the temporary storage for blocks
			# of data received from the web browser client, then invoke the superclass
			# initialization.

			def initialize *args
				@data = []
				@name = nil
				super
			end

			# Receive data from the web browser client, then immediately try to
			# push it to a backend.

			def receive_data data
				@data.unshift data
				if @name
					push
				else
			#		if data =~ /^Host:\s*(.*)\s*$/
			#			@name = $1.chomp.split(R_colon,2).first
					if data =~ /^Host:\s*([^\r\n:]*)/
						@name = $1
						ProxyBag.add_frontend_client self
						push
					elsif data =~ /\r\n\r\n/
						@name = ProxyBag.default_name
						ProxyBag.add_frontend_client self
						push
					end
				end
			end

			# Hardcoded 503 response that is sent if a connection is timed out while
			# waiting for a backend to handle it.

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
	
			# Push data from the web browser client to the backend server process.

			def push
				if @associate
					while data = @data.pop
						@associate.send_data data
					end
				end
			end

			# The connection with the web browser client has been closed, so the
			# object must be removed from the ProxyBag's queue if it is has not
			# been associated with a backend.  If it has already been associated
			# with a backend, then it will not be in the queue and need not be
			# removed.

			def unbind
				ProxyBag.remove_client(self) unless @associate
			end
		end


		# The BackendProtocol is the EventMachine::Connection subclass that
		# handles the communications between Swiftiply and the backend process
		# it is proxying to.

		class BackendProtocol < EventMachine::Connection
			attr_accessor :associate

			Crnrn = "\r\n\r\n".freeze
			Rrnrn = /\r\n\r\n/

			def initialize *args
				@name = self.class.bname
				super
			end

			def name
				@name
			end

			# Call setup() and add the backend to the ProxyBag queue.

			def post_init
				setup
				ProxyBag.add_server self
			end

			# Setup the initial variables for receiving headers and content.

			def setup
				@headers = ''
				@headers_completed = false
				@content_length = nil
				@content_sent = 0
			end

			# Receive data from the backend process.  Headers are parsed from
			# the rest of the content, and the Content-Length header used to
			# determine when the complete response has been read.  The proxy
			# will attempt to maintain a persistent connection with the backend,
			# allowing for greater throughput.

			def receive_data data
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

			# This is called when the backend disconnects from the proxy.
			# If the backend is currently associated with a web browser client,
			# that connection will be closed.  Otherwise, the backend will be
			# removed from the ProxyBag's backend queue.

			def unbind
				if @associate
					@associate.close_connection_after_writing
				else
					ProxyBag.remove_server(self)
				end
			end

			def self.bname=(val)
				@bname = val
			end

			def self.bname
				@bname
			end
		end

		# Start the EventMachine event loop and create the front end and backend
		# handlers, then create the timers that are used to expire unserviced
		# clients and to update the Proxy's clock.

		def self.run(config, key = nil)
			EventMachine.run do
				EventMachine.start_server(config[Ccluster_address], config[Ccluster_port], ClusterProtocol)
				config[Cmap].each do |m|
					if m[Ckeepalive]
						m[Cincoming].each do |p|
							m[Coutgoing].each do |o|
								backend_class = Class.new(BackendProtocol)
								backend_class.bname = p
								ProxyBag.default_name = p if m[Cdefault]
								host, port = o.split(/:/,2)
								EventMachine.start_server(host, port.to_i, backend_class)
							end
						end
					end
				end
				ProxyBag.server_unavailable_timeout ||= config[Ctimeout]
				ProxyBag.key = key
				EventMachine.add_periodic_timer(2) { ProxyBag.expire_clients }
				EventMachine.add_periodic_timer(1) { ProxyBag.update_ctime }
			end
		end
	end
end

