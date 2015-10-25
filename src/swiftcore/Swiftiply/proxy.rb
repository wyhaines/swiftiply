# Super class for all proxy implementations.
module Swiftcore
	module Swiftiply
		class Proxy
			def self.config(conf, new_conf)
				# Process Proxy config; determine which specific proxy implementation to load and pass config control into.
				conf[Cproxy] ||= Ckeepalive if conf[Ckeepalive]
				require "swiftcore/Swiftiply/proxy_backends/#{conf[Cproxy]}"
				klass = Swiftcore::Swiftiply::get_const_from_name(conf[Cproxy].upcase, ::Swiftcore::Swiftiply::Proxies)
				# Need error handling here!
				klass.config(conf, new_conf)
			end
		end
	end
end
