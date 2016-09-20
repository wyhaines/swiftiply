module Swiftcore
  module Swiftiply
    
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
				@filter = self.class.filter
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
						# The worker that connected did not present the proper authentication,
						# so something is fishy; time to cut bait.
						close_connection
						return
					end
				end
				
				unless @headers_completed 
					if data.include?(Crnrn)
						@headers_completed = true
						h,data = data.split(/\r\n\r\n/,2)
						#@headers << h << Crnrn
						if @headers.length > 0
							@headers << h
						else
							@headers = h
						end
						
						if @headers =~ /Content-[Ll]ength: *([^\r]+)/
							@content_length = $1.to_i
						elsif @headers =~ /Transfer-encoding:\s*chunked/
							@content_length = nil
						else
							@content_length = 0
						end

						if @permit_xsendfile && @headers =~ /X-[Ss]endfile: *([^\r]+)/
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
									@associate.send_data @headers + Crnrn
								end
							end
						else
							@associate.send_data @headers + Crnrn
						end
						
						# If keepalive is turned on, the assumption is that it will stay
						# on, unless the headers being returned indicate that the connection
						# should be closed.
						# So, check for a 'Connection: Closed' header.
						if keepalive = @associate.keepalive
							keepalive = false if @headers =~ /Connection: [Cc]lose/
							if @associate_http_version == C1_0
								keepalive = false unless @headers == /Connection: Keep-Alive/i
							end
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
						unless @dont_send_data
							# Check to see if keepalive is enabled.
							if keepalive
								@associate.reset_state
								ProxyBag.remove_client(self) unless @associate
							else
								@associate.close_connection_after_writing
							end
						end
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
			
			def self.filter=(val)
				@filter = val
			end
			
			def self.filter
				@filter
			end
			
			def filter
				@filter
			end
		end

  end
end
