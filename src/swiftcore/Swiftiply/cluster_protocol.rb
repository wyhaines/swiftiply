require "swiftcore/Swiftiply/http_recognizer"

module Swiftcore
  module Swiftiply

    # The ClusterProtocol is the subclass of EventMachine::Connection used
    # to communicate between Swiftiply and the web browser clients.

    class ClusterProtocol < HttpRecognizer

      proxy_bag_class_is Swiftcore::Swiftiply::ProxyBag

      C503Header = "HTTP/1.1 503 Server Unavailable\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n"

      def self.init_class_variables
        @count_503 = 0
        super
      end

      def self.increment_503_count
        @count_503 += 1
      end
      
      # Hardcoded 503 response that is sent if a connection is timed out while
      # waiting for a backend to handle it.

      def send_503_response
        ip = Socket::unpack_sockaddr_in(get_peername).last rescue Cunknown_host
        error = "The request (#{@uri} --> #{@name}), received on #{create_time.asctime} from #{ip} timed out before being deployed to a server for processing."
        send_data "#{C503Header}Server Unavailable\n\n#{error}".b
        ProxyBag.logger.log(Cinfo,"Server Unavailable -- #{error}")
        close_connection_after_writing
        increment_503_count
      end
  
      def increment_503_count
        @klass.increment_503_count
      end

      def push
        if @associate
          unless @redeployable
            # normal data push
            data = nil
            @associate.send_data data.b while data = @data.pop
          else
            # redeployable data push; just send the stuff that has
            # not already been sent.
            (@data.length - 1 - @data_pos).downto(0) do |p|
              d = @data[p]
              @associate.send_data d.b
              @data_len += d.length
            end
            @data_pos = @data.length

            # If the request size crosses the size limit, then
            # disallow redeployent of this request.
            if @data_len > @redeployable
              @redeployable = false
              @data.clear
            end
          end
        end
      end

    end
  end
end
