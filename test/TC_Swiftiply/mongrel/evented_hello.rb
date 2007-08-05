begin
	load_attempted ||= false
	require 'swiftcore/evented_mongrel'
rescue LoadError => e
	unless load_attempted
		load_attempted = true
		require 'rubygems'
		retry
	end
	raise e
end

class SimpleHandler < Mongrel::HttpHandler
	def process(request, response)
		response.start(200) do |head,out|
			head["Content-Type"] = "text/plain"
			out.write("hello!\n")
		end
	end
end

httpserver = Mongrel::HttpServer.new("127.0.0.1", 29998)
httpserver.register("/hello", SimpleHandler.new)
httpserver.register("/dir", Mongrel::DirHandler.new("."))
httpserver.run.join