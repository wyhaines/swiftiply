module Swiftcore
  module Swiftiply
    class Config
      def self.configure_logging(config, data)
        ProxyBag.remove_log(data[:hash])
        if config['logger'] and (!ProxyBag.log(data[:hash]) or MockLog === ProxyBag.log(data[:hash]))
          new_log = ::Swiftcore::Swiftiply::handle_logger_config(config['logger'])

          ProxyBag.add_log(new_log[:logger],data[:hash])
          ProxyBag.set_level(new_log[:log_level],data[:hash])
        end
      end

      def self.configure_file_cache(config, data)
        # The File Cache defaults to a max size of 100 elements, with a refresh
        # window of five minues, and a time slice of a hundredth of a second.
        sz = 100
        vw = 300
        ts = 0.01

        if config.has_key?(Cfile_cache)
          sz = config[Cfile_cache][Csize] || 100
          sz = 100 if sz < 0
          vw = config[Cfile_cache][Cwindow] || 900
          vw = 900 if vw < 0
          ts = config[Cfile_cache][Ctimeslice] || 0.01
          ts = 0.01 if ts < 0
        end

        ProxyBag.logger.log('debug',"Creating File Cache; size=#{sz}, window=#{vw}, timeslice=#{ts}") if ProxyBag.log_level > 2
        file_cache = Swiftcore::Swiftiply::FileCache.new(vw,ts,sz)
        file_cache.owners = data[:owners]
        file_cache.owner_hash = data[:hash]
        EventMachine.add_timer(vw/2) {ProxyBag.verify_cache(file_cache)} unless RunningConfig[:initialized]
        file_cache
      end

      def self.configure_dynamic_request_cache(config, data)
        # The Dynamic Request Cache defaults to a max size of 100, with a 15 minute
        # refresh window, and a time slice of a hundredth of a second.
        sz = 100
        vw = 900
        ts = 0.01
        if config.has_key?(Cdynamic_request_cache)
          sz = config[Cdynamic_request_cache][Csize] || 100
          sz = 100 if sz < 0
          vw = config[Cdynamic_request_cache][Cwindow] || 900
          vw = 900 if vw < 0
          ts = config[Cdynamic_request_cache][Ctimeslice] || 0.01
          ts = 0.01 if ts < 0
        end
        ProxyBag.logger.log('debug',"Creating Dynamic Request Cache; size=#{sz}, window=#{vw}, timeslice=#{ts}") if ProxyBag.log_level > 2
        dynamic_request_cache = Swiftcore::Swiftiply::DynamicRequestCache.new(config[Cdocroot],vw,ts,sz)
        dynamic_request_cache.owners = data[:owners]
        dynamic_request_cache.owner_hash = data[:hash]
        EventMachine.add_timer(vw/2) {ProxyBag.verify_cache(dynamic_request_cache)} unless Swiftcore::Swiftiply::RunningConfig[:initialized]
        dynamic_request_cache
      end

      def self.configure_etag_cache(config, data)
        # The ETag Cache defaults to a max size of 10000 (it doesn't take a lot
        # of RAM to hold an etag), with a 5 minute refresh window and a time
        # slice of a hundredth of a second.
        sz = 10000
        vw = 300
        ts = 0.01
        if config.has_key?(Cetag_cache)
          sz = config[Cetag_cache][Csize] || 100
          sz = 100 if sz < 0
          vw = config[Cetag_cache][Cwindow] || 900
          vw = 900 if vw < 0
          ts = config[Cetag_cache][Ctimeslice] || 0.01
          ts = 0.01 if ts < 0
        end
        ProxyBag.logger.log('debug',"Creating ETag Cache; size=#{sz}, window=#{vw}, timeslice=#{ts}") if ProxyBag.log_level > 2
        etag_cache = Swiftcore::Swiftiply::EtagCache.new(vw,ts,sz)
        etag_cache.owners = data[:owners]
        etag_cache.owner_hash = data[:hash]
        EventMachine.add_timer(vw/2) {ProxyBag.verify_cache(etag_cache)} unless Swiftcore::Swiftiply::RunningConfig[:initialized]
        etag_cache
      end

      def self.setup_caches(new_config,data)
        # The dynamic request cache may need to know a valid client name.
        data[:dynamic_request_cache].one_client_name ||= data[:p]

        new_config[Cincoming][data[:p]] = {}
        ProxyBag.add_incoming_mapping(data[:hash],data[:p])
        ProxyBag.add_file_cache(data[:file_cache],data[:p])
        ProxyBag.add_dynamic_request_cache(data[:dynamic_request_cache],data[:p])
        ProxyBag.add_etag_cache(data[:etag_cache],data[:p])
      end

      def self.configure_docroot(config, p)
        if config.has_key?(Cdocroot)
          ProxyBag.add_docroot(config[Cdocroot],p)
        else
          ProxyBag.remove_docroot(p)
        end
      end

      def self.configure_sendfileroot(config, p)
        if config.has_key?(Csendfileroot)
          ProxyBag.add_sendfileroot(config[Csendfileroot],p)
          true
        else
          ProxyBag.remove_sendfileroot(p)
          false
        end
      end

      def self.configure_xforwardedfor(config, p)
        if config[Cxforwardedfor]
          ProxyBag.set_x_forwarded_for(p)
        else
          ProxyBag.unset_x_forwarded_for(p)
        end
      end

      def self.configure_redeployable(config, p)
        if config[Credeployable]
          ProxyBag.add_redeployable(config[Credeployment_sizelimit] || 16384,p)
        else
          ProxyBag.remove_redeployable(p)
        end
      end

      def self.configure_key(config, p, data)
        if config.has_key?(Ckey)
          ProxyBag.set_key(data[:hash],config[Ckey])
        else
          ProxyBag.set_key(data[:hash],C_empty)
        end
      end

      def self.configure_staticmask(config, p)
        if config.has_key?(Cstaticmask)
          ProxyBag.add_static_mask(Regexp.new(config[Cstaticmask]),p)
        else
          ProxyBag.remove_static_mask(p)
       end
      end

      def self.configure_cache_extensions(config, p)
        if config.has_key?(Ccache_extensions) or config.has_key?(Ccache_directory)
          require 'swiftcore/Swiftiply/support_pagecache'
          ProxyBag.add_suffix_list((config[Ccache_extensions] || ProxyBag.const_get(:DefaultSuffixes)),p)
          ProxyBag.add_cache_dir((config[Ccache_directory] || ProxyBag.const_get(:DefaultCacheDir)),p)
        else
          ProxyBag.remove_suffix_list(p) if ProxyBag.respond_to?(:remove_suffix_list)
          ProxyBag.remove_cache_dir(p) if ProxyBag.respond_to?(:remove_cache_dir)
        end
      end

      def self.configure_cluster_manager(config, p)
        # Check for a cluster management section and do setup.
        # manager: URL
        #
        # manager:
        #   callsite: URL
        #
        # manager:
        #   require: FILENAME
        #   class: CLASSNAME
        #   callsite: CLASS specific destination
        #   params: param list to pass to the class
        #
        # If a filename is not given, cluster management will default to the
        # URL triggered system, which requires a URL

        if config.has_key?(Cmanager)
          config[Cmanager].each do |manager|
            cluster_manager_params = {}
            if Hash === manager
              cluster_manager_params[:callsite] = manager[Ccallsite]
              require manager[Crequire] || "swiftcore/Swiftiply/rest_based_cluster_manager"
              cluster_manager_params[:class] = get_const_from_name(manager[Cclassname] || "RestBasedClusterManager", ::Swiftcore::Swiftiply::ManagerProtocols)
              cluster_manager_params[:params] = manager[Cparams] || []
            else
              cluster_manager_params[:callsite] = manager
              require "swiftcore/Swiftiply/rest_based_cluster_manager"
              cluster_manager_params[:class] = ::Swiftcore::Swiftiply::ManagerProtocols::RestBasedClusterManager
              cluster_manager_params[:params] = []
            end
            ProxyBag.add_cluster_manager(cluster_manager_params, hash)
          end
        else
          ProxyBag.remove_cluster_manager(hash)
        end
      end

      def self.configure_backends(k,args)
        config = args[:config]
        p = args[:p]
        config_data = args[:config_data]
        new_config = args[:new_config]
        klass = args[:self]
        directory_class = args[:directory_class]
        directory_args = args[:directory_args]
        
        ProxyBag.remove_filters(p)

        is_a_server = klass.respond_to?(:is_a_server?) && klass.is_a_server?

        if config[k]
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
          config[k].each do |o|
            # Directory classes have a lot of power to customize what's happening. So, make a new instance right away.
            new_directory_class = generate_new_directory_class(directory_class, o, new_config)

            if is_a_server
              if klass.respond_to?(:parse_connection_params)
                params = klass.parse_connection_params(o, new_directory_class) # Provide the directory class, as it might have an opinion on how to parse this information.
                out = params[:out]
                host = params[:host]
                port = params[:port]
                filter = params[:filter]
              else
                if Hash === o
                  out = [o['to'],o['match'],o['prefix']].compact.join('::')
                  host, port = o['to'].split(/:/,2)
                  filter = Regexp.new(o['match'])
                else
                  out = o
                  host, port = out.split(/:/,2)
                  filter = nil
                end
              end
  
              ProxyBag.logger.log(Cinfo,"  Configuring outgoing server #{out}") if ::Swiftcore::Swiftiply::log_level > 0
              ProxyBag.default_name = p if config[Cdefault]
              if Swiftcore::Swiftiply::existing_backends.has_key?(out)
                ProxyBag.logger.log(Cinfo,'    Already running; skipping') if ::Swiftcore::Swiftiply::log_level > 2
                new_config[Coutgoing][out] ||= Swiftcore::Swiftiply::RunningConfig[Coutgoing][out]
                next
              else
                # TODO:  Add ability to create filters for outgoing destinations, so one can send different path patterns to different outgoing hosts/ports.
                Swiftcore::Swiftiply::existing_backends[out] = true
                backend_class = setup_backends(args.dup.merge(:directory_class => new_directory_class), filter)

                begin
                  new_config[Coutgoing][out] = EventMachine.start_server(host, port.to_i, backend_class)
                rescue RuntimeError => e
                  puts e.inspect
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
            else # it's not a server
              if klass.respond_to?(:parse_connection_params)
                params = klass.parse_connection_params(o, new_directory_class) # Provide the directory class, as it might have an opinion on how to parse this information.
                out = params[:out] # this should be some sort of identifier, just for logging purposes.
                filter = params[:out]
              else
                if Hash === o
                  filter = Regexp.new(o['match'])
                end
              end

              out ||= p
              ProxyBag.logger.log(Cinfo,"  Configuring outgoing protocol for #{out}") if ::Swiftcore::Swiftiply::log_level > 0
              ProxyBag.default_name = p if config[Cdefault]
              
              setup_backends(args.dup.merge(:directory_class => new_directory_class), filter)
            end
          end # done iterating on config
        else
          new_directory_class = generate_new_directory_class(directory_class, config, new_config)

          if klass.respond_to?(:parse_connection_params)
            params = klass.parse_connection_params({}, new_directory_class) # Provide the directory class, as it might have an opinion on how to parse this information.
            out = params[:out] # this should be some sort of identifier, just for logging purposes.
            filter = params[:out]
          end

          out ||= p
          ProxyBag.logger.log(Cinfo,"  Configuring outgoing protocol for #{out}") if ::Swiftcore::Swiftiply::log_level > 0
          ProxyBag.default_name = p if config[Cdefault]

          setup_backends(args.dup.merge(:directory_class => new_directory_class), filter)
        end
      end

      def self.stop_unused_servers(new_config)
        # Now stop everything that is still running but which isn't needed.
        if Swiftcore::Swiftiply::RunningConfig.has_key?(Coutgoing)
          (Swiftcore::Swiftiply::RunningConfig[Coutgoing].keys - new_config[Coutgoing].keys).each do |unneeded_server_key|
            EventMachine.stop_server(Swiftcore::Swiftiply::RunningConfig[Coutgoing][unneeded_server_key])
          end
        end
      end

      def self.set_server_queue(data, klass, config)
        klass ||= ::Swiftcore::Deque
        ProxyBag.set_server_queue(data[:hash], klass, config)
      end

      def self.generate_new_directory_class(directory_class, config, new_config)
        new_directory_class = Class.new(directory_class)
        new_directory_class.config(config, new_config) if new_directory_class.respond_to? :config
        new_directory_class
      end

      def self.setup_backends(args, filter)
        config = args[:config]
        p = args[:p]
        config_data = args[:config_data]
        new_config = args[:new_config]
        klass = args[:self]
        directory_class = args[:directory_class]
        directory_args = args[:directory_args]

        backend_class = Class.new(klass)
        backend_class.bname = config_data[:hash]
        ProxyBag.logger.log(Cinfo,"    Do Caching") if config['caching'] and ::Swiftcore::Swiftiply::log_level > 0
        backend_class.caching = config['caching'] if backend_class.respond_to? :caching
        ProxyBag.logger.log(Cinfo,"    Permit X-Sendfile") if config_data[:permit_xsendfile] and ::Swiftcore::Swiftiply::log_level > 0
        backend_class.xsendfile = config_data[:permit_xsendfile]
        ProxyBag.logger.log(Cinfo,"    Enable 404 on missing Sendfile resource") if config[Cenable_sendfile_404] and ::Swiftcore::Swiftiply::log_level > 0
        backend_class.enable_sendfile_404 = true if config[Cenable_sendfile_404]                
        backend_class.filter = !filter.nil?

        directory_class.backend_class = backend_class if directory_class.respond_to? :backend_class
        Config.set_server_queue(config_data, directory_class, directory_args)

        ProxyBag.add_filter(filter,config_data[:hash]) if filter
        ProxyBag.set_server_queue_as_filter_queue(config_data[:hash],backend_class) if filter
        backend_class
      end

    end
  end
end
