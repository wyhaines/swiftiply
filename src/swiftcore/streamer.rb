begin
	load_attempted ||= false
	require 'em/streamer'
rescue LoadError
	unless load_attempted
		load_attempted = true
		require 'rubygems'
		retry
	end
end

module EventMachine
	class FileStreamer

		def stream_one_chunk
			loop {
				if @position < @size
					if @connection.get_outbound_data_size > BackpressureLevel
						EventMachine::next_tick {stream_one_chunk}
						break
					else
						len = @size - @position
						len = ChunkSize if (len > ChunkSize)

						#@connection.send_data( "#{format("%x",len)}\r\n" ) if @http_chunks
						if @http_chunks
							@connection.send_data( "#{len.to_s(16)}\r\n" ) if @http_chunks
							@connection.send_data( @mapping.get_chunk( @position, len ))
							@connection.send_data("\r\n") if @http_chunks
						else
							@connection.send_data( @mapping.get_chunk( @position, len ))
						end

						@position += len
					end
				else
					@connection.send_data "0\r\n\r\n" if @http_chunks
					@mapping.close
					succeed
					break
				end
			}
		end

	end
end
