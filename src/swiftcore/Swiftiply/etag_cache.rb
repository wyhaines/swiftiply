begin
  load_attempted ||= false
  require 'swiftcore/Swiftiply/cache_base'
rescue LoadError => e
  if !load_attempted
    load_attempted = true
    begin
      require 'rubygems'
    rescue LoadError
      raise e
    end
    retry
  end
  raise e
end

module Swiftcore
  module Swiftiply

    ReadMode = 'r:ASCII-8BIT'.freeze

    class EtagCache < CacheBase

      def etag_mtime(path)
        self[path] || self[path] = self.calculate_etag(path)
      end

      def etag(path)
        self[path] && self[path].first || (self[path] = self.calculate_etag(path)).first
      end

      def mtime(path)
        self[path] && self[path].last || (self[path] = self.calculate_etag(path)).last
      end

      def verify(path)
        if et = self[path] and File.exist?(path)
          mt = File.mtime(path)
          if mt == et.last
            true
          else
            (self[path] = self.calculate_etag(path)).first
          end
        else
          false
        end
      end

      def calculate_etag(path)
        stats = File.stat(path)
        mtime = stats.mtime
        # Making an etag off of modification time + size is a lot faster than
        # calculating a hash for the whole file, and is adequate for the
        # purposes of an etag.
        etag = "#{mtime.to_i.to_s(16)}-#{stats.size.to_s(16)}"

        unless self[path]
          add_to_verification_queue(path)
          ProxyBag.log(owner_hash).log('info',"Adding ETag #{etag} for #{path} to ETag cache") if ProxyBag.level(owner_hash) > 2
        end
        [etag,mtime]
      rescue Exception
        # Pulling file stats failed; probably a race condition and file was deleted, but....there should be checks.
      end
    end
  end
end
