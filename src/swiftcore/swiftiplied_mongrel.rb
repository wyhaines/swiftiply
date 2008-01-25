# This module rewrites pieces of the very good Mongrel web server in
# order to change it from a threaded application to an event based
# application running inside an EventMachine event loop.  It should
# be compatible with the existing Mongrel handlers for Rails,
# Camping, Nitro, etc....
 
begin
	load_attempted ||= false
	require 'eventmachine'
	require 'swiftcore/Swiftiply/swiftiply_client'
	require 'mongrel'
rescue LoadError
	unless load_attempted
		load_attempted = true
		require 'rubygems'
		retry
	end
end

module Mongrel
	C0s = [0,0,0,0].freeze unless const_defined?(:C0s)
	CCCCC = 'CCCC'.freeze unless const_defined?(:CCCCC)

	class MongrelProtocol < SwiftiplyClientProtocol

		def post_init
			@parser = HttpParser.new
			@params = HttpParams.new
			@nparsed = 0
			@request = nil
			@request_len = nil
			@linebuffer = ''
		end

		def receive_data data
			@linebuffer << data
			@nparsed = @parser.execute(@params, @linebuffer, @nparsed) unless @parser.finished?
			if @parser.finished?
				if @request_len.nil?
					@request_len = @params[::Mongrel::Const::CONTENT_LENGTH].to_i
					script_name, path_info, handlers = ::Mongrel::HttpServer::Instance.classifier.resolve(@params[::Mongrel::Const::REQUEST_PATH])
					if handlers
						@params[::Mongrel::Const::PATH_INFO] = path_info
						@params[::Mongrel::Const::SCRIPT_NAME] = script_name
						# The previous behavior of this line set REMOTE_ADDR equal to HTTP_X_FORWARDED_FOR
						# if it was defined.  This behavior seems inconsistent with the intention of
						# http://www.ietf.org/rfc/rfc3875 so it has been changed.  REMOTE_ADDR now always
						# contains the address of the immediate source of the connection.  Check
						# @params[::Mongrel::Const::HTTP_X_FORWARDED_FOR] if you need that information.
						@params[::Mongrel::Const::REMOTE_ADDR] = ::Socket.unpack_sockaddr_in(get_peername)[1] rescue nil
						@notifiers = handlers.select { |h| h.request_notify }
					end
					if @request_len > ::Mongrel::Const::MAX_BODY
						new_buffer = Tempfile.new(::Mongrel::Const::MONGREL_TMP_BASE)
						new_buffer.binmode
						new_buffer << @linebuffer[@nparsed..-1]
						@linebuffer = new_buffer
					else
						@linebuffer = StringIO.new(@linebuffer[@nparsed..-1])
						@linebuffer.pos = @linebuffer.length
					end
				end
				if @linebuffer.length >= @request_len
					@linebuffer.rewind
					::Mongrel::HttpServer::Instance.process_http_request(@params,@linebuffer,self)
					@linebuffer.delete if Tempfile === @linebuffer
					post_init
				end
			elsif @linebuffer.length > ::Mongrel::Const::MAX_HEADER
				close_connection
				raise ::Mongrel::HttpParserError.new("HEADER is longer than allowed, aborting client early.")
			end
		rescue ::Mongrel::HttpParserError
			if $mongrel_debug_client
				STDERR.puts "#{Time.now}: BAD CLIENT (#{params[Const::HTTP_X_FORWARDED_FOR] || client.peeraddr.last}): #$!"
				STDERR.puts "#{Time.now}: REQUEST DATA: #{data.inspect}\n---\nPARAMS: #{params.inspect}\n---\n"
			end
			close_connection
		rescue Exception => e
			close_connection
			raise e
		end

		def write data
			send_data data
		end

		def closed?
			false
		end

	end

	class HttpServer
		# There is no framework agnostic way to get that key value from the
		# configuration into here; it'll require code specific to the way the
		# different frameworks handle their configuration of Mongrel.  So....
		# The support is here, for swiftiplied_mongrels which are secured by
		# a key.  If someone want to donate any patches.  Otherwise, this won't
		# really be useful to most people until 0.7.0.
		
		def initialize(host, port, num_processors=950, x=0, y=nil,key='') # Deal with Mongrel 1.0.1 or earlier, as well as later.
			@socket = nil
			@classifier = URIClassifier.new
			@host = host
			@port = port
			@key = key
			@workers = ThreadGroup.new
			if y
				@throttle = x
				@timeout = y || 60
			else
				@timeout = x
			end
			@num_processors = num_processors
			@death_time = 60
			self.class.const_set(:Instance,self)
		end

		def run
			trap('INT') { EventMachine.stop_event_loop }
			trap('TERM') { EventMachine.stop_event_loop }
			@acceptor = Thread.new do
				EventMachine.run do
					begin
						MongrelProtocol.connect(@host,@port,@key)
					rescue StopServer
						EventMachine.stop_event_loop
					end
				end
			end
		end

		def process_http_request(params,linebuffer,client)
			if not params[Const::REQUEST_PATH]
				uri = URI.parse(params[Const::REQUEST_URI])
				params[Const::REQUEST_PATH] = uri.request_uri
			end

 			raise "No REQUEST PATH" if not params[Const::REQUEST_PATH]

			script_name, path_info, handlers = @classifier.resolve(params[Const::REQUEST_PATH])

			if handlers
				notifiers = handlers.select { |h| h.request_notify }
				request = HttpRequest.new(params, linebuffer, notifiers)

				# request is good so far, continue processing the response
				response = HttpResponse.new(client)

				# Process each handler in registered order until we run out or one finalizes the response.
				dispatch_to_handlers(handlers,request,response)

				# And finally, if nobody closed the response off, we finalize it.
				unless response.done
					response.finished
				end
			else
				# Didn't find it, return a stock 404 response.
				# This code is changed from the Mongrel behavior because a content-length
				# header MUST accompany all HTTP responses that go into a swiftiply
				# keepalive connection, so just use the Response object to construct the
				# 404 response.
				response = HttpResponse.new(client)
				response.status = 404
				response.body = "#{params[Const::REQUEST_PATH]} not found"
				response.finished
			end
		end
		
		def dispatch_to_handlers(handlers,request,response)
			handlers.each do |handler|
				handler.process(request, response)
				break if response.done
			end
		end
		
	end

	class HttpRequest
		def initialize(params, linebuffer, dispatchers)
			@params = params
			@dispatchers = dispatchers
			@body = linebuffer
		end
	end

	class HttpResponse
		def send_file(path, small_file = false)
			File.open(path, "rb") do |f|
				while chunk = f.read(Const::CHUNK_SIZE) and chunk.length > 0
					begin
						write(chunk)
					rescue Object => exc
						break
					end
				end
			end
			@body_sent = true
		end

		def write(data)
			@socket.send_data data
		end

		def socket_error(details)
			@socket.close_connection
			done = true
			raise details
		end

		def finished
			send_status
			send_header
			send_body
		end
	end
	
	class Configurator
		# This version fixes a bug in the regular Mongrel version by adding
		# initialization of groups.
		def change_privilege(user, group)
			if user and group
				log "Initializing groups for {#user}:{#group}."
				Process.initgroups(user,Etc.getgrnam(group).gid)
			end
			
			if group
				log "Changing group to #{group}."
				Process::GID.change_privilege(Etc.getgrnam(group).gid)
			end
			
			if user
				log "Changing user to #{user}."
				Process::UID.change_privilege(Etc.getpwnam(user).uid)
			end
		rescue Errno::EPERM
			log "FAILED to change user:group #{user}:#{group}: #$!"
			exit 1
		end
	end
end
