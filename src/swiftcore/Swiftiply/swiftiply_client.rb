# Encoding:ascii-8bit

begin
	load_attempted ||= false
	require 'eventmachine'
	require 'socket'
rescue LoadError => e
	unless load_attempted
		load_attempted = true
		# Ugh.  Everything gets slower once rubygems are used.  So, for the
		# best speed possible, don't install EventMachine or Swiftiply via
		# gems.
		require 'rubygems'
		retry
	end
	raise e
end

# This is a basic Swiftiply client implementation.

class SwiftiplyClientProtocol < EventMachine::Connection
	
	attr_accessor :hostname, :port, :key, :ip, :id
	
	C_dotdotdot = '...'.freeze
	C0s = [0,0,0,0].freeze
	CCCCC = 'CCCC'.freeze
	CContentLength = 'Content-Length'.freeze
	DefaultHeaders = {'Connection' => 'close', 'Content-Type' => 'text/plain'}
	
	def self.connect(hostname = nil,port = nil,key = '')
		key = key.to_s

		connection = ::EventMachine.connect(hostname, port, self) do |conn|
			conn.hostname = hostname
			conn.port = port
			conn.key = key
			ip = conn.ip = conn.__get_ip(hostname)
			#conn.id = 'swiftclient' << ip.collect {|x| sprintf('%02x',x.to_i)}.join << sprintf('%04x',port.to_i)<< sprintf('%02x',key.length) << key
			conn.id = 'swiftclient' << ip.collect {|x| sprintf('%02x',x.to_i)}.join << sprintf('%04x',$$)<< sprintf('%02x',key.length) << key
			conn.set_comm_inactivity_timeout inactivity_timeout
		end
	end
	
	def self.inactivity_timeout
		@inactivity_timeout || 60
	end
	
	def self.inactivity_timeout=(val)
		@inactivity_timeout = val
	end
	
	def connection_completed
		send_data @id
	end

	def unbind
		::EventMachine.add_timer(rand(2)) {self.class.connect(@hostname,@port,@key)}
	end
	
	def send_http_data(data,h = {},status = 200, msg = C_dotdotdot)
		headers = DefaultHeaders.merge(h)
		headers[CContentLength] = data.length
		header_string = ''
		headers.each {|k,v| header_string << "#{k}: #{v}\r\n"}
		send_data("HTTP/1.1 #{status} #{msg}\r\n#{header_string}\r\n#{data}")
	end
	
	def __get_ip hostname
		Socket.gethostbyname(hostname)[3].unpack(CCCCC) rescue ip = C0s
	end
end
