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
			pb.add_incoming_docroot('/abc/123',:abcdef)
		end
		assert_equal('/abc/123',pb.instance_variable_get('@docroot_map')[:abcdef])		
	end
	
	def test_remove_incoming_docroot
		pb = Swiftcore::Swiftiply::ProxyBag
		assert_nothing_raised do
			pb.remove_incoming_docroot(:abcdef)
		end
		assert_nil(pb.instance_variable_get('@docroot_map')[:abcdef])
	end
	
	def test_add_incoming_redeployable
		pb = Swiftcore::Swiftiply::ProxyBag
		assert_nothing_raised do
			pb.add_incoming_redeployable(16384,:abcdef)
		end
		assert_equal(16384,pb.instance_variable_get('@redeployable_map')[:abcdef])		
	end
	
	def test_remove_incoming_redeployable
		pb = Swiftcore::Swiftiply::ProxyBag
		assert_nothing_raised do
			pb.remove_incoming_redeployable(:abcdef)
		end
		assert_nil(pb.instance_variable_get('@redeployable_map')[:abcdef])
	end
	
	def test_add_log
		pb = Swiftcore::Swiftiply::ProxyBag
		assert_nothing_raised do
			pb.add_log('/foo/bar',:abcdef)
		end
		assert_equal('/foo/bar',pb.instance_variable_get('@log_map')[:abcdef])
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
		assert_nil(Swiftcore::Swiftiply::ProxyBag.find_static_file(dr,'xyzzy','foo'))
		File.delete(path_info)
	end
	
	def test_serve_static_file
		dc = File.join(Dir.pwd,'TC_ProxyBag')
		dr = File.join(dc,'test_serve_static_file')
		
		smallfile_name = "smallfile#{Time.now.to_i}"
		smallfile_path = File.join(dr,smallfile_name)
		File.open(smallfile_path,'w') {|fh| fh.puts "alfalfa leafcutter bee"}
		DeleteQueue << smallfile_path
		
		bigfile_name = "bigfile#{Time.now.to_i}"
		bigfile_path = File.join(dr,bigfile_name)
		File.open(bigfile_path,'w+') {|fh| fh.write("#{'I am a duck. ' * 6}\n" * 1000)}
		DeleteQueue << bigfile_path
		
		conf_file = File.join(dc,'test_serve_static_file.conf')
		File.open(conf_file,'w+') {|fh| fh.write ConfBase.to_yaml}
		DeleteQueue << conf_file
		
		assert_nothing_raised("setup failed") do
			KillQueue << SwiftcoreTestSupport::create_process(:dir => 'TC_ProxyBag',
				:cmd => ["#{Ruby} -I../../src ../../bin/swiftiply -c test_serve_static_file.conf"])
			KillQueue << SwiftcoreTestSupport::create_process(:dir => 'TC_ProxyBag',
				:cmd => ["#{Ruby} -I../../src ../../bin/echo_client 127.0.0.1:29999"])
			# Make sure everything has time to start, connect, etc... before
			# the tests are executed.
			sleep 1
		end
	
		response = get_url('127.0.0.1',29998,smallfile_name)
		assert_equal("alfalfa leafcutter bee\n",response.body)
		
		response = get_url('127.0.0.1',29998,bigfile_name)
		assert_equal("I am a duck. I am a duck. ",response.body[0..25])
		assert_equal("I am a duck. \n",response.body[-14..-1])
		assert_equal(79000,response.body.length)
		
		# Hit it a bunch of times.
		5000.times { response = get_url('127.0.0.1',29998,smallfile_name) }
		# And it's still correct, right?
		assert_equal("alfalfa leafcutter bee\n",response.body)
	end
	
	def test_serve_normal_proxy
		dc = File.join(Dir.pwd,'TC_ProxyBag')
		dr = File.join(dc,'test_serve_normal_proxy')
		
		conf_file = File.join(dc,'test_serve_normal_proxy.conf')
		File.open(conf_file,'w+') {|fh| fh.write ConfBase.to_yaml}
		DeleteQueue << conf_file
		
		assert_nothing_raised("setup failed") do
			KillQueue << SwiftcoreTestSupport::create_process(:dir => 'TC_ProxyBag',
				:cmd => ["#{Ruby} -I../../src ../../bin/swiftiply -c test_serve_normal_proxy.conf"])
			KillQueue << SwiftcoreTestSupport::create_process(:dir => 'TC_ProxyBag',
				:cmd => ["#{Ruby} -I../../src ../../bin/echo_client 127.0.0.1:29999"])
			sleep 1
		end
		
		# Normal request
		response = get_url('127.0.0.1',29998,'/xyzzy')
		assert_equal("\r\nGET /xyzzy HTTP/1.1\r\nAccept: */*\r\nHost: 127.0.0.1:29998\r\n",response.body)
		
		# With query string params.
		response = get_url('127.0.0.1',29998,'/foo/bar/bam?Q=1234')
		assert_equal("\r\nGET /foo/bar/bam?Q=1234 HTTP/1.1\r\nAccept: */*\r\nHost: 127.0.0.1:29998\r\n",response.body)

		# POST request
		response = post_url('127.0.0.1',29998,'/xyzzy')
		assert_equal("\r\nPOST /xyzzy HTTP/1.1\r\nAccept: */*\r\nHost: 127.0.0.1:29998\r\n",response.body)
		
		# And another verb; different verbs should be irrelevant
		response = delete_url('127.0.0.1',29998,'/xyzzy')
		assert_equal("\r\nDELETE /xyzzy HTTP/1.1\r\nAccept: */*\r\n",response.body[0..38])
	end
end
