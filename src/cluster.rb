require 'rubygems'
require 'eventmachine'

ClusterAddress = "127.0.0.1"
ClusterPort = 8080
BackendAddress = "127.0.0.1"
BackendPort = 9080
ServerUnavailableTimeout = 3


class ProxyBag
	@client_q = []
	@server_q = []

	class << self

		def add_frontend_client clnt
			clnt.instance_eval {@create_time = Time.now}
			@client_q.unshift clnt
			match_clients_to_servers
		end

		def add_server srvr
			@server_q.unshift srvr
			match_clients_to_servers
		end

		def remove_server srvr
			@server_q.delete srvr
		end

		def remove_client clnt
			@client_q.delete clnt
		end

		def match_clients_to_servers
			now = Time.now

			while @server_q.first && @client_q.first
				server = @server_q.pop
				client = @client_q.pop
				server.instance_eval {@associate = client}
				client.instance_eval {@associate = server}
				client.push
			end

			unless @server_q.first
				while c = @client_q.pop
					if (now - c.create_time) >= ServerUnavailableTimeout
						$>.puts "Timed out client connection because no backends are available"
						c.send_503_response
					else
						@client_q.push c
						break
					end
				end
			end
		end
	end
end


class ClusterProtocol < EventMachine::Connection
	attr_reader :create_time

	def initialize *args
		@data = []
		super
	end
	def post_init
		$>.puts "Accepted connection from cluster (frontend) client"
		ProxyBag.add_frontend_client self
	end
	def receive_data data
		@data.unshift data
		push
	end

	def send_503_response
		send_data [
			"HTTP/1.0 503 Server Unavailable\r\n",
			"Content-type: text/plain\r\n",
			"Connection: close\r\n",
			"\r\n",
			"Server Unavailable"
		].join
		close_connection_after_writing
	end

	def push
		if @associate
			while data = @data.pop
				@associate.send_data data
			end
		end
	end

	def unbind
		if @associate
			@associate.close_connection_after_writing
		else
			ProxyBag.remove_client(self)
		end
	end
end




class BackendProtocol < EventMachine::Connection
	def post_init
		$>.puts "Accepted connection from backend client"
		ProxyBag.add_server self
	end

	def receive_data data
		# In HTTP, the client talks first so the server will NEVER
		# say anything unless there is an associate.
		@associate.send_data data
	end

	def unbind
		if @associate
			@associate.close_connection_after_writing
		else
			ProxyBag.remove_server(self)
		end
	end
end


EventMachine.run {
	$>.puts "Starting cluster server on #{ClusterAddress}:#{ClusterPort}"
	$>.puts "Starting backend server on #{BackendAddress}:#{BackendPort}"

	EventMachine.start_server ClusterAddress, ClusterPort, ClusterProtocol
	EventMachine.start_server BackendAddress, BackendPort, BackendProtocol
	EventMachine.add_periodic_timer(1) { ProxyBag.match_clients_to_servers }
}

