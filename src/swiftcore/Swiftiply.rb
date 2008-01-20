module Swiftcore

	# A little statemachine for loading requirements.  The intention is to
	# only load rubygems if necessary, and to load the Deque and SplayTreeMap
	# classes if they are available and set a constant accordingly so that
	# the fallbacks (Array and Hash) can be used if they are not.
	begin
		load_state ||= :start
		rubygems_loaded ||= false
		require 'digest/sha2'
		require 'eventmachine'
		require 'fastfilereaderext'
		require 'swiftcore/types'
		
		load_state = :deque
		require 'swiftcore/deque'
		HasDeque = true unless const_defined?(:HasDeque)
		
		load_state = :splaytreemap
		require 'swiftcore/splaytreemap'
		HasSplayTree = true unless const_defined?(:HasSplayTree)
		
		load_state = :remainder
		require 'swiftcore/streamer'
		require 'swiftcore/Swiftiply/etag_cache'
		require 'swiftcore/Swiftiply/file_cache'
		require 'swiftcore/Swiftiply/dynamic_request_cache'
		require 'time'
	#	require 'swiftcore/microparser'
	#	require 'ruby-prof'
	rescue LoadError => e
		unless rubygems_loaded
			# Ugh.  Everything gets slower once rubygems are used.  So, for the
			# best speed possible, don't install EventMachine or Swiftiply via
			# gems.
			begin
				require 'rubygems'
				rubygems_loaded = true
			rescue LoadError
				raise e
			end
			retry
		end
		case load_state
		when :deque
			HasDeque = false unless const_defined?(:HasDeque)
			retry
		when :splaytreemap
			HasSplayTree = false unless const_defined?(:HasSplayTree)
			retry
		end
		raise e
	end

	Deque = Array unless HasDeque

	module Swiftiply
		Version = '0.6.3'

		# Yeah, these constants look kind of tacky.  Inside of tight loops,
		# though, using them makes a small but measurable difference, and those
		# small differences add up....
		C_asterisk = '*'.freeze
		C_empty = ''.freeze
		C_header_close = 'HTTP/1.1 200 OK\r\nConnection: close\r\n'.freeze
		C_header_keepalive = 'HTTP/1.1 200 OK\r\n'.freeze
		C_slash = '/'.freeze
		C_slashindex_html = '/index.html'.freeze
		C1_0 = '1.0'.freeze
		C1_1 = '1.1'.freeze
		C_304 = "HTTP/1.1 304 Not Modified\r\n\r\n".freeze
		Caos = 'application/octet-stream'.freeze
		Cat = 'at'.freeze
		Ccache_directory = 'cache_directory'.freeze
		Ccache_extensions = 'cache_extensions'.freeze
		Ccluster_address = 'cluster_address'.freeze
		Ccluster_port = 'cluster_port'.freeze
		Ccluster_server = 'cluster_server'.freeze
		CConnection_close = "Connection: close\r\n".freeze
		CBackendAddress = 'BackendAddress'.freeze
		CBackendPort = 'BackendPort'.freeze
		Ccertfile = 'certfile'.freeze
		Cchunked_encoding_threshold = 'chunked_encoding_threshold'.freeze
		Cdaemonize = 'daemonize'.freeze
		Cdefault = 'default'.freeze
		Cdescriptor_cache = 'descriptor_cache_threshold'.freeze
		Cdescriptors = 'descriptors'.freeze
		Cdocroot = 'docroot'.freeze
		Cdynamic_request_cache = 'dynamic_request_cache'.freeze
		Cenable_sendfile_404 = 'enable_sendfile_404'.freeze
		Cepoll = 'epoll'.freeze
		Cepoll_descriptors = 'epoll_descriptors'.freeze
		Cetag_cache = 'etag_cache'.freeze
		Cfile_cache = 'file_cache_threshold'.freeze
		CGET = 'GET'.freeze
		Cgroup = 'group'.freeze
		CHEAD = 'HEAD'.freeze
		Chost = 'host'.freeze
		Cincoming = 'incoming'.freeze
		Ckeepalive = 'keepalive'.freeze
		Ckey = 'key'.freeze
		Ckeyfile = 'keyfile'.freeze
		Cmap = 'map'.freeze
		Cmax_cache_size = 'max_cache_size'.freeze
		Cmsg_expired = 'browser connection expired'.freeze
		Coutgoing = 'outgoing'.freeze
		Cport = 'port'.freeze
		Credeployable = 'redeployable'.freeze
		Credeployment_sizelimit = 'redeployment_sizelimit'.freeze
		Csendfileroot = 'sendfileroot'.freeze
		Cservers = 'servers'.freeze
		Cssl = 'ssl'.freeze
		Csize = 'size'.freeze
		Cswiftclient = 'swiftclient'.freeze
		Cthreshold = 'threshold'.freeze
		Ctimeslice = 'timeslice'.freeze
		Ctimeout = 'timeout'.freeze
		Curl = 'url'.freeze
		Cuser = 'user'.freeze
		Cwindow = 'window'.freeze

		C_fsep = File::SEPARATOR
		
		RunningConfig = {}

		class EMStartServerError < RuntimeError; end
		class SwiftiplyLoggerNotFound < RuntimeError; end
		
		# The ProxyBag is a class that holds the client and the server queues,
		# and that is responsible for managing them, matching them, and expiring
		# them, if necessary.

		class ProxyBag
			@client_q = Hash.new {|h,k| h[k] = Deque.new}
			#@client_q = Hash.new {|h,k| h[k] = []}
			@server_q = Hash.new {|h,k| h[k] = Deque.new}
			#@server_q = Hash.new {|h,k| h[k] = []}
			@logger = nil
			@ctime = Time.now
			@server_unavailable_timeout = 6
			@id_map = {}
			@reverse_id_map = {}
			@incoming_map = {}
			@docroot_map = {}
			@sendfileroot_map = {}
			@log_map = {}
			@redeployable_map = {}
			@file_cache_map = {}
			@dynamic_request_map = {}
			@etag_cache_map = {}
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

				# Setter and Getter accessors for the logger.
				def logger=(val)
					@logger = val
				end
				
				def logger
					@logger
				end
				
				def log_level=(val)
					@log_level = val
				end
				
				def log_level
					@log_level
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

				def add_incoming_sendfileroot(path,name)
					@sendfileroot_map[name] = path
				end
				
				def remove_incoming_sendfileroot(name)
					@sendfileroot_map.delete(name)
				end
				
				def get_sendfileroot(name)
					@sendfileroot_map[name]
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

				def add_dynamic_request_cache(cache,name)
					@dynamic_request_map[name] = cache
				end

				def add_etag_cache(cache,name)
					@etag_cache_map[name] = cache
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

				# Swiftiply maintains caches of small static files, etags, and
				# dynamnic request paths for each cluster of backends.
				# A timer is created when each cache is created, to do the
				# initial update.  Thereafer, the verification method on the
				# cache returns the number of seconds to wait before running
				# again.
				
				def verify_cache(cache)
					EventMachine.add_timer(cache.check_verification_queue) do
						verify_cache(cache)
					end
				end
				
				# Handle static files.  It employs an extension to efficiently
				# handle large files, and depends on an addition to
				# EventMachine, send_file_data(), to efficiently handle small
				# files.  In my tests, it streams in excess of 120 megabytes of
				# data per second for large files, and does 8000+ to 9000+
				# requests per second with small files (i.e. under 4k).  I think
				# this can still be improved upon for small files.
				#
				# TODO: Add support for logging static file delivery if wanted.
				#   The ideal logging would probably be to Analogger since it'd
				#   limit the performance impact of the the logging.
				#
				
				def serve_static_file(clnt,dr = nil)
					request_method = clnt.request_method
					
					# Only GET and HEAD requests can return a file.
					if request_method == CGET || request_method == CHEAD
						path_info = clnt.uri
						client_name = clnt.name
						dr ||= @docroot_map[client_name]
						fc = @file_cache_map[client_name]
						if data = fc[path_info]
							none_match = clnt.none_match
							same_response = case
								when request_method == CHEAD : false
								when none_match && none_match == C_asterisk : false
								when none_match && !none_match.strip.split(/\s*,\s*/).include?(data[1]) : false
								else none_match
								end
	
							if same_response
								clnt.send_data C_304
							else
								#clnt.send_data data.last
								#clnt.send_data data.first unless request_method == CHEAD
								unless request_method == CHEAD
									clnt.send_data data.last + data.first
								else
									clnt.send_data data.last
								end
							end
							clnt.close_connection_after_writing
							true
						elsif path = find_static_file(dr,path_info,client_name)
							none_match = clnt.none_match
							etag,mtime = @etag_cache_map[client_name].etag_mtime(path)
							same_response = nil
							same_response = case
								when request_method == CHEAD : false
								when none_match && none_match == C_asterisk : false
								when none_match && !none_match.strip.split(/\s*,\s*/).include?(etag) : false
								else none_match
							end
	
							if same_response
								clnt.send_data C_304
								clnt.close_connection_after_writing
							else
								ct = @typer.simple_type_for(path) || Caos
								fsize = File.size(path)
								if fsize <= @chunked_encoding_threshold
									header_line = "HTTP/1.1 200 OK\r\nConnection: close\r\nETag: #{etag}\r\nContent-Type: #{ct}\r\nContent-Length: #{fsize}\r\n\r\n"
									clnt.send_data header_line
									clnt.send_file_data path unless request_method == CHEAD
									fd = File.read(path)
									fc[path_info] = [fd,etag,mtime,header_line]
									clnt.close_connection_after_writing
								elsif clnt.http_version != C1_0 && fsize > @chunked_encoding_threshold
									clnt.send_data "HTTP/1.1 200 OK\r\nConnection: close\r\nETag: #{etag}\r\nContent-Type: #{ct}\r\nTransfer-Encoding: chunked\r\n\r\n"
									EM::Deferrable.future(clnt.stream_file_data(path, :http_chunks=>true)) {clnt.close_connection_after_writing} unless request_method == CHEAD
								else
									clnt.send_data "HTTP/1.1 200 OK\r\nConnection: close\r\nETag: #{etag}\r\nContent-Type: #{ct}\r\nContent-Length: #{fsize}\r\n\r\n"
									EM::Deferrable.future(clnt.stream_file_data(path, :http_chunks=>false)) {clnt.close_connection_after_writing} unless request_method == CHEAD
								end
							end
							true
						end
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

					uri = clnt.uri
					name = clnt.name
					drc = @dynamic_request_map[name]
					if drc[uri] || !(@docroot_map.has_key?(name) && serve_static_file(clnt))
						# It takes two requests to add it to the verification queue.
						unless drcval = drc[uri]
							drc[uri] = drcval == false ? drc.add_to_verification_queue(uri) : false
						end
						data_q.unshift data
						unless match_client_to_server_now(clnt)
							#if clnt.uri =~ /\w+-\w+-\w+\.\w+\.[\w\.]+-(\w+)?$/
							if $&
								@demanding_clients[$1].unshift clnt
							else
								@client_q[@incoming_map[name]].unshift(clnt)
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
			attr_writer :uri

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
				@hmp = @name = @uri = @http_version = @request_method = @none_match = @done_parsing = nil
				super
			end

			# States:
			# uri
			# name
			# \r\n\r\n
			#   If-None-Match
			#   If-Modified-Since
			# Done Parsing
			def receive_data data
				if @done_parsing
					@data.unshift data
					push
				else
					unless @uri
						data =~ /^(\w+)\s+([^\s\?]+).*(1.\d)/
						@uri = $2 || C_blank
						@http_version = $3
						@request_method = $1
						@uri = @uri.to_s.tr('+', ' ').gsub(/((?:%[0-9a-fA-F]{2})+)/n) {[$1.delete('%')].pack('H*')} if @uri =~ /%/
					end
					unless @name
						if data =~ /^Host:\s*([^\r\0:]+)/
							@name = $1.intern
							@name = ProxyBag.default_name unless ProxyBag.incoming_mapping(@name)
						end
					end
					if @hmp
						d = @data.join
					else
						d = data
					end
					if d =~ /\r\n\r\n/
						@name ||= ProxyBag.default_name
						@done_parsing = true
						if data =~ /^If-None-Match:\s*([^\r]+)/
							@none_match = $1
						end

						ProxyBag.add_frontend_client(self,@data,data)
					else
						@data.unshift data
					end


					# Note the \0 below.  intern() blows up when passed a \0.  People who are trying to break a server like to pass \0s.  This should cope with that.
#					if data =~ /^Host:\s*([^\r\0:]+)/
#						# Still wondering whether it is worth it to use intern here.
#						@name = $1.intern
#						@name = ProxyBag.default_name unless ProxyBag.incoming_mapping(@name)
#					elsif data =~ /\r\n\r\n/
#						@name = ProxyBag.default_name
#					end
#					unless @uri
#						data =~ /^(\w+)\s+([^\s\?]+).*(1.\d)/
#						@uri = $2
#						@http_version = $3
#						@request_method = $1
#						@uri = @uri.to_s.tr('+', ' ').gsub(/((?:%[0-9a-fA-F]{2})+)/n) {[$1.delete('%')].pack('H*')} if @uri =~ /%/
#					end
#					ProxyBag.add_frontend_client(self,@data,data)

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

			def uri; @uri; end
			def request_method; @request_method; end
			def http_version; @http_version; end
			def none_match; @none_match; end

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
				@permit_xsendfile = self.class.xsendfile
				@enable_sendfile_404 = self.class.enable_sendfile_404
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
				@headers_completed = @dont_send_data = false
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
					# preamble = data.slice!(0..24)
					preamble = data[0..24]
					data = data[25..-1] || C_empty
					keylen = preamble[23..24].to_i(16)
					keylen = 0 if keylen < 0
					key = keylen > 0 ? data.slice!(0..(keylen - 1)) : C_empty
					#if preamble[0..10] == Cswiftclient and key == ProxyBag.get_key(@name)
					if preamble.index(Cswiftclient) == 0 and key == ProxyBag.get_key(@name)
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
						#@headers << h << Crnrn
						@headers << h
						if @headers =~ /Content-[Ll]ength:\s*([^\r]+)/
							@content_length = $1.to_i
						elsif @headers =~ /Transfer-encoding:\s*chunked/
							@content_length = nil
						else
							@content_length = 0
						end

						if @permit_xsendfile && @headers =~ /X-[Ss]endfile:\s*([^\r]+)/
							@associate.uri = $1
							if ProxyBag.serve_static_file(@associate,ProxyBag.get_sendfileroot(@associate.name))
								@dont_send_data = true
							else
								if @enable_sendfile_404
									msg = "#{@associate.uri} could not be found."
									@associate.send_data "HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\nContent-Type: text/html\r\nContent-Length: #{msg.length}\r\n\r\n#{msg}"
									@associate.close_connection_after_writing
									@dont_send_data = true
								else
									#@associate.send_data @headers
									#@associate.send_data Crnrn
									@associate.send_data @headers + Crnrn
								end
							end
						else
							#@associate.send_data @headers
							#@associate.send_data Crnrn
							@associate.send_data @headers + Crnrn
						end
					else
						@headers << data
					end
				end

				if @headers_completed
					@associate.send_data data unless @dont_send_data
					@content_sent += data.length
					if @content_length and @content_sent >= @content_length or data[-6..-1] == C0rnrn
						# If @dont_send_data is set, then the connection is going to be closed elsewhere.
						@associate.close_connection_after_writing unless @dont_send_data
						@associate = @headers_completed = @dont_send_data = nil
						@headers = ''
						#@headers_completed = false
						#@content_length = nil
						@content_sent = 0
						#setup
						ProxyBag.add_server self
					end
				end
			# TODO: Log these errors!
			rescue Exception => e
				puts "Kaboom: #{e} -- #{e.backtrace.inspect}"
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
			
			def self.xsendfile=(val)
				@xsendfile = val
			end
			
			def self.xsendfile
				@xsendfile
			end
			
			def self.enable_sendfile_404=(val)
				@enable_sendfile_404 = val
			end
			
			def self.enable_sendfile_404
				@enable_sendfile_404
			end
		end

		# Start the EventMachine event loop and create the front end and backend
		# handlers, then create the timers that are used to expire unserviced
		# clients and to update the Proxy's clock.

		def self.run(config)
			@existing_backends = {}
			
			# Default is to assume we want to try to turn epoll/kqueue support on.  EM
			# ignores this on platforms that don't support it, so this is safe.
			EventMachine.epoll unless config.has_key?(Cepoll) and !config[Cepoll] rescue nil
			EventMachine.kqueue unless config.has_key?(Ckqueue) and !config[Ckqueue] rescue nil
			EventMachine.set_descriptor_table_size(config[Cepoll_descriptors] || config[Cdescriptors] || 4096) rescue nil
			
			EventMachine.run do
				trap("HUP") {em_config(Swiftcore::SwiftiplyExec.parse_options); GC.start}
				trap("INT") {EventMachine.stop_event_loop}
				GC.start
				em_config(config)
				GC.start
				#RubyProf.start
			end
			#result = RubyProf.stop

			#printer = RubyProf::TextPrinter.new(result)
			#File.open('/tmp/swprof','w+') {|fh| printer = printer.print(fh,0)}
		end
		
		def self.em_config(config)
			new_config = {Ccluster_address => [],Ccluster_port => [],Ccluster_server => {}}
			
			log_level = 0
			# Deal with the logger first.
			if lgcfg = config['logger']
				type = lgcfg['type'] || 'Analogger'
				begin
					load_attempted ||= false
					require "swiftcore/Swiftiply/loggers/#{type}"
				rescue LoadError
					if load_attempted
						raise SwiftiplyLoggerNotFound.new("The logger that was specified, #{type}, could not be found.")
					else
						load_attempted = true
						require 'rubygems'
						retry
					end
				end
				log_level = determine_log_level(lgcfg['level'])
				begin
					log_class = get_const_from_name(type,::Swiftcore::Swiftiply::Loggers)
					
					ProxyBag.logger = log_class.new(lgcfg)
					ProxyBag.log_level = log_level
					ProxyBag.logger.log('info',"Logger type #{type} started.") if log_level > 0
				rescue NameError
					raise SwiftiplyLoggerNameError.new("The logger class specified, Swiftcore::Swiftiply::Loggers::#{type} was not defined.")
				end
				
			end
			
			ssl_addresses = {}
			# Determine which address/port combos should be running SSL.
			(config[Cssl] || []).each do |sa|
				if sa.has_key?(Cat)
					ssl_addresses[sa[Cat]] = {Ccertfile => sa[Ccertfile], Ckeyfile => sa[Ckeyfile]}
				end
			end
			 
			addresses = (Array === config[Ccluster_address]) ? config[Ccluster_address] : [config[Ccluster_address]]
			ports = (Array === config[Ccluster_port]) ? config[Ccluster_port] : [config[Ccluster_port]]
			addrports = []
			addresses.each do |address|
				ports.each do |port|
					addrport = "#{address}:#{port}"
					addrports << addrport
					
					#if RunningConfig[Ccluster_address] != config[Ccluster_address] or RunningConfig[Ccluster_port] != config[Ccluster_port]
					#if !RunningConfig[Ccluster_address].include?(address) or !RunningConfig[Ccluster_port].include?(port)
					if (!RunningConfig.has_key?(Ccluster_address)) ||
						(RunningConfig.has_key?(Ccluster_address) && !RunningConfig[Ccluster_address].include?(address)) ||
						(RunningConfig.has_key?(Ccluster_port) && !RunningConfig[Ccluster_port].include?(port))
						begin
							# If this particular address/port runs SSL, check that the certificate and the
							# key files exist and are readable, then create a special protocol class
							# that embeds the certificate and key information.

							if ssl_addresses.has_key?(addrport)
								# TODO: LOG that the certfiles are missing instead of silently ignoring it.
								next unless exists_and_is_readable(ssl_addresses[addrport][Ccertfile])
								next unless exists_and_is_readable(ssl_addresses[addrport][Ckeyfile])

								# Create a customized protocol object for each different address/port combination.
								ssl_protocol = Class.new(ClusterProtocol)
								ssl_protocol.class_eval <<EOC
def post_init
	start_tls({:cert_chain_file => "#{ssl_addresses[addrport][Ccertfile]}", :private_key_file => "#{ssl_addresses[addrport][Ckeyfile]}"})
end
EOC
									ProxyBag.logger.log('info',"Opening SSL server on #{address}:#{port}") if log_level > 0 and log_level < 3
									ProxyBag.logger.log('info',"Opening SSL server on #{address}:#{port} using key at #{ssl_addresses[addrport][Ckeyfile]} and certificate at #{ssl_addresses[addrport][Ccertfile]}")
									new_config[Ccluster_server][addrport] = EventMachine.start_server(
									address,
									port,
									ssl_protocol)
							else
								ProxyBag.logger.log('info',"Opening server on #{address}:#{port}") if ProxyBag.log_level > 0
								new_config[Ccluster_server][addrport] = EventMachine.start_server(
									address,
									port,
									ClusterProtocol)
							end
						rescue RuntimeError => e
							advice = ''
							if config[port] < 1024
								advice << 'Make sure you have the correct permissions to use that port, and make sure there is nothing else running on that port.'
							else
								advice << 'Make sure there is nothing else running on that port.'
							end
							advice << "  The original error was:  #{e}\n"
							msg = "The listener on #{address}:#{port} could not be started.\n#{advice}"
							ProxyBag.logger.log('fatal',msg)
							raise EMStartServerError.new(msg)
						end
						
						new_config[Ccluster_address] << address
						new_config[Ccluster_port] << port unless new_config[Ccluster_port].include?(port)
					end
				end
			end
		    
			# Stop anything that is no longer in the config.
			if RunningConfig.has_key?(Ccluster_server)
				(RunningConfig[Ccluster_server].keys - addrports).each do |s|
					ProxyBag.logger.log('info',"Stopping unused server #{s.inspect} out of #{RunningConfig[Ccluster_server].keys.inspect - RunningConfig[Ccluster_server].keys.inspect}")
					EventMachine.stop_server(s)
				end
			end
			
			new_config[Coutgoing] = {}

			config[Cmap].each do |m|
				if m[Ckeepalive]
					# keepalive requests are standard Swiftiply requests.
					
					# The hash of the "outgoing" config section.  It is used to
					# uniquely identify a section.
					hash = Digest::SHA256.hexdigest(m[Cincoming].sort.join('|')).intern
					
					# TODO: Should make a pure ruby variation that just uses a hash.
					sz = 100
					vw = 900
					ts = 0.01
					if m.has_key?(Cfile_cache)
						sz = m[Cfile_cache][Csize] || 100
						sz = 100 if sz < 0
						vw = m[Cfile_cache][Cwindow] || 900
						vw = 900 if vw < 0
						ts = m[Cfile_cache][Ctimeslice] || 0.01
						ts = 0.01 if ts < 0
					end
					ProxyBag.logger.log('debug',"Creating File Cache; size=#{sz}, window=#{vw}, timeslice=#{ts}") if ProxyBag.log_level > 2
					file_cache = Swiftcore::Swiftiply::FileCache.new(vw,ts,sz)
					unless RunningConfig[:initialized]
						EventMachine.add_timer(vw/2) {ProxyBag.verify_cache(file_cache)}
					end

					sz = 100
					vw = 900
					ts = 0.01
					if m.has_key?(Cdynamic_request_cache)
						sz = m[Cdynamic_request_cache][Csize] || 100
						sz = 100 if sz < 0
						vw = m[Cdynamic_request_cache][Cwindow] || 900
						vw = 900 if vw < 0
						ts = m[Cdynamic_request_cache][Ctimeslice] || 0.01
						ts = 0.01 if ts < 0
					end
					ProxyBag.logger.log('debug',"Creating Dynamic Request Cache; size=#{sz}, window=#{vw}, timeslice=#{ts}") if ProxyBag.log_level > 2
					dynamic_request_cache = Swiftcore::Swiftiply::DynamicRequestCache.new(m[Cdocroot],vw,ts,sz)
					unless RunningConfig[:initialized]
						EventMachine.add_timer(vw/2) {ProxyBag.verify_cache(dynamic_request_cache)}
					end

					sz = 100
					vw = 900
					ts = 0.01
					if m.has_key?(Cetag_cache)
						sz = m[Cetag_cache][Csize] || 100
						sz = 100 if sz < 0
						vw = m[Cetag_cache][Cwindow] || 900
						vw = 900 if vw < 0
						ts = m[Cetag_cache][Ctimeslice] || 0.01
						ts = 0.01 if ts < 0
					end
					ProxyBag.logger.log('debug',"Creating ETag Cache; size=#{sz}, window=#{vw}, timeslice=#{ts}") if ProxyBag.log_level > 2
					etag_cache = Swiftcore::Swiftiply::EtagCache.new(vw,ts,sz)
					unless RunningConfig[:initialized]
						EventMachine.add_timer(vw/2) {ProxyBag.verify_cache(etag_cache)}
					end

					# For each incoming entry, do setup.
					
					new_config[Cincoming] = {}
					m[Cincoming].each do |p_|
						ProxyBag.logger.log('info',"Configuring incoming #{p}") if log_level > 1
						p = p_.intern
						new_config[Cincoming][p] = {}
						ProxyBag.add_incoming_mapping(hash,p)
						ProxyBag.add_file_cache(file_cache,p)
						ProxyBag.add_dynamic_request_cache(dynamic_request_cache,p)
						ProxyBag.add_etag_cache(etag_cache,p)
						
						if m.has_key?(Cdocroot)
							ProxyBag.add_incoming_docroot(m[Cdocroot],p)
						else
							ProxyBag.remove_incoming_docroot(p)
						end
						
						if m.has_key?(Csendfileroot)
							ProxyBag.add_incoming_sendfileroot(m[Csendfileroot],p)
							permit_xsendfile = true
						else
							ProxyBag.remove_incoming_sendfileroot(p)
							permit_xsendfile = false
						end
						
						#m.has_key?(Csendfileroot) ? ProxyBag.add_incoming_sendfileroot(m[Csendfileroot],p) : ProxyBag.remove_incoming_sendfileroot(p)
						
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
							ProxyBag.logger.log('info',"  Configuring outgoing #{o}") if log_level > 2
							ProxyBag.default_name = p if m[Cdefault]
							if @existing_backends.has_key?(o)
								new_config[Coutgoing][o] ||= RunningConfig[Coutgoing][o]
								next
							else
								@existing_backends[o] = true
								backend_class = Class.new(BackendProtocol)
								backend_class.bname = hash
								backend_class.xsendfile = permit_xsendfile
								backend_class.enable_sendfile_404 = true if m[Cenable_sendfile_404]
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
		
		def self.exists_and_is_readable(file)
			FileTest.exist?(file) and FileTest.readable?(file)
		end
		
		# There are 4 levels of logging supported.
		#   :disabled means no logging
		#   :minimal logs only 
		def self.determine_log_level(lvl)
			case lvl.to_s
			when /^d|0/
				0
			when /^m|1/
				1
			when /^n|2/
				2
			when /^f|3/
				3
			else
				1
			end
		end
		
		def self.get_const_from_name(name,space)
			r = nil
			space.constants.each do |c|
				if c =~ /#{name}/i
					r = c
					break
				end
			end
			"#{space.name}::#{r}".split('::').inject(Object) { |o,n| o.const_get n }
		end
		
	end
end

