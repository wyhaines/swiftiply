module Swiftcore
  
	Deque = Array unless HasDeque or const_defined?(:Deque)
  
  module Swiftiply
    Version = '0.6.5'

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
		C_304 = "HTTP/1.1 304 Not Modified\r\n".freeze
		Caos = 'application/octet-stream'.freeze
		Cat = 'at'.freeze
		Ccache_directory = 'cache_directory'.freeze
		Ccache_extensions = 'cache_extensions'.freeze
		Ccluster_address = 'cluster_address'.freeze
		Ccluster_port = 'cluster_port'.freeze
		Ccluster_server = 'cluster_server'.freeze
		CConnection_close = "Connection: close\r\n".freeze
		CConnection_KeepAlive = "Connection: Keep-Alive\r\n".freeze
		CBackendAddress = 'BackendAddress'.freeze
		CBackendPort = 'BackendPort'.freeze
		Ccertfile = 'certfile'.freeze
		Cchunked_encoding_threshold = 'chunked_encoding_threshold'.freeze
		Cxforwardedfor = 'xforwardedfor'.freeze
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
		Cfile_cache = 'file_cache'.freeze
		CGET = 'GET'.freeze
		Cgroup = 'group'.freeze
		CHEAD = 'HEAD'.freeze
		Chost = 'host'.freeze
		Cincoming = 'incoming'.freeze
		Cinfo = 'info'.freeze
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
		Cstaticmask = 'staticmask'.freeze
		Cswiftclient = 'swiftclient'.freeze
		Cthreshold = 'threshold'.freeze
		Ctimeslice = 'timeslice'.freeze
		Ctimeout = 'timeout'.freeze
		Curl = 'url'.freeze
		Cuser = 'user'.freeze
		Cwindow = 'window'.freeze

		C_fsep = File::SEPARATOR
		
		UnknownSocket = Socket::pack_sockaddr_in(0,'0.0.0.0')
		
		RunningConfig = {}

		class EMStartServerError < RuntimeError; end
		class SwiftiplyLoggerNotFound < RuntimeError; end

  end
end
