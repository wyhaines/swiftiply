# -*- coding: ISO-8859-1 -*-
require 'eventmachine'
require 'socket'

# This is a basic Swiftiply client implementation.
#
# An example of a simple echo server:
#
#   require 'swiftcore/swiftiply_client'
#
#   class HttpEcho < SwiftiplyClientProtocol
#     def receive_data data
#       send_http_data data
#     end
#   end
#
#   EventMachine.run do
#     EventMachine.epoll  # Linux 2.6.x kernels only
#     HttpEcho.connect('127.0.0.1',8080)
#   end
#


class SwiftiplyClientProtocol < EventMachine::Connection
	
	attr_accessor :hostname, :port, :ip, :id
	
	C_dotdotdot = '...'.freeze
	C0s = [0,0,0,0].freeze
	CCCCC = 'CCCC'.freeze
	CContentLength = 'Content-Length'.freeze
	DefaultHeaders = {'Connection' => 'close', 'Content-Type' => 'text/plain'}
	
	def self.connect(hostname = nil,port = nil)
		connection = ::EventMachine.connect(hostname, port, self) do |conn|
			conn.hostname = hostname
			conn.port = port
			ip = conn.ip = conn.__get_ip(hostname)
			conn.id = 'swiftclient' << ip.collect {|x| sprintf('%02s',x.to_i.to_s(16)).sub(' ','0')}.join << sprintf('%04s',port.to_i.to_s(16)).gsub(' ','0')
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
		::EventMachine.add_timer(rand(2)) {self.class.connect(@hostname,@port)}
	end
	
	def send_http_data(data,h = {},status = 200, msg = C_dotdotdot)
		headers = DefaultHeaders.merge(h)
		headers[CContentLength] = data.length
		header_string = ''
		headers.each {|k,v| header_string << "#{k}: #{v}\r\n"}
		send_data("HTTP/1.1 #{status} #{msg}\r\n#{header_string}\r\n\r\n#{data}")
	end
	
	def __get_ip hostname
		Socket.gethostbyname(hostname)[3].unpack(CCCCC) rescue ip = C0s
	end
end