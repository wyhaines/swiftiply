begin
	load_attempted ||= false
	require 'swiftcore/Swiftiply/cache_base'
rescue LoadError => e
	if !load_attempted
		load_attempted = true
		begin
			require 'rubygems'
		rescue LoadError
			raise e
		end
		retry
	end
	raise e
end

module Swiftcore
	module Swiftiply
		class DynamicRequestCache < CacheBase
			attr_accessor :one_client_name
			
			def initialize(docroot, vw, ts, maxsize)
				@docroot = docroot
				super(vw,ts,maxsize)
			end
			
			def verify(path)
				if @docroot && self[path]
					if ProxyBag.find_static_file(@docroot,path,@one_client_name)
						self.delete path
						false
					else
						true
					end
				else
					false
				end
			end
		end
	end
end