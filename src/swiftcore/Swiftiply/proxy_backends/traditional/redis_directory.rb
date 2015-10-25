require 'redis'

# Lookup directory information from redis repo.
module Swiftcore
	module Swiftiply
		module Proxies
			class TraditionalRedisDirectory
				# servers:
				#   host: HOSTNAME (defaults to 127.0.0.1)
				#   port: PORT (defaults to 6379)
				#   db: Redis DB (defaults to 0)
				#   password: (defaults to none)

				def self.config(conf,new_config)
					redis_config = {}
					(conf[Cservers] || {}).each {|k,v| redis_config[k.intern] = v}
					@redis = Redis.new(redis_config)
				rescue Exception => e
					puts "Failed to connect to the Redis server using these parameters: #{redis_config.to_yaml}"
					raise e
				end

				def self.redis
					@redis
				end

				def self.backend_class
					@backend_class
				end

				def self.backend_class=(val)
					@backend_class = val
				end

				def initialize(*args)
					@redis = self.class.redis
					@backend_class = self.class.backend_class
				end

				def pop
					key = ProxyBag.current_client_name
					data = @redis.rpoplpush(key,"#{key}.inuse")
					if data
						host, port = data.split(C_colon,2)
						host ||= C_localhost
						port ||= C80
						EventMachine.connect(host,port,@backend_class,host,port)
					else
						false
					end
				rescue Exception => e
					false
				end

				def unshift(val);end

				def push(val);end

				def delete(val);end

				def requeue(key, host, port)
					hp = "#{host}:#{port}"
					@redis.lrem("#{key}.inuse", 1, hp)
					@redis.lpush(key, hp)
				rescue Exception => e
					# Use an EM timer to reschedule the requeue just a very short time into the future?
					# The only time this will occur is if the redis server goes away.
				end

				def status
					r = ''
					keys = @redis.keys('*')
					r << "#{@redis.dbsize} -- #{keys.to_yaml}"
					keys.each do |k|
						r << "  #{k}(#{@redis.llen(k)})\n    #{@redis.lrange(k,0,@redis.llen(k)).to_yaml}"
					end
					r
				rescue Exception => e
					r << self.inspect
					r << e
					r << e.backtrace.to_yaml
					r
				end
			end
		end
	end
end
