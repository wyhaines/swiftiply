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
			
			def initialize(docroot, vw, ts, maxsize)
				@docroot = docroot
				super(vw,ts,maxsize)
			end
			
			def verify(path)
				if self[path]
					if ProxyBag.find_static_file(@docroot,path)
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