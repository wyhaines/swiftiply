#!ruby

require 'optparse'

begin
	load_attempted ||= false
	require 'swiftcore/Swiftiply'
rescue LoadError => e
	unless load_attempted
		load_attempted = true
		require 'rubygems'
		retry
	end
	raise e
end

ClusterAddress = "127.0.0.1"
ClusterPort = 8080
BackendAddress = "127.0.0.1"
BackendPort = 9080

Swiftcore::Swiftiply.run(ClusterAddress,ClusterPort,BackendAddress,BackendPort)
