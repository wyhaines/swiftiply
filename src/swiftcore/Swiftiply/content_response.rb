require 'digest/md5'

module Swiftcore
	module Swiftiply
		class ContentResponse < ::Hash
			# data,etag,mtime,path,cookies,headers
			def initialize(uri, headers, cacheable_data)
				parse_basic_http_data headers
				self[:uri] = uri
				self[:headers] = headers
				self[:data] = cacheable_data
				self[:ETag] ||= Digest::MD5.hexdigest(cacheable_data)
			end

			def parse_basic_http_data(headers)
				# The basic interesting pieces are ETag, Date, Expires, Vary, and Cache-Control.
				# I can hear you thinking right now that a line of 'if' statements is gross.
				# You're right. It's also a heaping hell of a lot faster than using something
				# like #scan. So, for this code, you'll just have to accept it.
				# Thanks for your consideration.
				if headers =~ /ETag:\s+(.*)/
					self[:ETag] = $1
				end
				if headers =~ /Date:\s+(.*)/
					self[:Date] = $1
				end
				if headers =~ /Expires:\s+(.*)/
					self[:Expires] = $1
				end
				if headers =~ /Vary:\s+(.*)/
					self[:Vary] = $1
				end
				if headers =~ /Cache-Control:\s+(.*)/
					self[:Cache_Control] = $1
				end
			end

			def header(header_name)
				name_symbol = header_name.to_sym
				self[name_symbol] || (self[:headers] =~ /#{header_name}:\s+(.*)/ && self[name_symbol] = $1)
			end

		end
	end
end
