require "swiftcore/Swiftiply/http_recognizer"

module Swiftcore
  module Swiftiply

    # The ControlProtocol implements a simple REST HTTP handler that can be
    # used to affect the running configuration of Swiftiply.

    class ControlProtocol < HttpRecognizer

      # Should be able to use this to control all aspects of Swuftiply configuration and behavior.
      #   - Query current performance information and statistics
      #     * GET /status
      #     * GET /status/DOMAIN
      #     * GET /domains
      #     * GET /config/DOMAIN
      #   - Supply new config sections (json payload?)
      #     * POST /config/DOMAIN
      #     * PUT /config/DOMAIN
	    #       (There is currently no useful differentiation between the use of
	    #        POST and PUT in the API; they are both idempotent operations
	    #        that place the provided configuration into Swiftiply.)
      #   - Remove config sections
      #     * DELETE /config/DOMAIN
			def push
        case @request_method
	      when CGET
          case @uri
	        when /\/status(\/(.*))$/
	        when /\/domains/
          when /\/config\/(.+)$/
          end
	      when CPOST, CPUT
          case @uri
	        when /\/config\/(.+)$/
          end
        when CDELETE
          case @uri
	        when /\/config\/(.+)$/
          end
        else
          # No supported method; discard
          close_connection
        end
			end

    end
  end
end
