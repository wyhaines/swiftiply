# Swiftiply v1.0.0 (http://github.com/wyhaines/swiftiply)

Swiftiply is a backend agnostic clustering proxy for web applications that is
specifically designed to support HTTP traffic from web frameworks. It is a targeted
proxy, intended specifically for use in front of web frameworks, and is not a
general purpose proxy.

What it is, though, is a very fast, narrowly targeted clustering proxy, with the
current implementation being written in Ruby.

Swiftiply works differently from a traditional proxy. In Swiftiply, the
backend processes are clients of the Swiftiply server -- they make persistent
socket connections to Swiftiply. One of the major advantages to this
architecture is that it allows one to start or stop backend processes at will,
with no configuration of the proxy. The proxy always knows exactly what resources
it has available to handle a given request. The obvious disadvantage is that this is
not behavior that web applications typically expect.

Swiftiply was originally written in an era when Mongrel was the preferred deployment
method for most Ruby frameworks. Swiftiply includes a version of Mongrel(found in
swiftcore/swiftiplied_mongrel.rb) that has been modified to work as a swiftiply client.
This should be transparent to any existing Mongrel handlers, allowing them all to with
Swiftiply.

Swiftiply also provides a traditional proxy model, allowing it to be used as a proxy
in front of any web application.

TODO: Provide an implementation of a swiftiply access proxy. This is a Swiftiply
TODO: "client" that maintains N connections into Swiftiply, but that operates as
TODO: a traditional proxy on the web application facing side. This lets an individual
TODO: server modulate the total number of connections that it is willing to handle
TODO: simultaneously, while not requiring the applications themselves to know anything
TODO: about it.

CONFIGURATION

Swiftiply takes a single configuration file which defines for it where it
should listen for incoming connections, whether it should daemonize itself,
and then provides a map of incoming domain names and the address/port to
proxy that traffic to. That outgoing address/port is where the backends for
that site will connect to.

Here's an example:

cluster_address: swiftcore.org
cluster_port: 80
daemonize: true
map:
 - incoming:
  - swiftcore.org
  - www.swiftcore.org
  outgoing: 127.0.0.1:30000
  default: true
 - incoming: iowa.swiftcore.org
  outgoing: 127.0.0.1:30010
 - incoming: analogger.swiftcore.org
  outgoing: 127.0.0.1:30020
 - incoming:
  - swiftiply.com
  - www.swiftiply.com
  - swiftiply.swiftcore.org
  outgoing: 127.0.0.1:30030
