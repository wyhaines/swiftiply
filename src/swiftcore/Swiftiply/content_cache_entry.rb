# This was inspired by Paul Sadauskas' Resourceful library: http://github.com/paul/resourceful
module Swiftcore
	module Swiftiply
		class ContentCacheEntry < ::Hash

			# @param [Resourceful::Request] request
			#   The request whose response we are storing in the cache.
			# @param response<Resourceful::Response>
			#   The Response obhect to be stored.
			def initialize(request, response)
				super()
				self[:request_uri] = request.uri
				self[:request_time] = request.request_time
				self[:request_vary_headers] = select_request_headers(request, response)
				self[:response] = response
			end

			# Returns true if this entry may be used to fullfil the given request, 
			# according to the vary headers.
			#
			# @param request<Resourceful::Request>
			#   The request to do the lookup on. 
			def valid_for?(request)
				request.uri == self[:request_uri] && self[:request_vary_headers].all? {|key, value| request.header[key] == value }
			end

			# Selects the headers from the request named by the response's Vary header
			# http://www.w3.org/Protocols/rfc2616/rfc2616-sec13.html#sec13.5.6
			#
			# @param [Resourceful::Request] request
			#   The request used to obtain the response.
			# @param [Resourceful::Response] response
			#   The response obtained from the request.
			def select_request_headers(request, response)
				headers = {}

# Broken
				self[:response].header['Vary'].each { |name| header[name] = request.header[name] if request.header[name] } if response.header['Vary']

				header
			end
		end
	end
end
