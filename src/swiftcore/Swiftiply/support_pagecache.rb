# -*- coding: ISO-8859-1 -*-

# support_pagecache will be required by Swiftiply, as necessary, in order to
# enable support for Rails style page caching.  The caching implementation is
# flexible, using /public/ as the cache directory by default, but allowing that
# default to be overridden, and looking for .html files by default, but also
# allowing that to be overridden.

module Swiftcore
	module Swiftiply
		class ProxyBag
			DefaultCacheDir = 'public'.freeze
			DefaultSuffixes = ['html'.freeze]
			@suffix_list = {}
			@cache_dir = {}
			
			class << self
				def add_suffix_list(list,name)
					@suffix_list[name] = list
				end
				
				def remove_suffix_list(list,name)
					@suffix_list.delete name
				end
				
				def add_cache_dir(dir,name)
					@cache_dir[name] = dir
				end
				
				def remove_cache_dir(name)
					@cache_dir.delete name
				end
				
				def find_static_file(dr,path_info,client_name)
					path = File.join(dr,path_info)
					if FileTest.exist?(path) and FileTest.file?(path)
						path
					elsif @suffix_list.has_key?(client_name)
						path = File.join(dr,@cache_dir[client_name],path_info)
						if FileTest.exist?(path) and FileTest.file?(path)
							path
						else
							for suffix in @suffix_list[client_name] do
								p = "#{path}.#{suffix}"
								return p if FileTest.exist?(p) and FileTest.file?(p)
							end
							nil
						end
					else
						nil
					end
				end
			end
		end
	end
end
