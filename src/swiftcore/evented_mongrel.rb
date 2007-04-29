# This module rewrites pieces of the very good Mongrel web server in
# order to change it from a threaded application to an event based
# application running inside an EventMachine event loop.  It should
# be compatible with the existing Mongrel handlers for Rails,
# Camping, Nitro, etc....
 
begin
	load_attempted ||= false
	require 'eventmachine'
rescue LoadError
	unless load_attempted
		load_attempted = true
		require 'rubygems'
		retry
	end
end

require 'mongrel'

module Mongrel
	class MongrelProtocol < EventMachine::Connection
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
					@request_len = @nparsed + @params[::Mongrel::Const::CONTENT_LENGTH].to_i
					script_name, path_info, handlers = ::Mongrel::HttpServer::Instance.classifier.resolve(@params[::Mongrel::Const::REQUEST_PATH])
					if handlers
						@params[::Mongrel::Const::PATH_INFO] = path_info
						@params[::Mongrel::Const::SCRIPT_NAME] = script_name
						@params[::Mongrel::Const::REMOTE_ADDR] = @params[::Mongrel::Const::HTTP_X_FORWARDED_FOR] || ::Socket.unpack_sockaddr_in(get_peername)[1]
						@notifiers = handlers.select { |h| h.request_notify }
					end
					if @request_len > ::Mongrel::Const::MAX_BODY
						new_buffer = Tempfile.new(::Mongrel::Const::MONGREL_TMP_BASE)
						new_buffer.binmode
						new_buffer << @linebuffer
						@linebuffer = new_buffer
					else
						@linebuffer = StringIO.new(@linebuffer)
					end
				end
				if @linebuffer.length >= @request_len
					::Mongrel::HttpServer::Instance.process_http_request(@params,@linebuffer,self)
				end
			elsif @linebuffer.length > ::Mongrel::Const::MAX_HEADER
				raise ::Mongrel::HttpParserError.new("HEADER is longer than allowed, aborting client early.")
			end
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
		def initialize(host, port, num_processors=(2**30-1), timeout=0)
			@socket = nil
			@classifier = URIClassifier.new
			@host = host
			@port = port
			@workers = ThreadGroup.new
			@timeout = timeout
			@num_processors = num_processors
			@death_time = 60
			self.class.const_set(:Instance,self)
		end

		def run
			@acceptor = Thread.new do
				EventMachine.run do
					begin
						EventMachine.start_server(@host,@port,MongrelProtocol)
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
				handlers.each do |handler|
					handler.process(request, response)
					break if response.done
				end

				# And finally, if nobody closed the response off, we finalize it.
				unless response.done
					response.finished
				else
					response.close_connection_after_writing
				end
			else
				# Didn't find it, return a stock 404 response.
				client.send_data(Const::ERROR_404_RESPONSE)
				client.close_connection_after_writing
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

		def close_connection_after_writing
			@socket.close_connection_after_writing
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
			@socket.close_connection_after_writing
		end
	end
end
