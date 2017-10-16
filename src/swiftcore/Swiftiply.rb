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
    require 'swiftcore/Swiftiply/proxy'

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

    Updaters = {
            'rest' => ['swiftcore/Swiftiply/config/rest_updater','::Swiftcore::Swiftiply::Config::RestUpdater']
    }

    def self.existing_backends
      @existing_backends
    end

    def self.existing_backends=(val)
      @existing_backends = val
    end

    # Start the EventMachine event loop and create the front end and backend
    # handlers, then create the timers that are used to expire unserviced
    # clients and to update the Proxy's clock.

    def self.run(config)
      self.existing_backends = {}

      # Default is to assume we want to try to turn epoll/kqueue support on.
      EventMachine.epoll unless config.has_key?(Cepoll) and !config[Cepoll] rescue nil
      EventMachine.kqueue unless config.has_key?(Ckqueue) and !config[Ckqueue] rescue nil
      EventMachine.set_descriptor_table_size(config[Cepoll_descriptors] || config[Cdescriptors] || 4096) rescue nil

      EventMachine.run do
        EM.set_timer_quantum(5)
        trap("HUP") {em_config(Swiftcore::SwiftiplyExec.parse_options); GC.start}
        trap("INT") {EventMachine.stop_event_loop}
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

    def self.log_level
      @log_level
    end

    def self.log_level=(val)
      @log_level = val
    end

    # TODO: This method is absurdly long, and should be refactored.
    def self.em_config(config)
      new_config = {Ccluster_address => [],Ccluster_port => [],Ccluster_server => {}}
      defaults = config['defaults'] || {}

      new_log = _config_loggers(config,defaults)
      self.log_level = ProxyBag.log_level
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
        Swiftcore::Swiftiply::Proxy.config(m,new_config)
      end

      updater = nil
      if config[Cupdates]
        uconf = config[Cupdates]
        require Updaters[uconf[Cupdater]].first
        updater = Updaters[uconf[Cupdater]].last
      end

      updater_class = Swiftcore::Swiftiply::class_by_name(updater) if updater
      self.class.const_set(:Updater, updater_class.new(uconf)) if updater

      #EventMachine.set_effective_user = config[Cuser] if config[Cuser] and RunningConfig[Cuser] != config[Cuser]
      run_as(config[Cuser],config[Cgroup]) if (config[Cuser] and RunningConfig[Cuser] != config[Cuser]) or (config[Cgroup] and RunningConfig[Cgroup] != config[Cgroup])
      new_config[Cuser] = config[Cuser]
      new_config[Cgroup] = config[Cgroup]

      ProxyBag.server_unavailable_timeout ||= config[Ctimeout]

      # By default any file over 16k will be sent via chunked encoding
      # if the client supports HTTP 1.1.  Generally there is no reason
      # to change this, but it is configurable.

      ProxyBag.chunked_encoding_threshold = config[Cchunked_encoding_threshold] || 16384

      ProxyBag.health_check_uri = config[Chealth_check_uri] || '/swiftiply_health'

      # The default cache_threshold is set to 100k.  Files above this size
      # will not be cached.  Customize this value in your configurations
      # as necessary for the best performance on your site.

      ProxyBag.cache_threshold = config['cache_threshold'] || 102400

      unless RunningConfig[:initialized]
        EventMachine.add_periodic_timer(0.1) { ProxyBag.recheck_or_expire_clients }
        #EventMachine.next_tick { ProxyBag.do_and_requeue_recheck_or_expire_clients }
        EventMachine.add_periodic_timer(1) { ProxyBag.update_ctime }
        EventMachine.add_periodic_timer(1) { ProxyBag.request_worker_resources }
        new_config[:initialized] = true
      end

      Updater.start if updater
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

    def self.class_by_name(name)
      klass = Object
      name.sub(/^::/,'').split('::').each {|n| klass = klass.const_get n}
      klass
    end

    def self.handle_logger_config(logger_config = nil,handle_default = true)
      new_logger = {}
      if logger_config
        type = logger_config['type'] || 'Analogger'
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
        new_logger[:log_level] = determine_log_level(logger_config['level'] || logger_config['log_level'])
        begin
          log_class = get_const_from_name(type,::Swiftcore::Swiftiply::Loggers)

          new_logger[:logger] = log_class.new(logger_config)
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
        new_logger[:logger] = log_class.new(logger_config)
        new_logger[:log_level] = log_level
      else
        new_logger = nil
      end

      new_logger
    end

  end
end

