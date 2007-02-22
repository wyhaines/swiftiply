require 'rubygems'
require 'eventmachine'
require 'eventmachine_httpserver'

BackendHost = "127.0.0.1"
BackendPort = 9080

class ClusterBackend < EventMachine::Connection
	include EventMachine::HttpServer

	def initialize *args
		super
		no_environment_strings
	end

	def connection_completed
		@completed = true
		$>.puts "Connected to cluster server #{BackendHost}:#{BackendPort}"
	end

	def process_http_request
		$requests ||= 0
		content = "Process #{Process.pid}: received request number #{$requests += 1} at #{Time.now}"
		send_data [
			"200 HTTP/1.1 Doc follows\r\n",
			"Content-type: text/plain\r\n",
			"Content-length: #{content.length}\r\n",
			"\r\n",
			content
		].join
		close_connection_after_writing
	end
	def unbind
		if @completed
			connect_to_cluster
		else
			$>.puts "FAILED to connect to cluster server #{BackendHost}:#{BackendPort}"
			EventMachine.add_timer(1) {connect_to_cluster}
		end
	end
end

def connect_to_cluster
	EventMachine.connect(BackendHost, BackendPort, ClusterBackend) {|conn|
		conn.set_comm_inactivity_timeout 60
	}
end

def run_machine
	EventMachine.run {
		$>.puts "Process #{Process.pid}"
		$>.puts "Connecting to cluster on #{BackendHost}:#{BackendPort}"
		connect_to_cluster
	}
end

run_machine
