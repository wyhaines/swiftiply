require 'test/unit'
require 'external/test_support'
SwiftcoreTestSupport.set_src_dir
require 'rbconfig'
require 'swiftcore/deque'

class TC_Deque < Test::Unit::TestCase
	@@testdir = SwiftcoreTestSupport.test_dir(__FILE__)
	
	def setup
		Dir.chdir(@@testdir)
		SwiftcoreTestSupport.announce(:proxybag,"ProxyBag")
	end

	def teardown
		GC.start
	end

	def test_a_new
		dq = nil
		assert_nothing_raised do
			dq = Swiftcore::Deque.new
		end
		assert_kind_of(Swiftcore::Deque,dq)
	end

	def test_b_unshift
		dq = Swiftcore::Deque.new

		assert_nothing_raised do
			dq.unshift "a"
			dq.unshift "b"
			dq.unshift "c"
		end

		assert_equal('["c","b","a"]',dq.inspect)
	end
	
	def test_c_shift
		dq = Swiftcore::Deque.new
		dq.unshift "a"
		dq.unshift "b"
		dq.unshift "c"
		assert_equal("c",dq.shift)
		assert_equal("b",dq.shift)
		assert_equal("a",dq.shift)
		assert_equal(nil,dq.shift)
	end

	def test_d_push
		dq = Swiftcore::Deque.new
		assert_nothing_raised do
			dq.push "a"
			dq.push "b"
			dq.push "c"
		end

		assert_equal('["a","b","c"]',dq.inspect)
	end

	def test_e_pop
		dq = Swiftcore::Deque.new
		dq.push "a"
		dq.push "b"
		dq.push "c"
		assert_equal("c",dq.pop)
		assert_equal("b",dq.pop)
		assert_equal("a",dq.pop)
		assert_equal(nil,dq.pop)
	end
		
	def test_f_size
		dq = Swiftcore::Deque.new
		dq.push "a"
		dq.push "b"
		dq.push "c"
		assert_equal(3,dq.size)
	end

	def test_g_max_size
		dq = Swiftcore::Deque.new
		assert_nothing_raised do
			dq.max_size
		end
	end

	def test_h_clear
		dq = Swiftcore::Deque.new
		dq.push "a"
		dq.push "b"
		dq.push "c"
		assert_nothing_raised do
			dq.clear
		end
		assert_equal(0,dq.size)
		assert_equal("[]",dq.inspect)
	end

	def test_i_empty
		dq = Swiftcore::Deque.new
		dq.push "a"
		assert(!dq.empty?)
		dq.clear
		assert(dq.empty?)
	end

	def test_j_to_s
		dq = Swiftcore::Deque.new
		dq.push "a"
		dq.push "b"
		dq.push "c"
		assert_equal("abc",dq.to_s)
	end

	def test_k_to_a
		dq = Swiftcore::Deque.new
		dq.push "a"
		dq.push "b"
		dq.push "c"
		assert_equal(["a","b","c"],dq.to_a)
	end
	
	def test_l_first
		dq = Swiftcore::Deque.new
		dq.push "a"
		dq.push "b"
		dq.push "c"
		assert_equal("a",dq.first)
	end

	def test_m_last
		dq = Swiftcore::Deque.new
		dq.push "a"
		dq.push "b"
		dq.push "c"
		assert_equal("c",dq.last)
	end

	def test_n_at
		dq = Swiftcore::Deque.new
		dq.push "a"
		dq.push "b"
		dq.push "c"
		assert_equal("a",dq.at(0))
		assert_equal("a",dq[0])
		assert_equal("b",dq.at(1))
		assert_equal("b",dq[1])
		assert_equal("c",dq.at(2))
		assert_equal("c",dq[2])
	end

	def test_o_index
		dq = Swiftcore::Deque.new
		dq.push "a"
		dq.push :b
		dq.push 37
		assert_equal(0,dq.index("a"))
		assert_equal(1,dq.index(:b))
		assert_equal(2,dq.index(37))
	end

end
