require 'swiftcore/Swiftiply/config'
# Standard style proxy.
module Swiftcore
	module Swiftiply
		module Proxies
			class Traditional < EventMachine::Connection
				Directories = {
					'static' => ['swiftcore/Swiftiply/proxy_backends/traditional/static_directory.rb','::Swiftcore::Swiftiply::Proxies::TraditionalStaticDirectory'],
					'redis' => ['swiftcore/Swiftiply/proxy_backends/traditional/redis_directory.rb','::Swiftcore::Swiftiply::Proxies::TraditionalRedisDirectory']
					}

				def self.is_a_server?
					false
				end

				def self.parse_connection_params(config, directory)
					{}
				end

				#
				# directory: DIRECTORY_TYPE [static]
				#
				def self.config(conf, new_config)
					directory = nil
					if conf[Cdirectory]
						require Directories[conf[Cdirectory]].first
						directory = Directories[conf[Cdirectory]].last
					end
					unless directory && !directory.empty?
						require Directories['static'].first
						directory = Directories['static'].last
					end

					directory_class = Swiftcore::Swiftiply::class_by_name(directory)

					owners = conf[Cincoming].sort.join('|')
					hash = Digest::SHA256.hexdigest(owners).intern
					config_data = {:hash => hash, :owners => owners}

					Config.configure_logging(conf, config_data)
					file_cache = Config.configure_file_cache(conf, config_data)
					dynamic_request_cache = Config.configure_dynamic_request_cache(conf, config_data)
					etag_cache = Config.configure_etag_cache(conf, config_data)

					# For each incoming entry, do setup.
					new_config[Cincoming] = {}
					conf[Cincoming].each do |p_|
						ProxyBag.logger.log(Cinfo,"Configuring incoming #{p_}") if Swiftcore::Swiftiply::log_level > 1
						p = p_.intern

						Config.setup_caches(new_config, config_data.merge({:p => p, :file_cache => file_cache, :dynamic_request_cache => dynamic_request_cache, :etag_cache => etag_cache}))

						ProxyBag.add_backup_mapping(conf[Cbackup].intern,p) if conf.has_key?(Cbackup)
						Config.configure_docroot(conf, p)
						config_data[:permit_xsendfile] = Config.configure_sendfileroot(conf, p)
						Config.configure_xforwardedfor(conf, p)
						Config.configure_redeployable(conf, p)
						Config.configure_key(conf, p, config_data)
						Config.configure_staticmask(conf, p)
						Config.configure_cache_extensions(conf,p)
						Config.configure_cluster_manager(conf,p)
						Config.configure_backends('groups', {
																			 :config => conf,
																			 :p => p,
																			 :config_data => config_data,
																			 :new_config => new_config,
																			 :self => self,
																			 :directory_class => directory_class,
																			 :directory_args => [conf]})
						Config.stop_unused_servers(new_config)
#            directory_class.config(conf, new_config)
#            Config.set_server_queue(config_data, directory_class, [conf])
					end
				end

				# Here lies the protocol definition.  A traditional proxy is super simple -- pass on what you get.
				attr_accessor :associate, :id

				C0rnrn = "0\r\n\r\n".freeze
				Crnrn = "\r\n\r\n".freeze

				def initialize(host=nil, port=nil)
					@name = self.class.bname
					@caching_enabled = self.class.caching
					@permit_xsendfile = self.class.xsendfile
					@enable_sendfile_404 = self.class.enable_sendfile_404
					@host = host
					@port = port
					super
				end

				def name
					@name
				end

				# Call setup() and add the backend to the ProxyBag queue.

				def post_init
					setup
				end

				# Setup the initial variables for receiving headers and content.

				def setup
					@headers = ''
					@headers_completed = @dont_send_data = false
					@content_sent = 0
					@filter = self.class.filter
				end

				# Receive data from the backend process.  Headers are parsed from
				# the rest of the content.  If a Content-Length header is present,
				# that is used to determine how much data to expect.  Otherwise,
				# if 'Transfer-encoding: chunked' is present, assume chunked
				# encoding.  Otherwise just read until the connection is closed.
				# SO MUCH functionality has to be duplicated and maintained between
				# here and the keepalive protocol. That funcationality need to be
				# refactored so that it's encapsulated better.

				def receive_data data
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
							elsif @headers =~ /Transfer-encoding: *chunked/
								@content_length = nil
							else
								@content_length = nil
							end

							if @caching_enabled && @associate && @associate.request_method == CGET && @headers =~ /Etag:/ && @headers !~ /Cache-Control: *no-/ # stupid granularity -- it's on or off, only
								@do_caching = true
								@cacheable_data = ''
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
						@cacheable_data << data if @do_caching
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
							self.close_connection_after_writing
							# add(path_info,path,data,etag,mtime,header)

							if @do_caching && associate_name = @associate.name
								ProxyBag.file_cache_map[associate_name].add(@associate.unparsed_uri,
																														'',
																														@cacheable_data,
																														'',
																														0,
																														@headers.scan(/^Set-Cookie:.*/).collect {|c| c =~ /: (.*)$/; $1},
																														@headers)
								ProxyBag.dynamic_request_cache[associate_name].delete(@associate.uri)
							end
						end
					end
				# TODO: Log these errors!
				rescue Exception => e
					puts "Kaboom: #{e} -- #{e.backtrace.inspect}"
					@associate.close_connection_after_writing if @associate
					@associate = nil
					self.close_connection_after_writing
				end

				# This is called when the backend disconnects from the proxy.

				def unbind
					associate_name = @associate.name
					sq = ProxyBag.server_queue(ProxyBag.incoming_mapping(associate_name))
					sq && sq.requeue(associate_name, @host, @port)
					ProxyBag.check_for_queued_requests(@name)
					if @associate
						if !@associate.redeployable or @content_sent
							@associate.close_connection_after_writing
						else
							@associate.associate = nil
							@associate.setup_for_redeployment
							ProxyBag.rebind_frontend_client(@associate)
						end
					else
#  					ProxyBag.remove_server(self)
					end
#  				ProxyBag.remove_id(self)
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

				def self.caching
					@caching
				end

				def self.caching=(val)
					@caching = val
				end
			end
		end
	end
end
