#!ruby

basedir = File.dirname(__FILE__)
$:.push(basedir)
require 'external/package'
require 'rbconfig'
begin
	require 'rubygems'
rescue LoadError
end

Dir.chdir(basedir)
Package.setup("1.0") {
	name "Swiftcore Swiftiply"

	build_ext "fastfilereader"
	translate(:ext, 'ext/fastfilereader/' => '/')
	#translate(:ext, 'ext/http11/' => 'iowa/')

	ext "ext/fastfilereader/fastfilereaderext.so"
	ext "ext/fastfilereader/fastfilereaderext.bundle"
	
	build_ext "deque"
	translate(:ext, 'ext/deque/' => '/swiftcore/')
	ext "ext/deque/deque.so"
	ext "ext/deque/deque.bundle"

	build_ext "splaytree"
	translate(:ext, 'ext/splaytree/' => '/swiftcore/')
	ext "ext/splaytree/splaytreemap.so"
	ext "ext/splaytree/splaytreemap.bundle"

	translate(:lib, 'src/' => '')
	translate(:bin, 'bin/' => '')
	lib(*Dir["src/swiftcore/**/*.rb"])
	lib("src/swiftcore/evented_mongrel.rb")
	lib("src/swiftcore/swiftiplied_mongrel.rb")
	lib(*Dir["src/ramaze/adapter/*.rb"])
	ri(*Dir["src/swiftcore/**/*.rb"])
	bin "bin/swiftiply"
	bin "bin/swiftiply_mongrel_rails"
	#File.rename("#{Config::CONFIG["bindir"]}/mongrel_rails","#{Config::CONFIG["bindir"]}/mongrel_rails.orig")
	bin "bin/mongrel_rails"

	unit_test "test/TC_ProxyBag.rb"
	unit_test "test/TC_Swiftiply.rb"
	unit_test "test/TC_Deque.rb"
	true
}
