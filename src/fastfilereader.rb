# Written by Francis Cianfrocca (garbagecat10@gmail.com) with contributions
# from Kirk Haines (wyhaines@gmail.com).

begin
	load_attempted ||= false
	require 'eventmachine'
	require 'fastfilereaderext'
rescue LoadError => e
	unless load_attempted
		load_attempted = true
		require 'eventmachine'
		require 'fastfilereaderext'
		retry
	end
	raise e
end

module EventMachine
	class FastFileReader
		include EventMachine::Deferrable

		attr_reader :size

		# TODO, make these constants tunable parameters
		ChunkSize = 16384
		BackpressureLevel = 50000
		MappingThreshold = 32768
		Crn = "\r\n".freeze
		C0rnrn = "0\r\n\r\n".freeze

		class << self
			# Return a newly-created instance of this class, or nil on error.
			#
			def open filename
				FastFileReader.new(filename)
			rescue
				nil
			end

		end

		# This constructor can throw exceptions. Use #open to avoid that fate.
		#
		def initialize filename
			# Throw an exception if we can't open the file.
			# TODO, perhaps we should throw a different exception?
			raise "no file" unless File.exist?(filename)

			@size = File.size?(filename)
			if @size >= MappingThreshold
				@mapping = Mapper.new( filename )
			else
				@content = File.read( filename )
			end
		end


		# This is a no-op for small files that have a @content
		# member. For large files with a @mapping, we call #close
		# on the mapping. In general, this will be done by the
		# finalizer when the GC runs, but there will be cases
		# when we will want to know that the underlying file mapping
		# is closed. This matters particularly on Windows, because
		# we're holding some HANDLE objects open that can cause
		# trouble for Ruby.
		def close
			@mapping.close if @mapping
		end

		# We expect to receive something like an EventMachine::Connection object.
		# We also expect to be running inside a reaactor loop, because we call
		# EventMachine#next_tick when we have too much data to send.
		def stream_as_http_chunks sink
			if @content
				if @content.length > 0
					sink.send_data( "#{@content.length.to_s(16)}\r\n#{@content}#{Crn}" )
				end
				sink.send_data( C0rnrn )
				set_deferred_success
			else
				@position = 0
				@sink = sink
				stream_one_http_chunk
			end
		end

		def stream_one_http_chunk
			loop {
				if @position < @size
					if @sink.get_outbound_data_size > BackpressureLevel
						EventMachine::next_tick {stream_one_http_chunk}
						break
					else
						len = @size - @position
						len = ChunkSize if (len > ChunkSize)
						@sink.send_data( "#{len.to_s(16)}\r\n#{@mapping.get_chunk( @position, len))}\r\n" )
						@position += len
					end
				else
					@sink.send_data( C0rnrn )
					set_deferred_success
					break
				end
			}
		end
		private :stream_one_http_chunk
	end
end

