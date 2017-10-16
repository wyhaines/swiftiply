# Encoding:ascii-8bit

require 'cgi'
require "swiftcore/Swiftiply/constants"

module Swiftcore
  module Swiftiply
    class NotImplemented < Exception; end

    # This module implements the HTTP handling code. I call it a recognizer,
    # and not a parser because it does not parse HTTP. It is much simpler than
    # that, being designed only to recognize certain useful bits very quickly.

    class HttpRecognizer < EventMachine::Connection

      attr_accessor :create_time, :last_action_time, :uri, :unparsed_uri, :associate, :name, :redeployable, :data_pos, :data_len, :peer_ip, :connection_header, :keepalive, :header_data

      Crn = "\r\n".freeze
      Crnrn = "\r\n\r\n".freeze
      C_blank = ''.freeze
      C_percent = '%'.freeze
      Cunknown_host = 'unknown host'.freeze
      C200Header = "HTTP/1.0 200 OK\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n"
      C404Header = "HTTP/1.0 404 Not Found\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n"
      C400Header = "HTTP/1.0 400 Bad Request\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n"

      def self.proxy_bag_class_is klass
        const_set(:ProxyBag, klass)
      end

      def self.init_class_variables
        @count_404 = 0
        @count_400 = 0
      end

      def self.increment_404_count
        @count_404 += 1
      end
      
      def self.increment_400_count
        @count_400 += 1
      end

      # Initialize the @data array, which is the temporary storage for blocks
      # of data received from the web browser client, then invoke the superclass
      # initialization.

      def initialize *args
        @data = Deque.new
        @data_pos = 0
        @connection_header = C_empty
        @header_missing_pieces = @name = @uri = @unparsed_uri = @http_version = @request_method = @none_match = @done_parsing = @header_data = nil
        @keepalive = true
        @klass = self.class
        super
      end

      def reset_state
        @data.clear
        @data_pos = 0
        @connection_header = C_empty
        @header_missing_pieces = @name = @uri = @unparsed_uri = @http_version = @request_method = @none_match = @done_parsing = @header_data = nil
        @keepalive = true
      end
      
      # States:
      # uri
      # name
      # \r\n\r\n
      #   If-None-Match
      # Done Parsing
      def receive_data data
        if @done_parsing
          @data.unshift data
          push
        else
          unless @uri
            # It's amazing how, when writing the code, the brain can be in a zone
            # where line noise like this regexp makes perfect sense, and is clear
            # as day; one looks at it and it reads like a sentence.  Then, one
            # comes back to it later, and looks at it when the brain is in a
            # different zone, and 'lo!  It looks like line noise again.
            #
            # data =~ /^(\w+) +(?:\w+:\/\/([^\/]+))?([^ \?]+)\S* +HTTP\/(\d\.\d)/
            #
            # In case it looks like line noise to you, dear reader, too:            
            #
            # 1) Match and save the first set of word characters.
            #
            #    Followed by one or more spaces.
            #
            #    Match but do not save the word characters followed by ://
            #
            #    2) Match and save one or more characters that are not a slash
            #
            #    And allow this whole thing to match 1 or 0 times.
            #
            # 3) Match and save one or more characters that are not a question
            #    mark or a space.
            #
            #    Match zero or more non-whitespace characters, followed by one
            #    or more spaces, followed by "HTTP/".
            #
            # 4) Match and save a digit dot digit.
            #
            # Thus, this pattern will match both the standard:
            #   GET /bar HTTP/1.1
            # style request, as well as the valid (for a proxy) but less common:
            #   GET http://foo/bar HTTP/1.0
            #
            # If the match fails, then this is a bad request, and an appropriate
            # response will be returned.
            #
            # http://www.w3.org/Protocols/rfc2616/rfc2616-sec3.html#sec5.1.2
            #
            if data =~ /^(\w+) +(?:\w+:\/\/([^ \/]+))?(([^ \?\#]*)\S*) +HTTP\/(\d\.\d)/
              @request_method = $1
              @unparsed_uri = $3
              @uri = $4
              @http_version = $5
              if $2
                @name = $2.intern
                @uri = C_slash if @uri.empty?
                # Rewrite the request to get rid of the http://foo portion.
                
                data.sub!(/^\w+ +\w+:\/\/[^ \/]+([^ \?]*)/,"#{@request_method} #{@uri}")
              end
              @uri = @uri.tr('+', ' ').gsub(/((?:%[0-9a-fA-F]{2})+)/n) {[$1.delete(C_percent)].pack('H*')} if @uri.include?(C_percent)
            else
              send_400_response
              return
            end
          end
          unless @name
            if data =~ /^Host: *([^\r\0:]+)/
              @name = $1.intern
            end
          end
          if @header_missing_pieces
            # Hopefully this doesn't happen often.
            d = @data.to_s << data
          else
            d = data
          end
          if d.include?(Crnrn)
            @name = ProxyBag.default_name unless ProxyBag.incoming_mapping(@name)
            if d =~ /If-None-Match: *([^\r]+)/
              @none_match = $1
            end
            @header_data = d.scan(/Cookie:.*/).collect {|c| c =~ /: ([^\r]*)/; $1}
            @done_parsing = true

            # Keep-Alive works differently on HTTP 1.0 versus HTTP 1.1
            # HTTP 1.0 was not written to support Keep-Alive initially; it was
            # bolted on.  Thus, for an HTTP 1.0 client to indicate that it
            # wants to initiate a Keep-Alive session, it must send a header:
            #
            # Connection: Keep-Alive
            #
            # Then, when the server sends the response, it must likewise add:
            #
            # Connection: Keep-Alive
            #
            # to the response.
            #
            # For HTTP 1.1, Keep-Alive is assumed.  If a client does not want
            # Keep-Alive, then it must send the following header:
            #
            # Connection: close
            #
            # Likewise, if the server does not want to keep the connection
            # alive, it must send the same header:
            #
            # Connection: close
            #
            # to the client.
            
            if @name
              unless ProxyBag.keepalive(@name) == false
                if @http_version == C1_0
                  if data =~ /Connection: Keep-Alive/i
                    # Nonstandard HTTP 1.0 situation; apply keepalive header.
                    @connection_header = CConnection_KeepAlive
                  else
                    # Standard HTTP 1.0 situation; connection will be closed.
                    @keepalive = false
                    @connection_header = CConnection_close
                  end
                else # The connection is an HTTP 1.1 connection.
                  if data =~ /Connection: [Cc]lose/
                    # Nonstandard HTTP 1.1 situation; connection will be closed.
                    @keepalive = false
                  end
                end
              end
              
              # THIS IS BROKEN; the interaction of @data, data, and add_frontend_client needs to be revised
              ProxyBag.add_frontend_client(self,@data,data)
            elsif @uri == ProxyBag.health_check_uri
              send_healthcheck_response
            else
              send_404_response
            end           
          else
            @data.unshift data
            @header_missing_pieces = true
          end
        end
      end
      
      # Hardcoded 400 response that is sent if the request is malformed.

      def send_400_response
        ip = Socket::unpack_sockaddr_in(get_peername).last rescue Cunknown_host
        error = "The request received on #{ProxyBag.now.asctime} from #{ip} was malformed and could not be serviced."
        send_data "#{C400Header}Bad Request\n\n#{error}"
        ProxyBag.logger.log(Cinfo,"Bad Request -- #{error}")
        close_connection_after_writing
        increment_400_count
      end

      # Hardcoded 404 response.  This is sent if a request can't be matched to
      # any defined incoming section.

      def send_404_response
        ip = Socket::unpack_sockaddr_in(get_peername).last rescue Cunknown_host
        error = "The request (#{ CGI::escapeHTML( @uri ) } --> #{@name}), received on #{ProxyBag.now.asctime} from #{ip} did not match any resource know to this server."
        send_data "#{C404Header}Resource not found.\n\n#{error}"
        ProxyBag.logger.log(Cinfo,"Resource not found -- #{error}")
        close_connection_after_writing
        increment_404_count
      end
  
      def send_healthcheck_response
        ip = Socket::unpack_sockaddr_in(get_peername).last rescue Cunknown_host
        message = "Health request from #{ip} at #{ProxyBag.now.asctime}\n400:#{@count_400}\n404:#{@count_404}\n\n"
        send_data "#{C200Header}#{message}"
        ProxyBag.logger.log(Cinfo,"healthcheck from ##{ip}")
        close_connection_after_writing
      end

      # The push method pushes data from the HttpRecognizer to whatever
      # entity is responsible for handling it. You MUST override this with
      # something useful.

      def push
        raise NotImplemented
      end

      # The connection with the web browser client has been closed, so the
      # object must be removed from the ProxyBag's queue if it is has not
      # been associated with a backend.  If it has already been associated
      # with a backend, then it will not be in the queue and need not be
      # removed.

      def unbind
        ProxyBag.remove_client(self) unless @associate
      end

      def request_method; @request_method; end
      def http_version; @http_version; end
      def none_match; @none_match; end

      def setup_for_redeployment
        @data_pos = 0
      end

      def increment_404_count
        @klass.increment_404_count
      end
      
      def increment_400_count
        @klass.increment_400_count
      end
      
    end
  end
end
