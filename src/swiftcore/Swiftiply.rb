begin
	load_attempted ||= false
	require 'digest/sha2'
	require 'eventmachine'
	require 'mime/types'
rescue LoadError => e
	unless load_attempted
		load_attempted = true
		require 'rubygems'
		retry
	end
	raise e
end

module Swiftcore
	module Swiftiply
		Version = '0.5.2'

		C_empty = ''.freeze
		C_slash = '/'.freeze
		C_slashindex_html = '/index.html'.freeze
		Ccluster_address = 'cluster_address'.freeze
		Ccluster_port = 'cluster_port'.freeze
		CBackendAddress = 'BackendAddress'.freeze
		CBackendPort = 'BackendPort'.freeze
		Cdaemonize = 'daemonize'.freeze
		Cdefault = 'default'.freeze
		Cdocroot = 'docroot'.freeze
		Chost = 'host'.freeze
		Cincoming = 'incoming'.freeze
		Ckeepalive = 'keepalive'.freeze
		Cmap = 'map'.freeze
		Cmsg_expired = 'browser connection expired'.freeze
		Coutgoing = 'outgoing'.freeze
		Cport = 'port'.freeze
		Credeployable = 'redeployable'.freeze
		Ctimeout = 'timeout'.freeze
		Curl = 'url'.freeze

		# The ProxyBag is a class that holds the client and the server queues,
		# and that is responsible for managing them, matching them, and expiring
		# them, if necessary.

		class ProxyBag
			@client_q = Hash.new {|h,k| h[k] = []}
			@server_q = Hash.new {|h,k| h[k] = []}
			@ctime = Time.now
			@server_unavailable_timeout = 6
			@id_map = {}
			@reverse_id_map = {}
			@incoming_map = {}
			@docroot_map = {}
			@log_map = {}
			@redeployable_map = {}
			@demanding_clients = Hash.new {|h,k| h[k] = []}

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

				def add_id(who,what)
					@id_map[who] = what
					@reverse_id_map[what] = who
				end

				def remove_id(who)
					what = @id_map.delete(who)
					@reverse_id_map.delete(what)
				end

				def add_incoming_mapping(hashcode,name)
					@incoming_map[name] = hashcode
				end

				def add_incoming_docroot(path,name)
					@docroot_map[name] = path
				end

				def add_incoming_redeployable(name)
					@redeployable_map[name] = true
				end

				def add_log(log,name)
					@log_map[name] = log
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

				# This is a NAIVE static file handler.  It's BAD for big files and
				# is very simplistic.  On my devel server it will do about 6500 4k
				# files per second.  This WILL be replaced by something faster,
				# smarter, and better.

				def serve_static_file(clnt)
					path_info = clnt.uri
					#if path_info == C_slash or path_info == C_empty
					#	path_info = C_slashindex_html
					#elsif path_info =~ /^([^.]+)$/
					#	path_info = "#{$1}/index.html"
					#end
					client_name = clnt.name
					dr = @docroot_map[client_name]
					path = File.join(dr,path_info)
					if FileTest.exist?(path)
						suffix = path_info.sub(/[_\s]*$/,C_empty)
						clnt.send_data "HTTP/1.1 200 OK\r\n"
						d = File.read(path)
						ct = ::MIME::Types.type_for(path_info.sub(/[_\s]*$/,C_empty)).first
						clnt.send_data "Connection: close\r\nDate: #{Time.now.httpdate}\r\nContent-Type: #{ct ? ct.content_type : 'application/octet-stream'}\r\nContent-Length: #{d.length}\r\n\r\n"
						clnt.send_data d
						clnt.close_connection_after_writing
						@log_map.has_key?(client_name) && log_map[client_name].log(Cinfo,path_info)
						true
					else
						false
					end
				rescue Object => e
					false
				end

				# Pushes a front end client (web browser) into the queue of clients
				# waiting to be serviced if there's no server available to handle
				# it right now.

				def add_frontend_client clnt
					clnt.create_time = @ctime

					if @redeployable_map.has_key?(clnt.name)
						clnt.redeployable = true
						clnt.data_pos = 0
					end

					unless @docroot_map.has_key?(clnt.name) and serve_static_file(clnt)
						unless match_client_to_server_now(clnt)
							if clnt.uri =~ /\w+-\w+-\w+\.\w+\.[\w\.]+-(\w+)?$/
								@demanding_clients[$1].unshift clnt
							else
								@client_q[@incoming_map[clnt.name]].unshift(clnt)
							end
						end
					end
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

				#def match_clients_to_servers
				#	while @server_q.first && @client_q.first
				#		server = @server_q.pop
				#		client = @client_q.pop
				#		server.associate = client
				#		client.associate = server
				#		client.push
				#	end
				#end

				# Tries to match the client passed as an argument to a
				# server.

				def match_client_to_server_now(client)
					sq = @server_q[@incoming_map[client.name]]
					if client.uri =~ /\w+-\w+-\w+\.\w+\.[\w\.]+-(\w+)?$/ and sidx = sq.index(@reverse_id_map[$1])
						server = sq.delete_at(sidx)
						server.associate = client
						client.associate = server
						client.push
						true
					elsif server = sq.pop
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
					if client = @demanding_clients[server.id].pop
						server.associate = client
						client.associate = server
						client.push
						true
					elsif client = @client_q[server.name].pop
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

			attr_accessor :create_time, :associate, :name, :redeployable, :data_pos

			Crn = "\r\n".freeze
			Crnrn = "\r\n\r\n".freeze
			Rrnrn = /\r\n\r\n/
			R_colon = /:/
			C_blank = ''.freeze

			# Initialize the @data array, which is the temporary storage for blocks
			# of data received from the web browser client, then invoke the superclass
			# initialization.

			def initialize *args
				@data = []
				@name = nil
				@uri = nil
				super
			end

			def receive_data data
				@data.unshift data
				if @name
					push
				else
					data =~ /\s([^\s\?]*)/
					@uri ||= $1
					if data =~ /^Host:\s*([^\r\n:]*)/
						@name = $1
						ProxyBag.add_frontend_client self
						push
					elsif data.index(/\r\n\r\n/)
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
					unless @redeployable
						# normal data push
						while data = @data.pop
							@associate.send_data data
						end
					else
						# redeployable data push
						(@data.length - 1).downto(@data_pos) {|p| @associate.send_data @data[p]}
						@data_pos = @data.length
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

			def uri
				@uri
			end

			def setup_for_redeployment
				@data_pos = 0
			end

		end

		# The BackendProtocol is the EventMachine::Connection subclass that
		# handles the communications between Swiftiply and the backend process
		# it is proxying to.

		class BackendProtocol < EventMachine::Connection
			attr_accessor :associate, :id

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
				@initialized = nil
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
				unless @initialized
					preamble = data.slice!(0..22)
					if preamble[0..10] == 'swiftclient'
						@id = preamble[11..22]
						ProxyBag.add_id(self,@id)
						@initialized = true
					else
						close_connection
						return
					end
				end
				unless @headers_completed 
					if data.index(Crnrn)
						@headers_completed = true
						h,d = data.split(Rrnrn)
						@headers << h << Crnrn
						@headers =~ /Content-Length:\s*([^\r\n]+)/
						@content_length = $1.to_i
						@associate.send_data @headers
						data = d
					else
						@headers << data
					end
				end

				if @headers_completed
					@associate.send_data data
					@content_sent += data.length
					if @content_sent >= @content_length
						@associate.close_connection_after_writing
						@associate = nil
						setup
						ProxyBag.add_server self
					end
				end
			rescue => e
				@associate.close_connection_after_writing if @associate
				@associate = nil
				setup
				ProxyBag.add_server self
			end

			# This is called when the backend disconnects from the proxy.
			# If the backend is currently associated with a web browser client,
			# that connection will be closed.  Otherwise, the backend will be
			# removed from the ProxyBag's backend queue.

			def unbind
				if @associate
					if !@associate.redeployable or @content_length
						@associate.close_connection_after_writing
					else
						@associate.associate = nil
						@associate.setup_for_redeployment
						ProxyBag.add_frontend_client(@associate)
					end
				else
					ProxyBag.remove_server(self)
				end
				ProxyBag.remove_id(self)
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
			existing_backends = {}
			EventMachine.run do
				EventMachine.start_server(config[Ccluster_address], config[Ccluster_port], ClusterProtocol)
				config[Cmap].each do |m|
					if m[Ckeepalive]
						incoming_hash = Digest::SHA256.hexdigest(m[Cincoming].join('|'))
						m[Cincoming].each do |p|
							ProxyBag.add_incoming_mapping(incoming_hash,p)
							ProxyBag.add_incoming_docroot(m[Cdocroot],p) if m.has_key? Cdocroot
							ProxyBag.add_incoming_redeployable(p) if m[Credeployable]
							m[Coutgoing].each do |o|
								ProxyBag.default_name = p if m[Cdefault]
								if existing_backends.has_key?(o)
									# Do we need to do anything here other than skip?
									next
								else
									existing_backends[o] = true
									backend_class = Class.new(BackendProtocol)
									backend_class.bname = incoming_hash
									host, port = o.split(/:/,2)
									EventMachine.start_server(host, port.to_i, backend_class)
								end
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

