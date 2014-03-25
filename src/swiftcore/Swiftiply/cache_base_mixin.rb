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
				vql = @vq.length
				qg = vql - @old_vql
				while Time.now < start + @tl && !@vq.empty?
					count += 1
					path = @vq.pop
					verify(path) ? @push_to_vq[path] = 1 : delete(path)
				end
				@push_to_vq.each_key {|x| add_to_verification_queue(x)}
				@old_vql = @vq.length

				rt = Time.now - start

				# This algorithm is self adaptive based on the amount of work
				# completed in the time slice, and the amount of remaining work
				# in the queue.
				# (verification_window / (verification_queue_length / count)) * (real_time / time_limit)

				# If the queue growth in the last time period exceeded the count of items consumed this time,
				# use the ratio of the two to reduce the count number. This will result in a shorter period of
				# of time before the next check cycle. This lets the system stay on top of things when there
				# are bursts.
				if qg > count
					count *= count/qg
				end
				if vql == 0
					@vw / 2
				else
					wait_time = (@vwtl * count) / (vql * rt)
					wait_time < rt ? rt * 2.0 : wait_time > @vw ? @vw : wait_time
				end
			end			
		end
	end
end
