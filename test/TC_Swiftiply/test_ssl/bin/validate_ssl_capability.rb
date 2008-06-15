require 'rubygems'
require 'eventmachine'
require 'net/http'
require 'net/https'

class P < EventMachine::Connection
	def post_init; start_tls; end
	
	def receive_data x
		send_data("HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Type: text/plain\r\n\r\nBoo!")
		close_connection_after_writing
	end

end

EM.run do
	EM.start_server('127.0.0.1',3333,P)
	EM.add_timer(6) {EM.stop_event_loop}
end


