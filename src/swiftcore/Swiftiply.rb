begin
	load_attempted ||= false
	require 'digest/sha2'
	require 'eventmachine'
	require 'fastfilereaderext'
	require 'swiftcore/types'
	require 'swiftcore/deque'
	require 'swiftcore/splaytreemap'
#	require 'swiftcore/microparser'
#	require 'ruby-prof'
rescue LoadError => e
	unless load_attempted
		load_attempted = true
		# Ugh.  Everything gets slower once rubygems are used.  So, for the
		# best speed possible, don't install EventMachine or Swiftiply via
		# gems.
		require 'rubygems'
		retry
	end
	raise e
end


module Swiftcore

	#Deque = Array

	module Swiftiply
		Version = '0.6.3'

		# Yeah, these constants look kind of tacky.  Inside of tight loops,
		# though, using them makes a small but measurable difference, and those
		# small differences add up....
		C_empty = ''.freeze
		C_slash = '/'.freeze
		C_slashindex_html = '/index.html'.freeze
		Caos = 'application/octet-stream'.freeze
		Ccache_directory = 'cache_directory'.freeze
		Ccache_extensions = 'cache_extensions'.freeze
		Ccluster_address = 'cluster_address'.freeze
		Ccluster_port = 'cluster_port'.freeze
		Ccluster_server = 'cluster_server'.freeze
		CBackendAddress = 'BackendAddress'.freeze
		CBackendPort = 'BackendPort'.freeze
		Cchunked_encoding_threshold = 'chunked_encoding_threshold'.freeze
		Cdaemonize = 'daemonize'.freeze
		Cdefault = 'default'.freeze
		Cdescriptor_cache = 'descriptor_cache_threshold'.freeze
		Cdocroot = 'docroot'.freeze
		Cepoll = 'epoll'.freeze
		Cepoll_descriptors = 'epoll_descriptors'.freeze
		Cfile_cache = 'file_cache_threshold'.freeze
		Cgroup = 'group'.freeze
		Chost = 'host'.freeze
		Cincoming = 'incoming'.freeze
		Ckeepalive = 'keepalive'.freeze
		Ckey = 'key'.freeze
		Cmap = 'map'.freeze
		Cmax_cache_size = 'max_cache_size'.freeze
		Cmsg_expired = 'browser connection expired'.freeze
		Coutgoing = 'outgoing'.freeze
		Cport = 'port'.freeze
		Credeployable = 'redeployable'.freeze
		Credeployment_sizelimit = 'redeployment_sizelimit'.freeze
		Csize = 'size'.freeze
		Cswiftclient = 'swiftclient'.freeze
		Cthreshold = 'threshold'.freeze
		Ctimeout = 'timeout'.freeze
		Curl = 'url'.freeze
		Cuser = 'user'.freeze

		C_fsep = File::SEPARATOR
		
		RunningConfig = {}

		class EMStartServerError < RuntimeError; end
		
		# The ProxyBag is a class that holds the client and the server queues,
		# and that is responsible for managing them, matching them, and expiring
		# them, if necessary.

		class ProxyBag
			@client_q = Hash.new {|h,k| h[k] = Deque.new}
			#@client_q = Hash.new {|h,k| h[k] = []}
			@server_q = Hash.new {|h,k| h[k] = Deque.new}
			#@server_q = Hash.new {|h,k| h[k] = []}
			@ctime = Time.now
			@server_unavailable_timeout = 6
			@id_map = {}
			@reverse_id_map = {}
			@incoming_map = {}
			@docroot_map = {}
			@log_map = {}
			@redeployable_map = {}
			@file_cache_map = {}
			@file_cache_threshold_map = {}
			@keys = {}
			@demanding_clients = Hash.new {|h,k| h[k] = Deque.new}
			#@demanding_clients = Hash.new {|h,k| h[k] = []}
			@hitcounters = Hash.new {|h,k| h[k] = 0}
			# Kids, don't do this at home.  It's gross.
			@typer = MIME::Types.instance_variable_get('@__types__')

			@dcnt = 0

			class << self

				def now
					@ctime
				end

				# Returns the access key.  If an access key is set, then all new backend
				# connections must send the correct access key before being added to
				# the cluster as a valid backend.

				def get_key(h)
					@keys[h] || C_empty
				end

				def set_key(h,val)
					@keys[h] = val
				end

				def add_id(who,what)
					@id_map[who] = what
					@reverse_id_map[what] = who
				end

				def remove_id(who)
					what = @id_map.delete(who)
					@reverse_id_map.delete(what)
				end

				def incoming_mapping(name)
					@incoming_map[name]
				end
				
				def add_incoming_mapping(hashcode,name)
					@incoming_map[name] = hashcode
				end
				
				def remove_incoming_mapping(name)
					@incoming_map.delete(name)
				end

				def add_incoming_docroot(path,name)
					@docroot_map[name] = path
				end

				def remove_incoming_docroot(name)
					@docroot_map.delete(name)
				end

				def add_incoming_redeployable(limit,name)
					@redeployable_map[name] = limit
				end

				def remove_incoming_redeployable(name)
					@redeployable_map.delete(name)
				end
				
				def add_log(log,name)
					@log_map[name] = log
				end

				def add_file_cache(cache,name)
					@file_cache_map[name] = cache
				end

				# Sets the default proxy destination, if requests are received
				# which do not match a defined destination.
				
				def default_name
					@default_name
				end

				def default_name=(val)
					@default_name = val
				end

				# This timeout is the amount of time a connection will sit in queue
				# waiting for a backend to process it.  A client connection that
				# sits for longer than this timeout receives a 503 response and
				# is dropped.

				def server_unavailable_timeout
					@server_unavailable_timeout
				end

				def server_unavailable_timeout=(val)
					@server_unavailable_timeout = val
				end

				# The chunked_encoding_threshold is a file size limit.  Files
				# which fall below this limit are sent in one chunk of data.
				# Files which hit or exceed this limit are delivered via chunked
				# encoding.  This enforces a maximum threshold of 32k.
				
				def chunked_encoding_threshold
					@chunked_enconding_threshold
				end
				
				def chunked_encoding_threshold=(val)
					val = 32768 if val > 32768
					@chunked_encoding_threshold = val
				end

				# Handle static files.  It employs an extension to efficiently
				# handle large files, and depends on an addition to
				# EventMachine, send_file_data(), to efficiently handle small
				# files.  In my tests, it streams in excess of 120 megabytes of
				# data per second for large files, and does 8000+ to 9000+
				# requests per second with small files (i.e. under 4k).  I think
				# this can still be improved upon for small files.
				#
				# Todo for 0.7.0 -- add etag/if-modified/if-modified-since
				# support.
				#
				# TODO: Add support for logging static file delivery if wanted.
				#   The ideal logging would probably be to Analogger since it'd
				#   limit the performance impact of the the logging.
				#
				
				def serve_static_file(clnt)
					path_info = clnt.uri
					client_name = clnt.name
					dr = @docroot_map[client_name]
					fc = @file_cache_map[client_name]
					if data = fc[path_info]
						clnt.send_data "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Type: #{data.last}\r\nContent-Length: #{data[1]}\r\n\r\n"
						clnt.send_data data.first
						clnt.close_connection_after_writing
						true
					elsif path = find_static_file(dr,path_info,client_name)
						#ct = ::MIME::Types.type_for(path).first || Caos
						ct = @typer.simple_type_for(path) || Caos
						fsize = File.size(path)
						if fsize > @chunked_encoding_threshold
							clnt.send_data "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Type: #{ct}\r\nTransfer-Encoding: chunked\r\n\r\n"
							EM::Deferrable.future(clnt.stream_file_data(path, :http_chunks=>true)) {clnt.close_connection_after_writing}
						else
							clnt.send_data "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Type: #{ct}\r\nContent-Length: #{fsize}\r\n\r\n"
							clnt.send_file_data path
							fd = File.read(path)
							fc[path_info] = [fd,fd.length,ct]
							clnt.close_connection_after_writing
						end
						true
					else
						false
					end
					# The exception is going to be eaten here, because some
					# dumb file IO error shouldn't take Swiftiply down.
					# TODO: It should log these errors, though.
				rescue Object => e
					puts "path: #{dr.inspect} / #{path.inspect}"
puts e
puts e.backtrace.join("\n")
					clnt.close_connection_after_writing
					false
				end

				# Determine if the requested file, in the given docroot, exists
				# and is a file (i.e. not a directory).
				#
				# If Rails style page caching is enabled, this method will be
				# dynamically replaced by a more sophisticated version.
				
				def find_static_file(docroot,path_info,client_name)
					path = File.join(docroot,path_info)
					FileTest.exist?(path) and FileTest.file?(path) and File.expand_path(path).index(docroot) == 0 ? path : false
				end
				
				# Pushes a front end client (web browser) into the queue of clients
				# waiting to be serviced if there's no server available to handle
				# it right now.

				def add_frontend_client(clnt,data_q,data)
					clnt.create_time = @ctime
					clnt.data_pos = clnt.data_len = 0 if clnt.redeployable = @redeployable_map[clnt.name]

					unless @docroot_map.has_key?(clnt.name) and serve_static_file(clnt)
						data_q.unshift data
						unless match_client_to_server_now(clnt)
							#if clnt.uri =~ /\w+-\w+-\w+\.\w+\.[\w\.]+-(\w+)?$/
							if $&
								@demanding_clients[$1].unshift clnt
							else
								@client_q[@incoming_map[clnt.name]].unshift(clnt)
							end
						end
						#clnt.push ## wasted call, yes?
					end
				end
				
				def rebind_frontend_client(clnt)
					clnt.create_time = @ctime
					clnt.data_pos = clnt.data_len = 0
					
					unless match_client_to_server_now(clnt)
						#if clnt.uri =~ /\w+-\w+-\w+\.\w+\.[\w\.]+-(\w+)?$/
						if $&
							@demanding_clients[$1].unshift clnt
						else
							@client_q[@incoming_map[clnt.name]].unshift(clnt)
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
				# TODO: Try replacing this with ...something.  Performance
				# here has to be bad when the list is long.
				
				def remove_client clnt
					@client_q[clnt.name].delete clnt
				end

				# Tries to match the client (passed as an argument) to a
				# server.

				def match_client_to_server_now(client)
					sq = @server_q[@incoming_map[client.name]]
					if sq.empty?
						false
					elsif client.uri =~ /\w+-\w+-\w+\.\w+\.[\w\.]+-(\w+)?$/
						if sidx = sq.index(@reverse_id_map[$1])
							server = sq.delete_at(sidx)
							server.associate = client
							client.associate = server
							client.push
							true
						else
							false
						end
					elsif server = sq.pop
						server.associate = client
						client.associate = server
						client.push
						true
					else
						false
					end
				end
	
				# Tries to match the server (passed as an argument) to a
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
				# response.  If this is happening, either you need more
				# backend processes, or you @server_unavailable_timeout is
				# too short.

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

				def dcnt
					@dcnt += 1
				end

			end
		end

		# The ClusterProtocol is the subclass of EventMachine::Connection used
		# to communicate between Swiftiply and the web browser clients.

		class ClusterProtocol < EventMachine::Connection
#			include Swiftcore::MicroParser

			attr_accessor :create_time, :associate, :name, :redeployable, :data_pos, :data_len

			Crn = "\r\n".freeze
			Crnrn = "\r\n\r\n".freeze
			C_blank = ''.freeze
			C503Header = "HTTP/1.0 503 Server Unavailable\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n"

			# Initialize the @data array, which is the temporary storage for blocks
			# of data received from the web browser client, then invoke the superclass
			# initialization.

			def initialize *args
				@data = Deque.new
				#@data = []
				@data_pos = 0
				@name = @uri = nil
				super
			end

			def receive_data data
				if @name
					@data.unshift data
					push
				else
					# Note the \0 below.  intern() blows up when passed a \0.  People who are trying to break a server like to pass \0s.  This should cope with that.
					if data =~ /^Host:\s*([^\r\0:]+)/
						# NOTE: Should I be using intern for this?  It might not
						# be a good idea.
						@name = $1.intern
						
						data =~ /\s([^\s\?]*)/
						@uri = $1
						@uri = @uri.to_s.tr('+', ' ').gsub(/((?:%[0-9a-fA-F]{2})+)/n) {[$1.delete('%')].pack('H*')} if @uri =~ /%/
						@name = ProxyBag.default_name unless ProxyBag.incoming_mapping(@name)
						ProxyBag.add_frontend_client(self,@data,data)
					elsif data =~ /\r\n\r\n/
						@name = ProxyBag.default_name
						data =~ /\s([^\s\?]*)/
						@uri = $1
						@uri = @uri.to_s.tr('+', ' ').gsub(/((?:%[0-9a-fA-F]{2})+)/n) {[$1.delete('%')].pack('H*')} if @uri =~ /%/
						ProxyBag.add_frontend_client(self,@data,data)
					end
#					r = consume_data(data)
#
#					close_connection unless r
#					if @_http_parsed
#						if @http_host
#							@name = @http_host.intern
#							@uri = @http_request_uri
#							@name = ProxyBag.default_name unless ProxyBag.incoming_mapping(@name)
#							ProxyBag.add_frontend_client(self,@data,data)
#						else
#							@name = ProxyBag.default_name
#							@uri = @http_request_uri
#							ProxyBag.add_frontend_client(self,@data,data)
#						end
#					else
#						@data.unshift data
#					end
				end
			end

			# Hardcoded 503 response that is sent if a connection is timed out while
			# waiting for a backend to handle it.

			def send_503_response
				send_data "#{C503Header}Server Unavailable\n\nThe request (#{@uri} --> #{@name}), received on #{create_time.asctime} timed out before being deployed to a server for processing."
				close_connection_after_writing
			end
	
			# Push data from the web browser client to the backend server process.

			def push
				if @associate
					unless @redeployable
						# normal data push
						data = nil
						@associate.send_data data while data = @data.pop
					else
						# redeployable data push; just send the stuff that has
						# not already been sent.
						(@data.length - 1 - @data_pos).downto(0) do |p|
							d = @data[p]
							@associate.send_data d
							@data_len += d.length
						end
						@data_pos = @data.length

						# If the request size crosses the size limit, then
						# disallow redeployent of this request.
						if @data_len > @redeployable
							@redeployable = false
							@data.clear
						end
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

			C0rnrn = "0\r\n\r\n".freeze
			Crnrn = "\r\n\r\n".freeze

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
				#@content_length = nil
				@content_sent = 0
			end
			
			# Receive data from the backend process.  Headers are parsed from
			# the rest of the content.  If a Content-Length header is present,
			# that is used to determine how much data to expect.  Otherwise,
			# if 'Transfer-encoding: chunked' is present, assume chunked
			# encoding.  Otherwise be paranoid; something isn't the way we like
			# it to be.

			def receive_data data
				unless @initialized
					preamble = data.slice!(0..24)
					
					keylen = preamble[23..24].to_i(16)
					keylen = 0 if keylen < 0
					key = keylen > 0 ? data.slice!(0..(keylen - 1)) : C_empty
					if preamble[0..10] == Cswiftclient and key == ProxyBag.get_key(@name)
						@id = preamble[11..22]
						ProxyBag.add_id(self,@id)
						@initialized = true
					else
						close_connection
						return
					end
				end
				
				unless @headers_completed 
					if data =~ /\r\n\r\n/
						@headers_completed = true
						h,data = data.split(/\r\n\r\n/,2)
						@headers << h << Crnrn
						if @headers =~ /Content-[Ll]ength:\s*([^\r]+)/
							@content_length = $1.to_i
						elsif @headers =~ /Transfer-encoding:\s*chunked/
							@content_length = nil
						else
							@content_length = 0
						end
						@associate.send_data @headers
					else
						@headers << data
					end
				end

				if @headers_completed
					@associate.send_data data
					@content_sent += data.length
					if @content_length and @content_sent >= @content_length or data[-6..-1] == C0rnrn
						@associate.close_connection_after_writing
						@associate = nil
						@headers = ''
						@headers_completed = false
						#@content_length = nil
						@content_sent = 0
						#setup
						ProxyBag.add_server self
					end
				end
			# TODO: Log these errors!
			rescue
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
						ProxyBag.rebind_frontend_client(@associate)
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

		def self.run(config)
			@existing_backends = {}
			
			# Default is to assume we want to try to turn epoll support on.  EM
			# ignores this on platforms that don't support it, so this is safe.
			unless config.has_key?(Cepoll) and !config[Cepoll]
				EventMachine.epoll
				EventMachine.set_descriptor_table_size(4096 || config[Cepoll_descriptors])
			end
			EventMachine.run do
				trap("HUP") {em_config(Swiftcore::SwiftiplyExec.parse_options); GC.start}
				trap("INT") {EventMachine.stop_event_loop}
				em_config(config)
				GC.start
				#RubyProf.start
			end
			#result = RubyProf.stop

			#printer = RubyProf::TextPrinter.new(result)
			#File.open('/tmp/swprof','w+') {|fh| printer = printer.print(fh,0)}
		end
		
		def self.em_config(config)
			new_config = {}
			if RunningConfig[Ccluster_address] != config[Ccluster_address] or RunningConfig[Ccluster_port] != config[Ccluster_port]
				begin
			    	new_config[Ccluster_server] = EventMachine.start_server(
                	config[Ccluster_address],
                	config[Ccluster_port],
                	ClusterProtocol)
				rescue RuntimeError => e
					advice = ''
					if config[Ccluster_port] < 1024
						advice << 'Make sure you have the correct permissions to use that port, and make sure there is nothing else running on that port.'
					else
						advice << 'Make sure there is nothing else running on that port.'
					end
					advice << "  The original error was:  #{e}\n"
					raise EMStartServerError.new("The listener on #{config[Ccluster_address]}:#{config[Ccluster_port]} could not be started.\n#{advice}")
				end
				new_config[Ccluster_address] = config[Ccluster_address]
				new_config[Ccluster_port] = config[Ccluster_port]
		    	EventMachine.stop_server(RunningConfig[Ccluster_server]) if RunningConfig.has_key?(Ccluster_server)
			else
				new_config[Ccluster_server] = RunningConfig[Ccluster_server]
				new_config[Ccluster_address] = RunningConfig[Ccluster_address]
				new_config[Ccluster_port] = RunningConfig[Ccluster_port]
			end
		    	
			new_config[Coutgoing] = {}

			config[Cmap].each do |m|
				if m[Ckeepalive]
					# keepalive requests are standard Swiftiply requests.
					
					# The hash of the "outgoing" config section.  It is used to
					# uniquely identify a section.
					hash = Digest::SHA256.hexdigest(m[Cincoming].sort.join('|')).intern
					
					filecache = Swiftcore::SplayTreeMap.new
					sz = 100
					if m.has_key?(Cfile_cache)
						sz = m[Cfile_cache][Csize] || 100
						sz = 100 if sz < 0
					end
					filecache.max_size = sz

					# For each incoming entry, do setup.
					new_config[Cincoming] = {}
					m[Cincoming].each do |p_|
						p = p_.intern
						new_config[Cincoming][p] = {}
						ProxyBag.add_incoming_mapping(hash,p)
						ProxyBag.add_file_cache(filecache,p)
						
						if m.has_key?(Cdocroot)
							ProxyBag.add_incoming_docroot(m[Cdocroot],p)
						else
							ProxyBag.remove_incoming_docroot(p)
						end
						
						if m[Credeployable]
							ProxyBag.add_incoming_redeployable(m[Credeployment_sizelimit] || 16384,p)
						else
							ProxyBag.remove_incoming_redeployable(p)
						end
						
						if m.has_key?(Ckey)
							ProxyBag.set_key(hash,m[Ckey])
						else
							ProxyBag.set_key(hash,C_empty)
						end
						
						if m.has_key?(Ccache_extensions) or m.has_key?(Ccache_directory)
							require 'swiftcore/Swiftiply/support_pagecache'
							ProxyBag.add_suffix_list((m[Ccache_extensions] || ProxyBag.const_get(:DefaultSuffixes)),p)
							ProxyBag.add_cache_dir((m[Ccache_directory] || ProxyBag.const_get(:DefaultCacheDir)),p)
						else
							ProxyBag.remove_suffix_list(p) if ProxyBag.respond_to?(:remove_suffix_list)
							ProxyBag.remove_cache_dir(p) if ProxyBag.respond_to?(:remove_cache_dir)
						end
							
						m[Coutgoing].each do |o|
							ProxyBag.default_name = p if m[Cdefault]
							if @existing_backends.has_key?(o)
								new_config[Coutgoing][o] ||= RunningConfig[Coutgoing][o]
								next
							else
								@existing_backends[o] = true
								backend_class = Class.new(BackendProtocol)
								backend_class.bname = hash
								host, port = o.split(/:/,2)
								begin
									new_config[Coutgoing][o] = EventMachine.start_server(host, port.to_i, backend_class)
								rescue RuntimeError => e
									advice = ''
									if port.to_i < 1024
										advice << 'Make sure you have the correct permissions to use that port, and make sure there is nothing else running on that port.'
									else
										advice << 'Make sure there is nothing else running on that port.'
									end
									advice << "  The original error was:  #{e}\n"
									raise EMStartServerError.new("The listener on #{host}:#{port} could not be started.\n#{advice}")
								end
							end
						end
						
						# Now stop everything that is still running but which isn't needed.
						if RunningConfig.has_key?(Coutgoing)
							(RunningConfig[Coutgoing].keys - new_config[Coutgoing].keys).each do |unneeded_server_key|
								EventMachine.stop_server(RunningConfig[Coutgoing][unneeded_server_key])
							end
						end
					end
				else
					# This is where the code goes that sets up traditional proxy destinations.
					# This is a future TODO item.	
				end
			end

			#EventMachine.set_effective_user = config[Cuser] if config[Cuser] and RunningConfig[Cuser] != config[Cuser]
			run_as(config[Cuser],config[Cgroup]) if (config[Cuser] and RunningConfig[Cuser] != config[Cuser]) or (config[Cgroup] and RunningConfig[Cgroup] != config[Cgroup])
			new_config[Cuser] = config[Cuser]
			new_config[Cgroup] = config[Cgroup]
			
			ProxyBag.server_unavailable_timeout ||= config[Ctimeout]
			ProxyBag.chunked_encoding_threshold = config[Cchunked_encoding_threshold] || 16384
			
			unless RunningConfig[:initialized]
				EventMachine.add_periodic_timer(2) { ProxyBag.expire_clients }
				EventMachine.add_periodic_timer(1) { ProxyBag.update_ctime }
				new_config[:initialized] = true
			end
			
			RunningConfig.replace new_config
		end
		
		
		# This can be used to change the effective user and group that
		# Swiftiply is running as.
		
		def self.run_as(user = "nobody", group = "nobody")
			Process.initgroups(user,Etc.getgrnam(group).gid) if user and group
			::Process::GID.change_privilege(Etc.getgrnam(group).gid) if group
			::Process::UID.change_privilege(Etc.getpwnam(user).uid) if user
		rescue Errno::EPERM
			raise "Failed to change the effective user to #{user} and the group to #{group}"
		end
	end
end

