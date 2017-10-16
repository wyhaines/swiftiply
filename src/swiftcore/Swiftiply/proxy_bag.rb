# encoding: ASCII-8BIT

module Swiftcore
  module Swiftiply

    # The ProxyBag is a class that holds the client and the server queues,
    # and that is responsible for managing them, matching them, and expiring
    # them, if necessary.

    class ProxyBag

      attr_reader :keepalive_queue

      @client_q = Hash.new {|h,k| h[k] = Deque.new}
      #@client_q = Hash.new {|h,k| h[k] = []}
#     @server_q = Hash.new {|h,k| h[k] = Deque.new}
      @server_q = {}
      @backup_map = {}
      @worker_request_semaphores = {}
      @keepalive_q = Deque.new
      @logger = nil
      @ctime = Time.now
      @dateheader = "Date: #{@ctime.httpdate}\r\n\r\n"
      @server_unavailable_timeout = 10
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
      @x_forwarded_for = {}
      @keepalive = {}
      @static_mask = {}
      @keys = {}
      @filters = {}
      @cluster_managers = {}
      @demanding_clients = Hash.new {|h,k| h[k] = Deque.new}
      @hitcounters = Hash.new {|h,k| h[k] = 0}
      # Kids, don't do this at home.  It's gross.
      @typer = MIME::Types.instance_variable_get('@__types__')

      MockLog = Swiftcore::Swiftiply::MockLog.new

      class << self

        def client_q
          @client_q
        end

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

        # Returns the access key.  If an access key is set, then all new
        # backend connections must send the correct access key before
        # being added to the cluster as a valid backend.

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

        def set_server_queue(hashcode, klass, data)
          @server_q[hashcode] = klass.new(*data)
        end

        def server_queue(hashcode)
          @server_q[hashcode]
        end

        def backup_mapping(name)
          @backup_map[name]
        end

        def add_backup_mapping(backup,name)
          @backup_map[name] = backup
        end

        def remove_backup_mapping(name)
          @backup_map.delete(map)
        end

        def add_docroot(path,name)
          @docroot_map[name] = File.expand_path(path)
        end

        def remove_docroot(name)
          @docroot_map.delete(name)
        end

        def add_sendfileroot(path,name)
          @sendfileroot_map[name] = path
        end

        def remove_sendfileroot(name)
          @sendfileroot_map.delete(name)
        end

        def get_sendfileroot(name)
          @sendfileroot_map[name]
        end

        def add_redeployable(limit,name)
          @redeployable_map[name] = limit
        end

        def remove_redeployable(name)
          @redeployable_map.delete(name)
        end

        def add_log(log,name)
          @log_map[name] = [log,1]
        end

        def log(name)
          (@log_map[name] && @log_map[name].first) || MockLog
        end

        def remove_log(name)
          @log_map[name].close if @log_map[name].respond_to? :close
          @log_map.delete(name)
        end

        def set_level(level,name)
          @log_map[name][1] = level
        end

        def level(name)
          (@log_map[name] && @log_map[name].last) || 0
        end

        def add_file_cache(cache,name)
          @file_cache_map[name] = cache
        end

        def file_cache_map
          @file_cache_map
        end

        def add_dynamic_request_cache(cache,name)
          @dynamic_request_map[name] = cache
        end

        def dynamic_request_cache
          @dynamic_request_map
        end

        def add_etag_cache(cache,name)
          @etag_cache_map[name] = cache
        end

        def x_forwarded_for(name)
          @x_forwarded_for[name]
        end

        def set_x_forwarded_for(name)
          @x_forwarded_for[name] = true
        end

        def unset_x_forwarded_for(name)
          @x_forwarded_for[name] = false
        end

        def add_static_mask(regexp, name)
          @static_mask[name] = regexp
        end

        def static_mask(name)
          @static_mask[name]
        end

        def remove_static_mask(name)
          @static_mask.delete(name)
        end

        def add_filter(filter, name)
          (@filters[name] ||= []) << filter
        end

        def filter(name)
          @filters[name]
        end

        def remove_filters(name)
          @filters[name].clear if @filters[name]
        end

        def set_server_queue_as_filter_queue(name,klass)
          @server_q[name] = Hash.new {|h,k| h[k] = klass.new}
        end

        def worker_request_config(name)
          @worker_request_config[name]
        end

        def add_worker_request_config(name, config)
          @worker_request_config[name] = config
        end

        def remove_worker_request_config(name)
          @worker_request_config.delete(name)
        end

        def add_keepalive(timeout, name)
          @keepalive[name] = timeout == 0 ? false : timeout
        end

        def keepalive(name)
          @keepalive[name]
        end

        def remove_keepalive(name)
          @keepalive[name] = false
        end

        def add_cluster_manager(cluster_manager_params, name)
          @cluster_managers[name] = cluster_manager_params
        end

        def cluster_manager(name)
          @cluster_managers[name]
        end

        def remove_cluster_manager(name)
          @cluster_managers.delete(name)
        end

        # Sets the default proxy destination, if requests are received
        # which do not match a defined destination.

        def default_name
          @default_name
        end

        def default_name=(val)
          @default_name = val
        end

        def health_check_uri
          @health_check_uri
        end

        def health_check_uri=(val)
          @health_check_uri = val
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

        def current_client_name
          @current_client_name
        end

        # The chunked_encoding_threshold is a file size limit.  Files
        # which fall below this limit are sent in one chunk of data.
        # Files which hit or exceed this limit are delivered via chunked
        # encoding.  This enforces a maximum threshold of 32k.

        def chunked_encoding_threshold
          @chunked_enconding_threshold || 32768
        end

        def chunked_encoding_threshold=(val)
          @chunked_encoding_threshold = val > 10485760 ? 10485760 : val         
        end

        def cache_threshold
          @cache_threshold || 32768
        end

        def cache_threshold=(val)
          @cache_threshold = val > 256*1024 ? 256*1024 : val
        end

        # Swiftiply maintains caches of small static files, etags, and
        # dynamnic request paths for each cluster of backends.
        # A timer is created when each cache is created, to do the
        # initial update.  Thereafer, the verification method on the
        # cache returns the number of seconds to wait before running
        # again.

        def verify_cache(cache)
          log(cache.owner_hash).log(Cinfo,"Checking #{cache.class.name}(#{cache.vqlength}/#{cache.length}) for #{cache.owners}") if level(cache.owner_hash) > 2
          new_interval = cache.check_verification_queue
          log(cache.owner_hash).log(Cinfo,"  Next #{cache.class.name} check in #{new_interval} seconds") if level(cache.owner_hash) > 2
          EventMachine.add_timer(new_interval) do
            verify_cache(cache)
          end
        end

        # Handle static files.  It employs an extension to efficiently
        # handle large files, and depends on an addition to
        # EventMachine, send_file_data(), to efficiently handle small
        # files.  In my tests, it streams in excess of 120 megabytes of
        # data per second for large files, and does as much as 25000
        # requests per second with small files (i.e. under 4k).  I think
        # this can still be improved upon for small files.
        #
        # This code is damn ugly.

        def serve_static_file(clnt,docroot = nil)
          Encoding::default_external = 'ASCII-8BIT'
          request_method = clnt.request_method

          # Only GET and HEAD requests can return a file.
          if request_method == CGET || request_method == CHEAD
            path_info = clnt.uri
            client_name = clnt.name
            docroot ||= @docroot_map[client_name]
            filecache = @file_cache_map[client_name]

						# If it is in the file cache...
            data = filecache[path_info] || filecache[clnt.unparsed_uri]
            if data && (data[4].nil? || clnt.header_data == data[4])
              none_match = clnt.none_match
              same_response = case
                when request_method == CHEAD then false
                when none_match && none_match == C_asterisk then false
                when none_match && !none_match.strip.split(/\s*,\s*/).include?(data[1]) then false
                else none_match
                end 
              if same_response
                clnt.send_data "#{C_304}#{clnt.connection_header}Content-Length: 0\r\n#{@dateheader}"
                owner_hash = filecache.owner_hash
                log(owner_hash).log(Cinfo,"#{Socket::unpack_sockaddr_in(clnt.get_peername || UnknownSocket).last} \"GET #{path_info} HTTP/#{clnt.http_version}\" 304 -") if level(owner_hash) > 1
              else
                unless request_method == CHEAD
                  clnt.send_data "#{data.last}#{clnt.connection_header}#{@dateheader}#{data.first}"
                  owner_hash = filecache.owner_hash
                  log(owner_hash).log(Cinfo,"#{Socket::unpack_sockaddr_in(clnt.get_peername || UnknownSocket).last} \"GET #{path_info} HTTP/#{clnt.http_version}\" 200 #{data.first.length}") if level(owner_hash) > 1
                else
                  clnt.send_data "#{data.last}#{clnt.connection_header}#{@dateheader}"
                  owner_hash = filecache.owner_hash
                  log(owner_hash).log(Cinfo,"#{Socket::unpack_sockaddr_in(clnt.get_peername || UnknownSocket).last} \"HEAD #{path_info} HTTP/#{clnt.http_version}\" 200 -") if level(owner_hash) > 1
                end
              end

              unless clnt.keepalive
                clnt.close_connection_after_writing
              else
                clnt.reset_state
              end

              true
            elsif path = find_static_file(docroot,path_info,client_name)
              #TODO: There is a race condition here between when we detect 
							# whether the file is there, and when we start to deliver it.
              # It'd be nice to handle an exception when trying to read the file
							# in a graceful way, by falling out as if no static file had been
							# found.  That way, if the file is deleted between detection and
							# the start of delivery, such as might happen when delivering
							# files out of some sort of page cache, it can be handled in a
							# reasonable manner.  This should be easily doable, so DO IT SOON!
              none_match = clnt.none_match
              etag,mtime = @etag_cache_map[client_name].etag_mtime(path)
              same_response = nil
              same_response = case
                when request_method == CHEAD then false
                when none_match && none_match == C_asterisk then false
                when none_match && !none_match.strip.split(/\s*,\s*/).include?(etag) then false
                else none_match
              end

              if same_response
                clnt.send_data "#{C_304}#{clnt.connection_header}Content-Length: 0\r\n#{@dateheader}"

                unless clnt.keepalive
                  clnt.close_connection_after_writing
                else
                  clnt.reset_state
                end

                owner_hash = filecache.owner_hash
                log(owner_hash).log(Cinfo,"#{Socket::unpack_sockaddr_in(clnt.get_peername || UnknownSocket).last} \"GET #{path_info} HTTP/#{clnt.http_version}\" 304 -") if level(owner_hash) > 1
              else
                ct = @typer.simple_type_for(path) || Caos 
                fsize = File.size(path)

                header_line = "HTTP/1.1 200 OK\r\nETag: #{etag}\r\nContent-Type: #{ct}\r\nContent-Length: #{fsize}\r\n"
                fd = nil
                if fsize < @chunked_encoding_threshold
                  File.open(path,'r:ASCII-8BIT') {|fh| fd = fh.sysread(fsize)}
                  clnt.send_data "#{header_line}#{clnt.connection_header}#{@dateheader}"
                  unless request_method == CHEAD
                    if fsize < 32768
                      clnt.send_file_data path
                    else
                      clnt.send_data fd
                    end
                  end

                  unless clnt.keepalive
                    clnt.close_connection_after_writing
                  else
                    clnt.reset_state
                  end

                elsif clnt.http_version != C1_0 && fsize > @chunked_encoding_threshold
                  clnt.send_data "HTTP/1.1 200 OK\r\n#{clnt.connection_header}ETag: #{etag}\r\nContent-Type: #{ct}\r\nTransfer-Encoding: chunked\r\n#{@dateheader}"
                  EM::Deferrable.future(clnt.stream_file_data(path, :http_chunks=>true)) {clnt.close_connection_after_writing} unless request_method == CHEAD
                else
                  clnt.send_data "#{header_line}#{clnt.connection_header}#{@dateheader}"
                  EM::Deferrable.future(clnt.stream_file_data(path, :http_chunks=>false)) {clnt.close_connection_after_writing} unless request_method == CHEAD
                end

                filecache.add(path_info, path, fd || File.read(path, mode: 'rb', encoding: 'ASCII-8BIT'),etag,mtime,nil,header_line) if fsize < @cache_threshold

                owner_hash = filecache.owner_hash
                log(owner_hash).log(Cinfo,"#{Socket::unpack_sockaddr_in(clnt.get_peername || UnknownSocket).last} \"#{request_method} #{path_info} HTTP/#{clnt.http_version}\" 200 #{request_method == CHEAD ? C_empty : fsize}") if level(owner_hash) > 1
              end
              true
            end
          else
            false
          end
          # The exception is going to be eaten here, because some
          # dumb file IO error shouldn't take Swiftiply down.
        rescue Object => e
          puts "KABOOM: #{e}\n#{e.backtrace.inspect}"
          @logger.log('error',"Failed request for #{docroot.inspect}/#{path.inspect} -- #{e} @ #{e.backtrace.inspect}") if @log_level > 0

          # TODO: This is uncivilized; if there is an unexpected error, a reasonable response MUST be returned.
          clnt.close_connection_after_writing
          false
        end       

        # Determine if the requested file, in the given docroot, exists
        # and is a file (i.e. not a directory).
        #
        # If Rails style page caching is enabled, this method will be
        # dynamically replaced by a more sophisticated version.

        def find_static_file(docroot,path_info,client_name)
          return unless docroot
          path = File.join(docroot,path_info)
          path if FileTest.exist?(path) and FileTest.file?(path) and File.expand_path(path).index(docroot) == 0 and !(x = static_mask(client_name) and path =~ x) ? path : false
        end

        # Pushes a front end client (web browser) into the queue of
        # clients waiting to be serviced if there's no server available
        # to handle it right now.

        def add_frontend_client(clnt,data_q,data)
          clnt.create_time = @ctime

          # Initialize parameters relevant to redeployable requests, if this client
          # has them enabled.
          clnt.data_pos = clnt.data_len = 0 if clnt.redeployable = @redeployable_map[clnt.name]

          uri = clnt.uri
          name = clnt.name
          drm = @dynamic_request_map[name]
          if drm[uri] || !serve_static_file(clnt)
            # It takes two requests to add it to the dynamic verification
            # queue. So, go from nil to false, then from false to
            # insertion into the queue.
            unless drmval = drm[uri]
              if drmval == false
                drm[uri] = drm.add_to_verification_queue(uri)
                log(drm.owner_hash).log(Cinfo,"Adding request #{uri} to dynamic request cache") if level(drm.owner_hash) > 2
              else
                drm[uri] = false
              end
            end

            # A lot of sites won't need to check X-FORWARDED-FOR, so
            # we'll only take the time to munge the headers to add
            # it if the config calls for it.
            if x_forwarded_for(clnt.name) and peername = clnt.get_peername
              data.sub!(/\r\n\r\n/,"\r\nX-FORWARDED-FOR: #{Socket::unpack_sockaddr_in(peername).last}\r\n\r\n")
            end

            data_q.unshift data
            unless match_client_to_server_now(clnt)
              if clnt.uri =~ /\w+-\w+-\w+\.\w+\.[\w\.]+-(\w+)?$/
                @demanding_clients[$1].unshift clnt
              else
                @client_q[@incoming_map[name]].unshift(clnt)
              end
            end
          end
        end

        def rebind_frontend_client(clnt)
          clnt.create_time = @ctime
          clnt.data_pos = clnt.data_len = 0

          unless match_client_to_server_now(clnt)
            if clnt.uri =~ /\w+-\w+-\w+\.\w+\.[\w\.]+-(\w+)?$/
            #if $& ####
              @demanding_clients[$1].unshift clnt
            else
              @client_q[@incoming_map[clnt.name]].unshift(clnt)
            end
          end
        end

        # Pushes a backend server into the queue of servers waiting for
        # a client to service if there are no clients waiting to be
        # serviced.

        def add_server srvr
          if f = srvr.filter
            #q[f].unshift(srvr) unless match_server_to_client_now(srvr)
            q[f].unshift(srvr)
          else
            #@server_q[srvr.name].unshift(srvr) unless match_server_to_client_now(srvr)
            @server_q[srvr.name].unshift(srvr)
          end
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
          @current_client_name = client.name
          hash = @incoming_map[@current_client_name]

          if outgoing_filters = @filters[hash]
            outgoing_filters.each do |f|
              # This is inefficient if there are a lot of filters. Maybe instead
              # of a regex, filters need something faster/more basic, like a
              # trie that just does prefix matching?
              if client.uri =~ f
                sq = @server_q[@incoming_map[client.name][f]]
                break
              end
            end
          end

          sq ||= @server_q[hash]

# 0b9b883b-552f2e61-693d1970.a.1.5-7f0000015a97
          if client.uri =~ /\w+-\w+-\w+\.\w+\.[\w\.]+-(\w+)?$/
            if sidx = sq.index(@reverse_id_map[$1])
              server = sq[sidx]
              sq.delete_at(sidx)
              #server = sq.slice!(sidx,1)
              server.associate = client
              client.associate = server
              client.push
              true
            else
              # This is an IOWA session request, but the desired worker is busy.
              false
            end
          elsif server = sq.pop
            server.associate = client
            client.associate = server
            client.push
            true
          else
            # There are no available workers.
            @worker_request_semaphores[hash] = [client.name, C_plus] if @cluster_managers.has_key?(hash)
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

        def do_and_requeue_recheck_or_expire_clients
          recheck_or_expire_clients if rand() > 0.9
          EventMachine.next_tick { do_and_requeue_recheck_or_expire_clients }
        end

        # Walk through the waiting clients if there is no server
        # available to process clients and expire any clients that
        # have been waiting longer than @server_unavailable_timeout
        # seconds.  Clients which are expired will receive a 503
        # response.  If this is happening, either you need more
        # backend processes, or your @server_unavailable_timeout is
        # too short.

        def recheck_or_expire_clients
          if @server_q.any?
            now = Time.now
            @client_q.each_key do |name|
              while c = @client_q[name].pop
                if (now - c.create_time) >= @server_unavailable_timeout
                  c.send_503_response
                elsif !match_client_to_server_now(c)
                  @client_q[name].push c
                  break
                end
              end
            end
            @demanding_clients.each_key do |name|
              while c = @demanding_clients[name].pop
                if (now - c.create_time) >= @server_unavailable_timeout
                  c.send_503_response
                elsif !match_client_to_server_now(c)
                  @demanding_clients[name].push c
                  break
                end
              end
            end
          end
        end

        def check_for_queued_requests(client_name)
          if client = @client_q[client_name].pop
            unless match_client_to_server_now(client)
              @client_q[client_name].push client
            end
          end
        end

        # This is called by a periodic timer once a second to update
        # the time.

        def update_ctime
          @ctime = Time.now
          @dateheader[C_date_header_range] = @ctime.httpdate
        end

        # Run through the list of sites that encountered a situation where
        # there were no available workers to handle a request, and fire off
        # a request for more resources.
        # Note that this is only an advisory request -- there is no requirement
        # for anything to actually deploy more resources in response to this.
        #
        # In an ideal world, there's a cluster manager that can receive this
        # request, examine the current load situation, and do _something_ to
        # deploy more requests if they are available.

        def request_worker_resources
          @worker_request_semaphores.each do |name, request|
            cluster_manager = @cluster_managers[name]
            params = cluster_manager[:params] # This needs to be more sophisticated so that details from the request can get inserted dynamically.
            @worker_request_semaphores.delete(name) if cluster_manager[:class].call(cluster_manager[:callsite], request, params)
          end
        end

      end
    end
  end
end
