# This client returns 

require 'swiftcore/Swiftiply/swiftiply_client'

class SendFileClient < SwiftiplyClientProtocol
		def post_init
			@httpdata = ''
			super
		end
			
        def receive_data data
        	@httpdata << data
        	if @httpdata =~ /\r\n\r\n/
				@httpdata =~ /^(\w+)\s+([^\s\?]+).*(1.\d)/
				send_http_data("Doing X-Sendfile to #{$2}",{'Connection' => 'close', 'X-Sendfile' => $2},200,'OK')
				@httpdata = ''
			end
        end
end

if ARGV[0] and ARGV[0].index(/:/) > 0
	h,p = ARGV[0].split(/:/,2)
	EventMachine.run { SendFileClient.connect(h,p.to_i,ARGV[1] || '') }
else
	puts "sendfile_client HOST:PORT [KEY]"
end# -*- coding: ISO-8859-1 -*-

