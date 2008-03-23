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
		class FileCache < CacheBase
			
			def add(path_info,path,data,etag,mtime,header)
				unless self[path_info]
					add_to_verification_queue(path_info)
					ProxyBag.log(owner_hash).log('info',"Adding file #{path} to file cache as #{path_info}") if ProxyBag.level(owner_hash) > 2
				end
				self[path_info] = [data,etag,mtime,path,header]
			end
			
			def verify(path_info)
				if f = self[path_info]
					if File.exist?(f[3])
						mt = File.mtime(f[3])
						if mt == f[2]
							true
						else
							false
						end
					else
						false
					end
				else
					false
				end
			end
		end
	end
end

