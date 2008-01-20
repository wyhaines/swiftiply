module Swiftcore
	begin
		# Attempt to load the SplayTreeMap and Deque.  If it is not found, rubygems
		# will be required, and SplayTreeMap will be checked for again.  If it is
		# still not found, then it will be recorded as unavailable, and the
		# remainder of the requires will be performed.  If any of them are not
		# found, and rubygems has not been required, it will be required and the
		# code will retry, once.
		load_state ||= :start
		rubygems_loaded ||= false
		load_state = :splaytreemap
		require 'swiftcore/splaytreemap'
		HasSplayTree = true unless const_defined?(:HasSplayTree)

		load_state = :deque
		require 'swiftcore/deque'
		HasDeque = true unless const_defined?(:HasDeque)
		
		load_state = :remainder
	rescue LoadError => e
		if !rubygems_loaded
			begin
				require 'rubygems'
				rubygems_loaded = true
			rescue LoadError
				raise e
			end
			retry
		end
		
		case load_state
		when :deque
			HasDeque = false
			retry
		when :splaytreemap
			HasSplayTreeMap = false
			retry
		end
		
		raise e
	end

		
	if HasSplayTree
		require 'swiftcore/Swiftiply/splay_cache_base'
	else
		require 'swiftcore/Swiftiply/hash_cache_base'
	end
end
