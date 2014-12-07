module Swiftcore
	# TODO:
	#
	# 1) Basic HTTP Authentication
	# 2) Stats
	#   Stats will be recorded in aggregate and for each incoming section, and may
	#   accessed through a separate stats port via a RESTful HTTP request which
	#   identifies the section to pull stats for, and the authentication key for
	#   access to those stats.
	#   http://127.0.0.1:8082
	#
	# To track:
	#   Total connections
	#   400s served
	#   404s served
	#
	#   Per config section:
	#     backends connected
	#     backends busy
	#     backend disconnects
	#     backend errors
	#     static bytes served
	#     static requests handled
	#     static requests 304'd
	#     cache hits for static files
	#     dynamic bytes returned
	#     dynamic requests handled
	#     
	#   
	#
	# 3) Maintenance Page Support
	#   This is a path to a static file which will be returned on a 503 error.
	# 4) GZip compression
	#   Can be toggled on or off.  Configure mime types to compress.  Implemented
	#   via an extension.
	# 5) Make one "SwiftiplyCplusplus" and one "SwiftiplC" extension that,
	#    respectively, encapsulate all of the C++ and C extensions into just
	#    two.

	# A little statemachine for loading requirements.  The intention is to
	# only load rubygems if necessary, and to load the Deque and SplayTreeMap
	# classes if they are available, setting a constant accordingly so that
	# the fallbacks (Array and Hash) can be used if they are not.
	
	begin
		load_state ||= :start
		rubygems_loaded ||= false
		require 'socket'
		require 'digest/sha2'
		require 'eventmachine'
		require 'fastfilereaderext' # This is unneeded as of EventMachine 0.12.6, so test for EM's version before requiring ours.
		require 'swiftcore/hash'
		require 'swiftcore/types'
		require 'swiftcore/Swiftiply/mocklog'
		
		load_state = :deque
		require 'swiftcore/deque' unless const_defined?(:HasDeque)
		HasDeque = true unless const_defined?(:HasDeque)
		
		load_state = :splaytreemap
		require 'swiftcore/splaytreemap' unless const_defined?(:HasSplayTree)
		HasSplayTree = true unless const_defined?(:HasSplayTree)
		
		load_state = :helpers
		require 'swiftcore/streamer'
		require 'swiftcore/Swiftiply/etag_cache'
		require 'swiftcore/Swiftiply/file_cache'
		require 'swiftcore/Swiftiply/dynamic_request_cache'
		require 'time'

		load_state = :core
		require 'swiftcore/Swiftiply/constants'
		require 'swiftcore/Swiftiply/proxy_bag'
		require 'swiftcore/Swiftiply/cluster_protocol'
		require 'swiftcore/Swiftiply/backend_protocol'

	rescue LoadError => e
		unless rubygems_loaded
			# Everything gets slower once rubygems are used (though this
			# effect is not so profound as it once was).  So, for the
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

	GC.start

	module Swiftiply

		# Start the EventMachine event loop and create the front end and backend
		# handlers, then create the timers that are used to expire unserviced
		# clients and to update the Proxy's clock.

		def self.run(config)
			@existing_backends = {}
			
			# Default is to assume we want to try to turn epoll/kqueue support on.
			EventMachine.epoll unless config.has_key?(Cepoll) and !config[Cepoll] rescue nil
			EventMachine.kqueue unless config.has_key?(Ckqueue) and !config[Ckqueue] rescue nil
			EventMachine.set_descriptor_table_size(config[Cepoll_descriptors] || config[Cdescriptors] || 4096) rescue nil
			
			EventMachine.run do
				EM.set_timer_quantum(5)
				trap("HUP") { EM.add_timer(0) {em_config(Swiftcore::SwiftiplyExec.parse_options); GC.start} }
				trap("INT") { EventMachine.stop_event_loop }
				GC.start
				em_config(config)
				GC.start # We just want to make sure all the junk created during
				         # configuration is purged prior to real work starting.
				#RubyProf.start
			end
			#result = RubyProf.stop

			#printer = RubyProf::TextPrinter.new(result)
			#File.open('/tmp/swprof','w+') {|fh| printer = printer.print(fh,0)}
		end
		
		# TODO: This method is crazy long, and should be refactored.
		def self.em_config(config)
			new_config = {Ccluster_address => [],Ccluster_port => [],Ccluster_server => {}}
			defaults = config['defaults'] || {}

			new_log = _config_loggers(config,defaults)
			log_level = ProxyBag.log_level
			ssl_addresses = _config_determine_ssl_addresses(config)

			addresses = (Array === config[Ccluster_address]) ? config[Ccluster_address] : [config[Ccluster_address]]
			ports = (Array === config[Ccluster_port]) ? config[Ccluster_port] : [config[Ccluster_port]]
			addrports = []

			addresses.each do |address|
				ports.each do |port|
					addrport = "#{address}:#{port}"
					addrports << addrport
					
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
									ProxyBag.logger.log(Cinfo,"Opening SSL server on #{address}:#{port}") if log_level > 0 and log_level < 3
									ProxyBag.logger.log(Cinfo,"Opening SSL server on #{address}:#{port} using key at #{ssl_addresses[addrport][Ckeyfile]} and certificate at #{ssl_addresses[addrport][Ccertfile]}")
									new_config[Ccluster_server][addrport] = EventMachine.start_server(
									address,
									port,
									ssl_protocol)
							else
								standard_protocol = Class.new(ClusterProtocol)
								standard_protocol.init_class_variables
								ProxyBag.logger.log(Cinfo,"Opening server on #{address}:#{port}") if ProxyBag.log_level > 0
								new_config[Ccluster_server][addrport] = EventMachine.start_server(
									address,
									port,
									standard_protocol)
							end
						rescue RuntimeError => e
							advice = ''
							if port < 1024
								advice << 'Make sure you have the correct permissions to use that port, and make sure there is nothing else running on that port.'
							else
								advice << 'Make sure there is nothing else running on that port.'
							end
							advice << "  The original error was:  #{e}\n"
							msg = "The listener on #{address}:#{port} could not be started.\n#{advice}\n"
							ProxyBag.logger.log('fatal',msg)
							raise EMStartServerError.new(msg)
						end
						
						new_config[Ccluster_address] << address
						new_config[Ccluster_port] << port unless new_config[Ccluster_port].include?(port)
					else
						new_config[Ccluster_server][addrport] = RunningConfig[Ccluster_server][addrport]
						new_config[Ccluster_address] << address
						new_config[Ccluster_port] << port unless new_config[Ccluster_port].include?(port)
					end
				end
			end
		    
			# Stop anything that is no longer in the config.
			if RunningConfig.has_key?(Ccluster_server)
				(RunningConfig[Ccluster_server].keys - addrports).each do |s|
					ProxyBag.logger.log(Cinfo,"Stopping unused incoming server #{s.inspect} out of #{RunningConfig[Ccluster_server].keys.inspect - RunningConfig[Ccluster_server].keys.inspect}")
					EventMachine.stop_server(s)
				end
			end
			
			new_config[Coutgoing] = {}

			config[Cmap].each do |mm|
				m = defaults.dup
				m.rmerge!(mm)
				
				if m[Ckeepalive]
					# keepalive requests are standard Swiftiply requests.
					
					# The hash of the "outgoing" config section.  It is used to
					# uniquely identify a section.
					owners = m[Cincoming].sort.join('|')
					hash = Digest::SHA256.hexdigest(owners).intern
					
					ProxyBag.remove_log(hash)
												
					if m['logger'] and (!ProxyBag.log(hash) or MockLog === ProxyBag.log(hash))
						new_log = handle_logger_config(m['logger'])

						ProxyBag.add_log(new_log[:logger],hash)
						ProxyBag.set_level(new_log[:log_level],hash)
					end

					# The File Cache defaults to a max size of 100 elements, with a refresh
					# window of five minues, and a time slice of a hundredth of a second.
					sz = 100
					vw = 300
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
					file_cache.owners = owners
					file_cache.owner_hash = hash
					EventMachine.add_timer(vw/2) {ProxyBag.verify_cache(file_cache)} unless RunningConfig[:initialized]

					# The Dynamic Request Cache defaults to a max size of 100, with a 15 minute
					# refresh window, and a time slice of a hundredth of a second.
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
					dynamic_request_cache.owners = owners
					dynamic_request_cache.owner_hash = hash
					EventMachine.add_timer(vw/2) {ProxyBag.verify_cache(dynamic_request_cache)} unless RunningConfig[:initialized]

					# The ETag Cache defaults to a max size of 10000 (it doesn't take a lot
					# of RAM to hold an etag), with a 5 minute refresh window and a time
					# slice of a hundredth of a second.
					sz = 10000
					vw = 300
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
					etag_cache.owners = owners
					etag_cache.owner_hash = hash
					EventMachine.add_timer(vw/2) {ProxyBag.verify_cache(etag_cache)} unless RunningConfig[:initialized]

					# For each incoming entry, do setup.
					
					new_config[Cincoming] = {}
					m[Cincoming].each do |p_|
						ProxyBag.logger.log(Cinfo,"Configuring incoming #{p_}") if log_level > 1
						p = p_.intern
						
						# The dynamic request cache may need to know a valid client name.
						dynamic_request_cache.one_client_name ||= p
						
						new_config[Cincoming][p] = {}
						ProxyBag.add_incoming_mapping(hash,p)
						ProxyBag.add_file_cache(file_cache,p)
						ProxyBag.add_dynamic_request_cache(dynamic_request_cache,p)
						ProxyBag.add_etag_cache(etag_cache,p)
						
						if m.has_key?(Cdocroot)
							ProxyBag.add_docroot(m[Cdocroot],p)
						else
							ProxyBag.remove_docroot(p)
						end
						
						if m.has_key?(Csendfileroot)
							ProxyBag.add_sendfileroot(m[Csendfileroot],p)
							permit_xsendfile = true
						else
							ProxyBag.remove_sendfileroot(p)
							permit_xsendfile = false
						end
						
						if m[Cxforwardedfor]
							ProxyBag.set_x_forwarded_for(p)
						else
							ProxyBag.unset_x_forwarded_for(p)
						end
						
						if m[Credeployable]
							ProxyBag.add_redeployable(m[Credeployment_sizelimit] || 16384,p)
						else
							ProxyBag.remove_redeployable(p)
						end
						
						if m.has_key?(Ckey)
							ProxyBag.set_key(hash,m[Ckey])
						else
							ProxyBag.set_key(hash,C_empty)
						end
						
						if m.has_key?(Cstaticmask)
							ProxyBag.add_static_mask(Regexp.new(m[Cstaticmask]),p)
						else
							ProxyBag.remove_static_mask(p)
						end
						
						if m.has_key?(Ccache_extensions) or m.has_key?(Ccache_directory)
							require 'swiftcore/Swiftiply/support_pagecache'
							ProxyBag.add_suffix_list((m[Ccache_extensions] || ProxyBag.const_get(:DefaultSuffixes)),p)
							ProxyBag.add_cache_dir((m[Ccache_directory] || ProxyBag.const_get(:DefaultCacheDir)),p)
						else
							ProxyBag.remove_suffix_list(p) if ProxyBag.respond_to?(:remove_suffix_list)
							ProxyBag.remove_cache_dir(p) if ProxyBag.respond_to?(:remove_cache_dir)
						end
							
						# Go through the outgoing sections, creating an EM server
						# for each one.
						
						# First, make sure the filters are clear.
						ProxyBag.remove_filters(p)
						
						m[Coutgoing].each do |o|
							#
							# outgoing: 127.0.0.1:12340
							# outgoing:
							#   to: 127.0.0.1:12340
							#
							# outgoing:
							#   match: php$
							#   to: 127.0.0.1:12342
							#
							# outgoing:
							#   prefix: /blah
							#   to: 127.0.0.1:12345
							#
							#####
							#
							# If the outgoing is a simple host:port, then all
							# requests go striaght to a backend connected to
							# that socket location.
							#
							# If the outgoing is a hash, and the hash only has
							# a 'to' key, then the behavior is the same as if
							# it were a simple host:port.
							#
							# If the outgoing hash has a 'to' and a 'match',
							# then the incoming request's uri will be compared
							# to the regular expression contained in the
							# 'match' parameter.
							#
							# If the outgoing hash has a 'to' and a 'prefix',
							# then the incoming request's uri will be compared
							# with the prefix using a trie classifier.
							#   THE PREFIX OPTION IS NOT FULLY IMPLEMENTED!!!

							if Hash === o
								out = [o['to'],o['match'],o['prefix']].compact.join('::')
								host, port = o['to'].split(/:/,2)
								filter = Regexp.new(o['match'])
							else
								out = o
								host, port = out.split(/:/,2)
								filter = nil
							end
							
							ProxyBag.logger.log(Cinfo,"  Configuring outgoing #{out}") if log_level > 2
							ProxyBag.default_name = p if m[Cdefault]
							
							if @existing_backends.has_key?(out)
								ProxyBag.logger.log(Cinfo,'    Already running; skipping') if log_level > 2
								new_config[Coutgoing][out] ||= RunningConfig[Coutgoing][out]
								next
							else
								# TODO:  Add ability to create filters for outgoing destinations, so one can send different path patterns to different outgoing hosts/ports.
								@existing_backends[out] = true
								backend_class = Class.new(BackendProtocol)
								backend_class.bname = hash
								ProxyBag.logger.log(Cinfo,"    Permit X-Sendfile") if permit_xsendfile and log_level > 2
								backend_class.xsendfile = permit_xsendfile
								ProxyBag.logger.log(Cinfo,"    Enable 404 on missing Sendfile resource") if m[Cenable_sendfile_404] and log_level > 2
								backend_class.enable_sendfile_404 = true if m[Cenable_sendfile_404]								
								backend_class.filter = !filter.nil?
								ProxyBag.add_filter(filter,hash)

								begin
									new_config[Coutgoing][out] = EventMachine.start_server(host, port.to_i, backend_class)
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
			
			# By default any file over 16k will be sent via chunked encoding
			# if the client supports HTTP 1.1.  Generally there is no reason
			# to change this, but it is configurable.
			
			ProxyBag.chunked_encoding_threshold = config[Cchunked_encoding_threshold] || 16384
			
			# The default cache_threshold is set to 100k.  Files above this size
			# will not be cached.  Customize this value in your configurations
			# as necessary for the best performance on your site.
			
			ProxyBag.cache_threshold = config['cache_threshold'] || 102400
			
			unless RunningConfig[:initialized]
				EventMachine.add_periodic_timer(2) { ProxyBag.expire_clients }
				EventMachine.add_periodic_timer(1) { ProxyBag.update_ctime }
				new_config[:initialized] = true
			end
			
			RunningConfig.replace new_config
		end
		
		def self._config_loggers(config,defaults)
			if defaults['logger']
				if config['logger']
					config['logger'].rmerge!(defaults['logger'])
				else
					config['logger'] = {}.rmerge!(defaults['logger'])
				end
			else
				config['logger'] = {'log_level' => 0, 'type' => 'stderror'} unless config['logger']
			end
			
			new_log = handle_logger_config(config['logger']) if config['logger']
			ProxyBag.logger = new_log[:logger] if new_log
			ProxyBag.log_level = new_log[:log_level] if new_log
			new_log
		end
		
		def self._config_determine_ssl_addresses(config)
			ssl_addresses = {}
			# Determine which address/port combos should be running SSL.
			(config[Cssl] || []).each do |sa|
				if sa.has_key?(Cat)
					ssl_addresses[sa[Cat]] = {Ccertfile => sa[Ccertfile], Ckeyfile => sa[Ckeyfile]}
				end
			end
			ssl_addresses
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
		#   :disabled or 0 means no logging
		#   :minimal or 1 logs only essential items
		#   :normal or 2 logs everything useful/interesting
		#   :full or 3 logs all major events
		#
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
		
		def self.handle_logger_config(lgcfg = nil,handle_default = true)
			new_logger = {}
			if lgcfg
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
				new_logger[:log_level] = determine_log_level(lgcfg['level'] || lgcfg['log_level'])
				begin
					log_class = get_const_from_name(type,::Swiftcore::Swiftiply::Loggers)
			
					new_logger[:logger] = log_class.new(lgcfg)
					new_logger[:logger].log(Cinfo,"Logger type #{type} started; log level is #{new_logger[:log_level]}.") if new_logger[:log_level] > 0
				rescue NameError
					raise SwiftiplyLoggerNameError.new("The logger class specified, Swiftcore::Swiftiply::Loggers::#{type} was not defined.")
				end
			elsif handle_default
				# Default to the stderror logger with a log level of 0
				begin
					load_attempted ||= false
					require "swiftcore/Swiftiply/loggers/stderror"
				rescue LoadError
					if load_attempted
						raise SwiftiplyLoggerNotFound.new("The attempt to load the default logger (swiftcore/Swiftiply/loggers/stderror.rb) failed.  This should not happen.  Please double check your Swiftiply installation.")
					else
						load_attempted = true
						require 'rubygems'
						retry
					end
				end

				log_class = get_const_from_name('stderror',::Swiftcore::Swiftiply::Loggers)
				new_logger[:logger] = log_class.new(lgcfg)
				new_logger[:log_level] = log_level
			else
				new_logger = nil
			end
			
			new_logger
		end
		
	end
end

