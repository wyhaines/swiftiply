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
			
			def add(path_info,path,data,etag,mtime,cookie,header)
				unless self[path_info]
					add_to_verification_queue(path_info)
					ProxyBag.log(owner_hash).log('info',"Adding file #{path} to file cache as #{path_info}") if ProxyBag.level(owner_hash) > 2
				end
				self[path_info] = [data,etag,mtime,path,cookie,header]
			end
			
			def verify(path_info)
				if f = self[path_info]
					if File.exist?(f[3]) and File.mtime(f[3]) == f[2]
						true
					else
						ProxyBag.log(owner_hash).log('info',"Removing file #{path_info} from file cache") if ProxyBag.level(owner_hash) > 2
						false
					end
				else
					# It was in the verification queue, but not in the file cache.
					false
				end
			end
			
		end
	end
end

