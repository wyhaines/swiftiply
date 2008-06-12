require 'test/unit'
require 'external/test_support'
SwiftcoreTestSupport.set_src_dir
require 'rbconfig'
require 'net/http'
require 'swiftcore/Swiftiply'
require 'yaml'

class TC_ProxyBag < Test::Unit::TestCase
	@@testdir = SwiftcoreTestSupport.test_dir(__FILE__)
	Ruby = File.join(::Config::CONFIG['bindir'],::Config::CONFIG['ruby_install_name']) << ::Config::CONFIG['EXEEXT']
	
	DeleteQueue = []
	KillQueue = []
	
	ConfBase = YAML.load(<<ECONF)
cluster_address: 127.0.0.1
cluster_port: 29998
daemonize: false
map:
  - incoming:
    - 127.0.0.1
    outgoing: 127.0.0.1:29999
    docroot: #{@@testdir}/TC_ProxyBag/test_serve_static_file
    default: true
    redeployable: false
ECONF
	
	def get_url(hostname,port,url)
		Net::HTTP.start(hostname,port) {|http| http.get(url)}
	end
	
	def post_url(hostname,port,url,data = nil)
		Net::HTTP.start(hostname,port) {|http| http.post(url,data)}
	end

	def delete_url(hostname,port,url)
		Net::HTTP.start(hostname,port) {|http| http.delete(url)}
	end
	
	def setup
		Dir.chdir(@@testdir)
		SwiftcoreTestSupport.announce(:proxybag,"ProxyBag")
	end

	def teardown
		while f = DeleteQueue.pop do
			 File.delete f if f
		end
		 
		while p = KillQueue.pop do
			Process.kill("SIGKILL",p) if p
			Process.wait p if p
		end
	end
	
	def test_update_ctime
		pb = Swiftcore::Swiftiply::ProxyBag
		t = pb.update_ctime
		assert_instance_of(Time,t)
	end
	
	def test_now
		pb = Swiftcore::Swiftiply::ProxyBag
		n = pb.update_ctime
		assert_instance_of(Time,pb.now)
		assert_equal(n,pb.now)
	end
	
	def test_set_key
		pb = Swiftcore::Swiftiply::ProxyBag
		assert_nothing_raised do
			pb.set_key(:a,'abc')
		end
		assert_equal('abc',pb.instance_variable_get('@keys')[:a])
	end
	
	def test_get_key
		pb = Swiftcore::Swiftiply::ProxyBag
		assert_nothing_raised do
			pb.set_key(:b,'def')
		end
		assert_equal('def',pb.get_key(:b))
	end
	
	def test_add_id
		pb = Swiftcore::Swiftiply::ProxyBag
		assert_nothing_raised do
			pb.add_id(:abcdef,12345)
		end
		assert_equal(12345,pb.instance_variable_get('@id_map')[:abcdef])
		assert_equal(:abcdef,pb.instance_variable_get('@reverse_id_map')[12345])
	end
	
	def test_remove_id
		pb = Swiftcore::Swiftiply::ProxyBag
		assert_nothing_raised do
			pb.remove_id(:abcdef)
		end
		assert_nil(pb.instance_variable_get('@id_map')[:abcdef])
		assert_nil(pb.instance_variable_get('@reverse_id_map')[12345])
	end
	
	def test_add_incoming_mapping
		pb = Swiftcore::Swiftiply::ProxyBag
		assert_nothing_raised do
			pb.add_incoming_mapping(:abcdef,12345)
		end
		assert_equal(:abcdef,pb.instance_variable_get('@incoming_map')[12345])
	end
	
	def test_remove_incoming_mapping
		pb = Swiftcore::Swiftiply::ProxyBag
		assert_nothing_raised do
			pb.remove_incoming_mapping(12345)
		end
		assert_nil(pb.instance_variable_get('@incoming_map')[12345])
	end
	
	def test_add_incoming_docroot
		pb = Swiftcore::Swiftiply::ProxyBag
		assert_nothing_raised do
			pb.add_docroot('/abc/123',:abcdef)
		end
		assert_equal('/abc/123',pb.instance_variable_get('@docroot_map')[:abcdef])		
	end
	
	def test_remove_incoming_docroot
		pb = Swiftcore::Swiftiply::ProxyBag
		assert_nothing_raised do
			pb.remove_docroot(:abcdef)
		end
		assert_nil(pb.instance_variable_get('@docroot_map')[:abcdef])
	end
	
	def test_add_incoming_redeployable
		pb = Swiftcore::Swiftiply::ProxyBag
		assert_nothing_raised do
			pb.add_redeployable(16384,:abcdef)
		end
		assert_equal(16384,pb.instance_variable_get('@redeployable_map')[:abcdef])		
	end
	
	def test_remove_incoming_redeployable
		pb = Swiftcore::Swiftiply::ProxyBag
		assert_nothing_raised do
			pb.remove_redeployable(:abcdef)
		end
		assert_nil(pb.instance_variable_get('@redeployable_map')[:abcdef])
	end
	
	def test_add_log
		pb = Swiftcore::Swiftiply::ProxyBag
		assert_nothing_raised do
			pb.add_log('/foo/bar',:abcdef)
		end
		assert_equal(['/foo/bar',1],pb.instance_variable_get('@log_map')[:abcdef])
	end
	
	def test_default_name
		pb = Swiftcore::Swiftiply::ProxyBag
		assert_nothing_raised do
			pb.default_name = 'test'
		end
		assert_equal('test',pb.instance_variable_get('@default_name'))
	end
	
	def test_server_unavailable_timeout
		pb = Swiftcore::Swiftiply::ProxyBag
		assert_nothing_raised do
			pb.server_unavailable_timeout = 3
		end
		assert_equal(3,pb.instance_variable_get('@server_unavailable_timeout'))
	end
	
	def test_find_static_file
		dr = Dir.pwd
		path_info = "testfile#{Time.now.to_i}"
		File.open(path_info,'w') {|fh| fh.puts "alfalfa leafcutter bee"}
		assert_equal(File.join(dr,path_info),Swiftcore::Swiftiply::ProxyBag.find_static_file(dr,path_info,'foo'))
		assert_equal(nil,Swiftcore::Swiftiply::ProxyBag.find_static_file(dr,'xyzzy','foo'))
		File.delete(path_info)
	end
	
end
