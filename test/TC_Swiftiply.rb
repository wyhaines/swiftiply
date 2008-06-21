require 'test/unit'
require 'external/test_support'
SwiftcoreTestSupport.set_src_dir
require 'rbconfig'
require 'net/http'
require 'net/https'
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
epoll: true
descriptors: 20000
defaults:
  logger:
    type: stderror
    log_level: 0
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

	def get_url_https(hostname, port, url)
		http = Net::HTTP.new(hostname, port)
		http.use_ssl = true
		http.start {http.request_get(url)}
	end
	
	def get_url_1_0(hostname, port, url)
		Net::HTTP.start(hostname,port) {|http| http.instance_variable_set('@curr_http_version','1.0');  http.get(url)}
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
			 File.delete f if f and FileTest.exist?(f)
		end
		 
		while p = KillQueue.pop do
			Process.kill("SIGKILL",p) if p
			Process.wait p if p
		end
	end

	#####	
	# Test serving a small file (no chunked encoding) and a large file (chunked
	# encoding).
	#####
	
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
		conf = YAML.load(ConfBase.to_yaml)

		File.open(conf_file,'w+') {|fh| fh.write conf.to_yaml}
		DeleteQueue << conf_file
		
		assert_nothing_raised("setup failed") do
			KillQueue << SwiftcoreTestSupport::create_process(:dir => 'TC_Swiftiply',
				:cmd => ["#{Ruby} -I../../src ../../bin/swiftiply -c test_serve_static_file.conf"])
			KillQueue << SwiftcoreTestSupport::create_process(:dir => 'TC_Swiftiply',
				:cmd => ["#{Ruby} -I../../src ../bin/echo_client 127.0.0.1:29999"])
			# Make sure everything has time to start, connect, etc... before
			# the tests are executed.
			sleep 1
		end
	
		response = get_url('127.0.0.1',29998,smallfile_name)
		small_etag = response['ETag']
		assert_equal("alfalfa leafcutter bee\n",response.body)
		
		response = get_url('127.0.0.1',29998,bigfile_name)
		big_etag = response['ETag']
		assert_equal("I am a duck. I am a duck. ",response.body[0..25])
		assert_equal("I am a duck. \n",response.body[-14..-1])
		assert_equal(79000,response.body.length)
		
		response = get_url_1_0('127.0.0.1',29998,bigfile_name)
		assert_equal("I am a duck. I am a duck. ",response.body[0..25])
		assert_equal("I am a duck. \n",response.body[-14..-1])
		assert_equal(79000,response.body.length)
		
		# Hit it a bunch of times.
		
		ab = `which ab`.chomp
		unless ab == ''
			r = `#{ab} -n 100000 -c 25 http://127.0.0.1:29998/#{smallfile_name}`
			r =~ /^(Requests per second.*)$/
			puts "10k 22 byte files, concurrency of 25\n#{$1}\n"
		end
		unless ab == ''
			r = `#{ab} -n 100000 -c 25 -H 'If-None-Match: #{small_etag}' http://127.0.0.1:29998/#{smallfile_name}`
			r =~ /^(Requests per second.*)$/
			puts "10k 22 byte files with etag, concurrency of 25\n#{$1}\n"
		end
		unless ab == ''
			r = `#{ab} -n 100000 -i -c 25 http://127.0.0.1:29998/#{smallfile_name}`
			r =~ /^(Requests per second.*)$/
			puts "10k HEAD requests, concurrency of 25\n#{$1}\n"
		end
		unless ab == ''
			r = `#{ab} -n 20000 -c 25 http://127.0.0.1:29998/#{bigfile_name}`
			r =~ /^(Requests per second.*)$/
			puts "10k 78000 byte files, concurrency of 25\n#{$1}\n"
		end
		unless ab == ''
			r = `#{ab} -n 20000 -c 25 -H 'If-None-Match: #{big_etag}' http://127.0.0.1:29998/#{bigfile_name}`
			r =~ /^(Requests per second.*)$/
			puts "10k 78000 byte files with etag, concurrency of 25\n#{$1}\n"
		end
		
		# And it is still correct?
		response = get_url('127.0.0.1',29998,smallfile_name)
		assert_equal("alfalfa leafcutter bee\n",response.body)
	end

	def test_serve_static_file_caches
		puts "\nTesting caches"
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
		conf = YAML.load(ConfBase.to_yaml)
		conf['logger'] ||= {}
		conf['logger']['log_level'] = 3
		conf['map'][0]['file_cache'] = {}
		conf['map'][0]['file_cache']['window'] = 5
		conf['map'][0]['logger'] = {}
		conf['map'][0]['logger']['log_level'] = 3
		conf['map'][0]['logger']['type'] = 'stderror'
		
		File.open(conf_file,'w+') {|fh| fh.write conf.to_yaml}
		DeleteQueue << conf_file
		
		assert_nothing_raised("setup failed") do
			KillQueue << SwiftcoreTestSupport::create_process(:dir => 'TC_Swiftiply',
				:cmd => ["#{Ruby} -I../../src ../../bin/swiftiply -c test_serve_static_file.conf"])
			KillQueue << SwiftcoreTestSupport::create_process(:dir => 'TC_Swiftiply',
				:cmd => ["#{Ruby} -I../../src ../bin/echo_client 127.0.0.1:29999"])
			# Make sure everything has time to start, connect, etc... before
			# the tests are executed.
			sleep 1
		end
	
		response = get_url('127.0.0.1',29998,smallfile_name)
		small_etag = response['ETag']
		assert_equal("alfalfa leafcutter bee\n",response.body)
		File.delete smallfile_path
		
		response = get_url('127.0.0.1',29998,bigfile_name)
		big_etag = response['ETag']
		assert_equal("I am a duck. I am a duck. ",response.body[0..25])
		assert_equal("I am a duck. \n",response.body[-14..-1])
		assert_equal(79000,response.body.length)
		
		sleep 4

		File.open(smallfile_path,'w') {|fh| fh.puts "alfalfa leafcutter bee too"}
		
		response = get_url('127.0.0.1',29998,smallfile_name)
		small_etag = response['ETag']
		assert_equal("alfalfa leafcutter bee too\n",response.body)
	end
	
	#####
	# Test the x-sendfile header support.
	# Big and small files that do exist.
	#####
	
	def test_serve_static_file_xsendfile
		puts "\nTesting Static File Delivery via X-Sendfile"
		dc = File.join(Dir.pwd,'TC_Swiftiply')
		dr = File.join(dc,'test_serve_static_file_xsendfile')
		
		smallfile1_name = "smallfile1#{Time.now.to_i}"
		smallfile1_path = File.join(dr,'pub',smallfile1_name)
		File.open(smallfile1_path,'w') {|fh| fh.puts "alfalfa leafcutter bee"}
		DeleteQueue << smallfile1_path
		
		smallfile2_name = "smallfile2#{Time.now.to_i}"
		smallfile2_path = File.join(dr,'priv',smallfile2_name)
		File.open(smallfile2_path,'w') {|fh| fh.puts "alfalfa leafcutter bee"}
		DeleteQueue << smallfile2_path
		
		bigfile1_name = "bigfile1#{Time.now.to_i}"
		bigfile1_path = File.join(dr,'pub',bigfile1_name)
		File.open(bigfile1_path,'w+') {|fh| fh.write("#{'I am a duck. ' * 6}\n" * 1000)}
		DeleteQueue << bigfile1_path
		
		bigfile2_name = "bigfile2#{Time.now.to_i}"
		bigfile2_path = File.join(dr,'priv',bigfile2_name)
		File.open(bigfile2_path,'w+') {|fh| fh.write("#{'I am a duck. ' * 6}\n" * 1000)}
		DeleteQueue << bigfile2_path
		
		conf = YAML.load(ConfBase.to_yaml)
		conf['map'].first['docroot'] = "#{@@testdir}/TC_Swiftiply/test_serve_static_file_xsendfile/pub"
		conf['map'].first['sendfileroot'] = "#{@@testdir}/TC_Swiftiply/test_serve_static_file_xsendfile/priv"
		
		conf_file = File.join(dc,'test_serve_static_file_xsendfile.conf')
		File.open(conf_file,'w+') {|fh| fh.write conf.to_yaml}
		DeleteQueue << conf_file
		
		assert_nothing_raised("setup failed") do
			KillQueue << SwiftcoreTestSupport::create_process(:dir => 'TC_Swiftiply',
				:cmd => ["#{Ruby} -I../../src ../../bin/swiftiply -c test_serve_static_file_xsendfile.conf"])
			KillQueue << SwiftcoreTestSupport::create_process(:dir => 'TC_Swiftiply',
				:cmd => ["#{Ruby} -I../../src #{@@testdir}/TC_Swiftiply/test_serve_static_file_xsendfile/sendfile_client.rb 127.0.0.1:29999"])
			# Make sure everything has time to start, connect, etc... before
			# the tests are executed.
			sleep 1
		end

		response = get_url('127.0.0.1',29998,smallfile1_name)
		small_etag = response['ETag']
		assert_equal("alfalfa leafcutter bee\n",response.body)

		response = get_url('127.0.0.1',29998,smallfile2_name)
		small_etag = response['ETag']
		assert_equal("alfalfa leafcutter bee\n",response.body)		
				
		response = get_url('127.0.0.1',29998,bigfile1_name)
		big_etag = response['ETag']
		assert_equal("I am a duck. I am a duck. ",response.body[0..25])
		assert_equal("I am a duck. \n",response.body[-14..-1])
		assert_equal(79000,response.body.length)
		
		response = get_url_1_0('127.0.0.1',29998,bigfile1_name)
		assert_equal("I am a duck. I am a duck. ",response.body[0..25])
		assert_equal("I am a duck. \n",response.body[-14..-1])
		assert_equal(79000,response.body.length)
		
		response = get_url('127.0.0.1',29998,bigfile2_name)
		big_etag = response['ETag']
		assert_equal("I am a duck. I am a duck. ",response.body[0..25])
		assert_equal("I am a duck. \n",response.body[-14..-1])
		assert_equal(79000,response.body.length)
		
		response = get_url_1_0('127.0.0.1',29998,bigfile2_name)
		assert_equal("I am a duck. I am a duck. ",response.body[0..25])
		assert_equal("I am a duck. \n",response.body[-14..-1])
		assert_equal(79000,response.body.length)
		
		response = get_url('127.0.0.1',29998,'this_isnt_there')
		assert_equal("this_isnt_there",response.to_hash['x-sendfile'].first)
		assert(response.body =~ /Doing X-Sendfile to this_isnt_there/)
	end
	
	#####
	# Test x-sendfile handling for a file that doesn't exist.
	#####
	
	def test_serve_static_file_xsendfile2
		dc = File.join(Dir.pwd,'TC_Swiftiply')
		dr = File.join(dc,'test_serve_static_file_xsendfile')
		
		smallfile2_name = "smallfile2#{Time.now.to_i}"
		smallfile2_path = File.join(dr,'priv',smallfile2_name)
		File.open(smallfile2_path,'w') {|fh| fh.puts "alfalfa leafcutter bee"}
		DeleteQueue << smallfile2_path
		
		conf = YAML.load(ConfBase.to_yaml)
		conf['map'].first['docroot'] = "#{@@testdir}/TC_Swiftiply/test_serve_static_file_xsendfile/pub"
		conf['map'].first['sendfileroot'] = "#{@@testdir}/TC_Swiftiply/test_serve_static_file_xsendfile/priv"
		conf['map'].first['enable_sendfile_404'] = 'true'
		
		conf_file = File.join(dc,'test_serve_static_file_xsendfile.conf')
		File.open(conf_file,'w+') {|fh| fh.write conf.to_yaml}
		DeleteQueue << conf_file
		
		assert_nothing_raised("setup failed") do
			KillQueue << SwiftcoreTestSupport::create_process(:dir => 'TC_Swiftiply',
				:cmd => ["#{Ruby} -I../../src ../../bin/swiftiply -c test_serve_static_file_xsendfile.conf"])
			KillQueue << SwiftcoreTestSupport::create_process(:dir => 'TC_Swiftiply',
				:cmd => ["#{Ruby} -I../../src #{@@testdir}/TC_Swiftiply/test_serve_static_file_xsendfile/sendfile_client.rb 127.0.0.1:29999"])
			# Make sure everything has time to start, connect, etc... before
			# the tests are executed.
			sleep 1
		end

		response = get_url('127.0.0.1',29998,smallfile2_name)
		small_etag = response['ETag']
		assert_equal("alfalfa leafcutter bee\n",response.body)		
		
		response = get_url('127.0.0.1',29998,'this_isnt_there')
		assert(Net::HTTPNotFound === response)
		assert(response.body =~ /this_isnt_there could not be found/)
	end	

	#####
	# Setup an SSL connection and test a couple requests that use SSL.
	#####
	
	def test_ssl
		puts "\nTesting SSL"
		dc = File.join(Dir.pwd,'TC_Swiftiply')
		dr = File.join(dc,'test_ssl')
		
		# Before proceding with testing, the code here should determine if the
		# EventMachine installed on the system has SSL support built.  If it
		# does not, don't run the tests.  Instead, report on this fact and
		# point them at some information about how to reinstall EM so that it
		# does support ssl.
		
		print "Testing whether SSL is available..."
		Thread.new do
			sleep 1
			print '..'
			STDOUT.flush
			sleep 1
			print '..'
			STDOUT.flush
			sleep 1
			print '..'
			STDOUT.flush
			sleep 1
			print '..'
			STDOUT.flush
			http = Net::HTTP.new('127.0.0.1',3333)
			http.use_ssl
			http.start {http.request_get('/')}
			puts '..'
		end
		
		ssl_available = system("#{Ruby} TC_Swiftiply/test_ssl/bin/validate_ssl_capability.rb")
		
		if ssl_available
			puts "  SSL is available.  Continuing."
		else
			puts "\n\n\n!!! Notice !!!"
			puts "\nSSL does not appear to be available in your version of EventMachine."
			puts "This is probably because it could not find the openssl libraries while compiling."
			puts "If you do not have these libraries, install them, then rebuild/reinstall"
			puts "EventMachine.  If you do have them, you should report this as a bug to the"
			puts "EventMachine project, with details about your system, library locations, etc...,"
			puts "so that they can fix the build process."
			puts "\nSkipping SSL tests."
			return
		end
		
		smallfile_name = "smallfile#{Time.now.to_i}"
		smallfile_path = File.join(dr,'pub',smallfile_name)
		File.open(smallfile_path,'w') {|fh| fh.puts "alfalfa leafcutter bee"}
		DeleteQueue << smallfile_path
		
		conf = YAML.load(ConfBase.to_yaml)
		conf['map'].first['docroot'] = "#{@@testdir}/TC_Swiftiply/test_ssl/pub"
		conf['ssl'] = []
		conf['ssl'] << {'at' => '127.0.0.1:29998', 'certfile' => "#{@@testdir}/TC_Swiftiply/test_ssl/test.cert", 'keyfile' => "#{@@testdir}/TC_Swiftiply/test_ssl/test.key"}
		conf['map'].first['sendfileroot'] = "#{@@testdir}/TC_Swiftiply/test_serve_static_file_xsendfile/priv"
		conf['map'].first['enable_sendfile_404'] = 'true'
		
		conf_file = File.join(dc,'test_ssl.conf')
		File.open(conf_file,'w+') {|fh| fh.write conf.to_yaml}
		DeleteQueue << conf_file
		
		assert_nothing_raised("setup failed") do
			KillQueue << SwiftcoreTestSupport::create_process(:dir => 'TC_Swiftiply',
				:cmd => ["#{Ruby} -I../../src ../../bin/swiftiply -c test_ssl.conf"])
			KillQueue << SwiftcoreTestSupport::create_process(:dir => 'TC_Swiftiply',
				:cmd => ["#{Ruby} -I../../src #{@@testdir}/TC_Swiftiply/test_serve_static_file_xsendfile/sendfile_client.rb 127.0.0.1:29999"])
			# Make sure everything has time to start, connect, etc... before
			# the tests are executed.
			sleep 1
		end

		response = get_url_https('127.0.0.1',29998,smallfile_name)
		small_etag = response['ETag']
		assert_equal("alfalfa leafcutter bee\n",response.body)		
		
		response = get_url_https('127.0.0.1',29998,'this_isnt_there')
		assert(Net::HTTPNotFound === response)
		assert(response.body =~ /this_isnt_there could not be found/)
		
		#ab = `which ab`.chomp
		#unless ab == ''
		#	r = `#{ab} -n 20000 -c 25 https://127.0.0.1:29998/#{smallfile_name}`
		#	r =~ /^(Requests per second.*)$/
		#	puts "10k 22 byte files through SSL, concurrency of 25\n#{$1}\n"
		#end
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
			conf = YAML.load(ConfBase.to_yaml)
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
				:cmd => ["#{Ruby} -I../../src ../bin/echo_client 127.0.0.1:29999"])
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
				:cmd => ["#{Ruby} -I../../src ../bin/echo_client 127.0.0.1:29999"])
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
		
		# A very large url
		u = '/abcdefghijklmnopqrstuvwxyz'*100
		response = get_url('127.0.0.1',29998,u)
		assert_equal("GET #{u} HTTP/1.1\r\nAccept: */*\r\nHost: 127.0.0.1:29998\r\n\r\n",response.body)
	end
	
	# Test redeployable requests.
	
	def test_redeployable
		puts "\nTesting Redeployable Requests"
		dc = File.join(Dir.pwd,'TC_Swiftiply')
		dr = File.join(dc,'test_redeployable')
		
		conf_file = File.join(dc,'test_redeployable.conf')
		File.open(conf_file,'w+') do |fh|
			conf = YAML.load(ConfBase.to_yaml)
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
			conf = YAML.load(ConfBase.to_yaml)
			conf['map'].first['key'] = 'abcdef1234'
			fh.write conf.to_yaml
		end
		DeleteQueue << conf_file
		
		assert_nothing_raised("setup failed") do
			KillQueue << SwiftcoreTestSupport::create_process(:dir => 'TC_Swiftiply',
				:cmd => ["#{Ruby} -I../../src ../../bin/swiftiply -c test_serve_normal_proxy_with_authentication.conf"])
			KillQueue << SwiftcoreTestSupport::create_process(:dir => 'TC_Swiftiply',
				:cmd => ["#{Ruby} -I../../src ../bin/echo_client 127.0.0.1:29999 abcdef1234"])
			sleep 1
		end
		
		# Normal request
		response = get_url('127.0.0.1',29998,'/xyzzy')
		assert_equal("GET /xyzzy HTTP/1.1\r\nAccept: */*\r\nHost: 127.0.0.1:29998\r\n\r\n",response.body)
	end

	def test_http_404_error
		puts "\nTesting Request for Unknown Host, No Default (404 Error situation)"
		dc = File.join(Dir.pwd,'TC_Swiftiply')
		dr = dc
		
		conf_file = File.join(dc,'test_404_error.conf')
		File.open(conf_file,'w+') do |fh|
			conf = YAML.load(ConfBase.to_yaml)
			conf['map'].first['default'] = false
			conf['map'].first['incoming'] = ["localhost"]
			fh.write conf.to_yaml
		end
		
		DeleteQueue << conf_file
		
		assert_nothing_raised("setup failed") do
			KillQueue << SwiftcoreTestSupport::create_process(:dir => 'TC_Swiftiply',
				:cmd => ["#{Ruby} -I../../src ../../bin/swiftiply -c test_404_error.conf"])
			KillQueue << SwiftcoreTestSupport::create_process(:dir => 'TC_Swiftiply',
				:cmd => ["#{Ruby} -I../../src ../bin/echo_client 127.0.0.1:29999 abcdef1234"])
			sleep 1
		end
		
		response = get_url('127.0.0.1',29998,'/xyzzy')
		assert_equal("404",response.header.code)
	end

	def test_http_503_error
		puts "\nTesting Request when server unavailable (503 error situation)"
		dc = File.join(Dir.pwd,'TC_Swiftiply')
		dr = dc
		
		conf_file = File.join(dc,'test_404_error.conf')
		File.open(conf_file,'w+') do |fh|
			conf = YAML.load(ConfBase.to_yaml)
			fh.write conf.to_yaml
		end
		
		DeleteQueue << conf_file
		
		assert_nothing_raised("setup failed") do
			KillQueue << SwiftcoreTestSupport::create_process(:dir => 'TC_Swiftiply',
				:cmd => ["#{Ruby} -I../../src ../../bin/swiftiply -c test_404_error.conf"])
			sleep 1
		end
		
		response = get_url('127.0.0.1',29998,'/xyzzy')
		assert_equal("503",response.header.code)
	end

	def test_sensible_error1
		puts "\n---------------------------------------------------------------"
		puts "|                Raising an error; this is OK!                |"
		puts "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^"
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
		puts "\n---------------------------------------------------------------"
		puts "| The above exception was just a test.  It should have started  |"
		puts "| with: \"The listener on 127.0.0.1:29998 could not be started.\" |"
		puts "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^"
	end
	
	def test_evented_mongrel
		puts "\nTesting Evented Mongrel"
		
		assert_nothing_raised("setup failed") do
			KillQueue << SwiftcoreTestSupport::create_process(:dir => File.join('TC_Swiftiply','mongrel'),
				:cmd => ["#{Ruby} -I../../../src evented_hello.rb"])
			KillQueue << SwiftcoreTestSupport::create_process(:dir => File.join('TC_Swiftiply','mongrel'),
				:cmd => ["#{Ruby} -I../../../src threaded_hello.rb"])
		end
		
		sleep 1
		
		response = get_url('127.0.0.1',29998,'/hello')
		assert_equal("hello!\n",response.body)
		
		response = get_url('127.0.0.1',29998,'/dir')
		assert_equal("<html><head><title>Directory Listing",response.body[0..35])
		
		ab = `which ab`.chomp
		unless ab == ''
			puts "\nThreaded Mongrel..."
			rt = `#{ab} -n 10000 -c 25 http://127.0.0.1:29997/hello`
			rt =~ /^(Requests per second.*)$/
			rts = $1
			puts "\nEvented Mongrel..."
			re = `#{ab} -n 10000 -c 25 http://127.0.0.1:29998/hello`
			re =~ /^(Requests per second.*)$/
			res = $1
			puts "\nThreaded Mongrel, no proxies, concurrency of 25\n#{rts}"
			puts "Evented Mongrel, no proxies, concurrency of 25\n#{res}"
			sleep 1
		end
	end
	
	def test_swiftiplied_mongrel
		puts "\nTesting Swiftiplied Mongrel"

		dc = File.join(Dir.pwd,'TC_Swiftiply')
		dr = File.join(dc,'test_serve_normal_proxy')
		
		conf_file = File.join(dc,'test_serve_mongrel.conf')
		File.open(conf_file,'w+') {|fh| fh.write ConfBase.to_yaml}
		DeleteQueue << conf_file
		
		kq = []
		assert_nothing_raised("setup failed") do
			KillQueue << SwiftcoreTestSupport::create_process(:dir => 'TC_Swiftiply',
				:cmd => ["#{Ruby} -I../../src ../../bin/swiftiply -c test_serve_mongrel.conf"])
			sleep 1
			KillQueue << SwiftcoreTestSupport::create_process(:dir => File.join('TC_Swiftiply','mongrel'),
				:cmd => ["#{Ruby} -I../../../src swiftiplied_hello.rb"])
			KillQueue << SwiftcoreTestSupport::create_process(:dir => File.join('TC_Swiftiply','mongrel'),
				:cmd => ["#{Ruby} -I../../../src swiftiplied_hello.rb"])
			sleep 1
		end
		
		response = get_url('127.0.0.1',29998,'/hello')
		assert_equal("hello!\n",response.body)
		
		response = get_url('127.0.0.1',29998,'/dir')
		assert_equal("<html><head><title>Directory Listing",response.body[0..35])
		
		ab = `which ab`.chomp
		unless ab == ''
			#r = `#{ab} -n 10000 -c 250 http://127.0.0.1:29998/hello`
			r = `#{ab} -n 100000 -c 25 http://127.0.0.1:29998/hello`
			r =~ /^(Requests per second.*)$/
			puts "Swiftiply -> Swiftiplied Mongrel, concurrency of 25\n#{$1}"
		end
	end
	
	def test_HUP
		puts "\nTesting HUP handling"
		dc = File.join(Dir.pwd,'TC_Swiftiply')
		dr = File.join(dc,'test_serve_static_file')
		
		conf_file = File.join(dc,'test_HUP.conf')
		File.open(conf_file,'w+') do |fh|
			conf = YAML.load(ConfBase.to_yaml)
			conf['map'].first.delete('docroot')
			fh.write conf.to_yaml
		end

		DeleteQueue << conf_file
		
		smallfile_name = "xyzzy"
		smallfile_path = File.join(dr,smallfile_name)
		File.open(smallfile_path,'w') {|fh| fh.puts "alfalfa leafcutter bee"}
		DeleteQueue << smallfile_path
		
		swiftiply_pid = nil
		assert_nothing_raised("setup failed") do
			KillQueue << swiftiply_pid = SwiftcoreTestSupport::create_process(:dir => 'TC_Swiftiply',
				:cmd => ["#{Ruby} -I../../src ../../bin/swiftiply -c test_HUP.conf"])
			KillQueue << SwiftcoreTestSupport::create_process(:dir => 'TC_Swiftiply',
				:cmd => ["#{Ruby} -I../../src ../bin/echo_client 127.0.0.1:29999"])
			sleep 1
		end

		# Normal request for a sanity check.
		response = get_url('127.0.0.1',29998,'/xyzzy')
		assert_equal("GET /xyzzy HTTP/1.1\r\nAccept: */*\r\nHost: 127.0.0.1:29998\r\n\r\n",response.body)
		
		# Now rewrite the conf file to be a little different.
		File.open(conf_file,'w+') {|fh| fh.write ConfBase.to_yaml }
		
		# Reload the config
		Process.kill 'SIGHUP',swiftiply_pid
		
		# This request should pull the file from the docroot, since it the
		# docroot was not deleted from the config that was just read.
		response = get_url('127.0.0.1',29998,'/xyzzy')

		assert_equal("alfalfa leafcutter bee\n",response.body)
	end
	
end
