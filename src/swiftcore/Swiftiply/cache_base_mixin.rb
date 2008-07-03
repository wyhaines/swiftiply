module Swiftcore
	module Swiftiply
		module CacheBaseMixin
			attr_accessor :vw, :owners, :owner_hash, :name
			
			def add_to_verification_queue(path)
				@vq.unshift(path)
				true
			end
			
			def vqlength
				@vq.length
			end

			def check_verification_queue
				start = Time.now
				count = 0
				@push_to_vq = {}
				while Time.now < start + @tl && !@vq.empty?
					count += 1
					path = @vq.pop
					verify(path) ? @push_to_vq[path] = 1 : delete(path)
				end
				@push_to_vq.each_key {|x| add_to_verification_queue(x)}
				
				rt = Time.now - start
				
				# This algorithm is self adaptive based on the amount of work
				# completed in the time slice, and the amount of remaining work
				# in the queue.
				#@vw / (@vq.length / count) * (rt / @tl)
				l = @vq.length
				if l == 0
					@vw / 2
				else
					wait_time = (@vwtl * count) / (l * rt)
					wait_time < rt ? rt * 2.0 : wait_time > @vw ? @vw : wait_time
				end
			end			
		end
	end
end
