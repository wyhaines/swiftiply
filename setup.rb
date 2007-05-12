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

	translate(:lib, 'src/' => '')
	translate(:bin, 'bin/' => '')
	lib(*Dir["src/swiftcore/**/*.rb"])
	lib("src/swiftcore/evented_mongrel.rb")
	lib("src/swiftcore/swiftiplied_mongrel.rb")
	ri(*Dir["src/swiftcore/**/*.rb"])
	bin "bin/swiftiply"
	bin "bin/swiftiply_mongrel_rails"
	#File.rename("#{Config::CONFIG["bindir"]}/mongrel_rails","#{Config::CONFIG["bindir"]}/mongrel_rails.orig")
	bin "bin/mongrel_rails"

	# Install Ramaze libs if Ramaze is installed.
	
	begin
		require 'ramaze'
		lib("src/ramaze/adapter/evented_mongrel.rb")
		lib("src/ramaze/adapter/swiftiplied_mongrel.rb")
	rescue LoadError
		# Ramaze not installed
	end

#	unit_test "test/TC_Swiftiply.rb"
	
	true
}
