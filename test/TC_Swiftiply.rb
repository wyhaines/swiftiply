require 'test/unit'
require 'external/test_support'
SwiftcoreTestSupport.set_src_dir
require 'rbconfig'
require 'net/http'
require 'swiftcore/Swiftiply'
require 'yaml'

class TC_Swiftiply < Test::Unit::TestCase
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
    docroot: #{@@testdir}/TC_Swiftiply/test_serve_static_file
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
		SwiftcoreTestSupport.announce(:swiftiply_functional,"Functional Swiftiply Testing")
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
	
	# Test serving a small file (no chunked encoding) and a large file (chunked
	# encoding).

	def test_serve_static_file
		puts "\nTesting Static File Delivery"
		dc = File.join(Dir.pwd,'TC_Swiftiply')
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
			KillQueue << SwiftcoreTestSupport::create_process(:dir => 'TC_Swiftiply',
				:cmd => ["#{Ruby} -I../../src ../../bin/swiftiply -c test_serve_static_file.conf"])
			KillQueue << SwiftcoreTestSupport::create_process(:dir => 'TC_Swiftiply',
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

	def test_serve_static_file_from_cachedir
		puts "\nTesting Static File Delivery From Cachedir"
		dc = File.join(Dir.pwd,'TC_Swiftiply')
		dr = File.join(dc,'test_serve_static_file_from_cachedir')
		
		smallfile_name = "smallfile#{Time.now.to_i}"
		smallfile_path = File.join(dr,'public',smallfile_name)
		File.open(smallfile_path,'w') {|fh| fh.puts "alfalfa leafcutter bee"}
		DeleteQueue << smallfile_path
		
		smallfile_name2 = "smallfile2#{Time.now.to_i}"
		smallfile_path2 = File.join(dr,'public',smallfile_name2)
		File.open("#{smallfile_path2}.htm",'w') {|fh| fh.puts "alfalfa leafcutter bee"}
		DeleteQueue << "#{smallfile_path2}.htm"
		
		smallfile_name3 = "smallfile3#{Time.now.to_i}"
		smallfile_path3 = File.join(dr,'public',smallfile_name3)
		File.open("#{smallfile_path3}.cgi",'w') {|fh| fh.puts "alfalfa leafcutter bee"}
		DeleteQueue << "#{smallfile_path3}.cgi"
		
		bigfile_name = "bigfile#{Time.now.to_i}"
		bigfile_path = File.join(dr,'public',bigfile_name)
		File.open("#{bigfile_path}.html",'w+') {|fh| fh.write("#{'I am a duck. ' * 6}\n" * 1000)}
		DeleteQueue << "#{bigfile_path}.html"
		
		conf_file = File.join(dc,'test_serve_static_file_from_cachedir.conf')
		File.open(conf_file,'w+') do |fh|
			conf = ConfBase.dup
			conf['map'].first['docroot'] = 'test_serve_static_file_from_cachedir'
			conf['map'].first['cache_directory'] = 'public'
			conf['map'].first['cache_extensions'] = ['html','htm','cgi']
			fh.write conf.to_yaml
		end
		DeleteQueue << conf_file
		
		assert_nothing_raised("setup failed") do
			KillQueue << SwiftcoreTestSupport::create_process(:dir => 'TC_Swiftiply',
				:cmd => ["#{Ruby} -I../../src ../../bin/swiftiply -c test_serve_static_file_from_cachedir.conf"])
			KillQueue << SwiftcoreTestSupport::create_process(:dir => 'TC_Swiftiply',
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
		
		response = get_url('127.0.0.1',29998,smallfile_name2)
		assert_equal("alfalfa leafcutter bee\n",response.body)

		response = get_url('127.0.0.1',29998,smallfile_name3)
		assert_equal("alfalfa leafcutter bee\n",response.body)

	end
	
	# Test a vanilla proxy configuration with multiple verbs.
		
	def test_serve_normal_proxy
		puts "\nTesting Normal Proxy Action"
		dc = File.join(Dir.pwd,'TC_Swiftiply')
		dr = File.join(dc,'test_serve_normal_proxy')
		
		conf_file = File.join(dc,'test_serve_normal_proxy.conf')
		File.open(conf_file,'w+') {|fh| fh.write ConfBase.to_yaml}
		DeleteQueue << conf_file
		
		assert_nothing_raised("setup failed") do
			KillQueue << SwiftcoreTestSupport::create_process(:dir => 'TC_Swiftiply',
				:cmd => ["#{Ruby} -I../../src ../../bin/swiftiply -c test_serve_normal_proxy.conf"])
			KillQueue << SwiftcoreTestSupport::create_process(:dir => 'TC_Swiftiply',
				:cmd => ["#{Ruby} -I../../src ../../bin/echo_client 127.0.0.1:29999"])
			sleep 1
		end
		
		# Normal request
		response = get_url('127.0.0.1',29998,'/xyzzy')
		assert_equal("GET /xyzzy HTTP/1.1\r\nAccept: */*\r\nHost: 127.0.0.1:29998\r\n\r\n",response.body)
		
		# With query string params.
		response = get_url('127.0.0.1',29998,'/foo/bar/bam?Q=1234')
		assert_equal("GET /foo/bar/bam?Q=1234 HTTP/1.1\r\nAccept: */*\r\nHost: 127.0.0.1:29998\r\n\r\n",response.body)

		# POST request
		response = post_url('127.0.0.1',29998,'/xyzzy')
		assert_equal("POST /xyzzy HTTP/1.1\r\nAccept: */*\r\nHost: 127.0.0.1:29998\r\n\r\n",response.body)
		
		# And another verb; different verbs should be irrelevant
		response = delete_url('127.0.0.1',29998,'/xyzzy')
		assert_equal("DELETE /xyzzy HTTP/1.1\r\nAccept: */*\r\n",response.body[0..36])
		
		# A non-matching hostname, to trigger default handling
		response = get_url('localhost',29998,'/xyzzy')
		assert_equal("GET /xyzzy HTTP/1.1\r\nAccept: */*\r\nHost: localhost:29998\r\n\r\n",response.body)
	end
	
	# Test redeployable requests.
	
	def test_redeployable
		puts "\nTesting Redeployable Requests"
		dc = File.join(Dir.pwd,'TC_Swiftiply')
		dr = File.join(dc,'test_redeployable')
		
		conf_file = File.join(dc,'test_redeployable.conf')
		File.open(conf_file,'w+') do |fh|
			conf = ConfBase.dup
			conf['map'].first['redeployable'] = 'true'
			fh.write conf.to_yaml
		end
		DeleteQueue << conf_file
		
		secpid = nil
		assert_nothing_raised("setup failed") do
			KillQueue << SwiftcoreTestSupport::create_process(:dir => 'TC_Swiftiply',
				:cmd => ["#{Ruby} -I../../src ../../bin/swiftiply -c test_redeployable.conf"])
			secpid = SwiftcoreTestSupport::create_process(:dir => 'TC_Swiftiply',
				:cmd => ["#{Ruby} -I../../src slow_echo_client 127.0.0.1:29999"])
			sleep 1
		end
		
		response = nil
		urlthread = Thread.start {response = get_url('127.0.0.1',29998,'/slo_gin_fizz')}
		
		sleep 1

		Process.kill "SIGKILL",secpid
		secpid = nil
		assert_nothing_raised("setup failed") do

			secpid = SwiftcoreTestSupport::create_process(:dir => 'TC_Swiftiply',
				:cmd => ["#{Ruby} -I../../src slow_echo_client 127.0.0.1:29999"])
		end

		urlthread.join
		assert_equal("GET /slo_gin_fizz HTTP/1.1\r\nAccept: */*\r\nHost: 127.0.0.1:29998\r\n\r\n",response.body)
		
		sleep 1

		bigdata = 'x' * 69990
		bigdata << 'y' * 10
		response = nil

		# First, make sure that an ininterrupted request of this size is handled.
		
		assert_nothing_raised do
			response = post_url('127.0.0.1',29998,'/slo_gin_fizz',bigdata)
		end
		
		response.body =~ /(xxxxx*)/
		xs_len = $1.length
		response.body =~ /(yyyyy*)/
		ys_len = $1.length
		assert_equal(69990,xs_len)
		assert_equal(10,ys_len)
		
		# Now do the interrupted request.
		
		sleep 1
		
		urlthread = Thread.start {response = post_url('127.0.0.1',29998,'/slo_gin_fizz',bigdata)}

		sleep 1
				
		Process.kill "SIGKILL",secpid
		secpid = nil
		assert_nothing_raised("setup failed") do
			KillQueue << SwiftcoreTestSupport::create_process(:dir => 'TC_Swiftiply',
				:cmd => ["#{Ruby} -I../../src slow_echo_client 127.0.0.1:29999"])
		end

		assert_raise(EOFError) do
			# Net::HTTP should have blown up trying to get a result.  The
			# request was too big to be redeployed, so the connection should
			# have been dropped with nothing returned.
			urlthread.join
		end
	ensure
		Process.kill("SIGKILL",secpid) if secpid
	end

	def test_serve_normal_proxy_with_authentication
		puts "\nTesting Normal Proxy Action With Backend Authentication"
		dc = File.join(Dir.pwd,'TC_Swiftiply')
		dr = File.join(dc,'test_serve_normal_proxy_with_authentication')
		
		conf_file = File.join(dc,'test_serve_normal_proxy_with_authentication.conf')
		File.open(conf_file,'w+') do |fh|
			conf = ConfBase.dup
			conf['map'].first['key'] = 'abcdef1234'
			fh.write conf.to_yaml
		end
		DeleteQueue << conf_file
		
		assert_nothing_raised("setup failed") do
			KillQueue << SwiftcoreTestSupport::create_process(:dir => 'TC_Swiftiply',
				:cmd => ["#{Ruby} -I../../src ../../bin/swiftiply -c test_serve_normal_proxy_with_authentication.conf"])
			KillQueue << SwiftcoreTestSupport::create_process(:dir => 'TC_Swiftiply',
				:cmd => ["#{Ruby} -I../../src ../../bin/echo_client 127.0.0.1:29999 abcdef1234"])
			sleep 1
		end
		
		# Normal request
		response = get_url('127.0.0.1',29998,'/xyzzy')
		assert_equal("GET /xyzzy HTTP/1.1\r\nAccept: */*\r\nHost: 127.0.0.1:29998\r\n\r\n",response.body)
	end
	
	def test_sensible_error1
		puts "\n---------------------------------"
		puts "| Raising an error; this is OK! |"
		puts "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^"
		sleep 1

		dc = File.join(Dir.pwd,'TC_Swiftiply')
		dr = dc
		
		conf_file = File.join(dc,'test_sensible_error1.conf')
		File.open(conf_file,'w+') {|fh| fh.write ConfBase.to_yaml }
		DeleteQueue << conf_file
		
		assert_nothing_raised("setup failed") do
			KillQueue << SwiftcoreTestSupport::create_process(:dir => 'TC_Swiftiply',
				:cmd => ["#{Ruby} -I../../src ../../bin/swiftiply -c test_sensible_error1.conf"])
			sleep 1
			KillQueue << SwiftcoreTestSupport::create_process(:dir => 'TC_Swiftiply',
				:cmd => ["#{Ruby} -I../../src ../../bin/swiftiply -c test_sensible_error1.conf"])
			sleep 1
		end	
	end
end
