class Hash

	# Hash#merge doesn't work right if any of the values in the hash are themselves
	# hashes.  This creates frowns on my normally smiling face.  This method
	# will walk a hash, merging it, while preserving default_proc's that may
	# exist on the hashes involved.  The code was adopted from IOWA.  It's also
	# quite likely that it sucks.  I wrote it years ago, and have left it alone
	# since then.  If you need similar functionality in your code somewhere,
	# though, feel free to use this.  If you make it better, I'd appreciate it
	# if you would send me your patches, though.
	
	def rmerge!(h)
		h.each do |k,v|
			if v.kind_of?(::Hash)
				if self[k].kind_of?(::Hash)
					unless self[k].respond_to?(:rmerge!)
						if dp = self[k].default_proc
							self[k] = Hash.new {|h,k| dp.call(h,k)}.rmerge!(self[k])
						else
							osk = self[k]
							self[k] = Hash.new
							self[k].rmerge!(osk)
						end
					end
					self[k].rmerge!(v)
				else
					if self.default_proc
						self.delete k
						self[k]
					end
					unless self[k].kind_of?(::Hash)
						self.delete k
						self[k] = Hash.new
					end
					self[k].rmerge!(v)
				end
			else
				self[k] = v
			end
		end
	end
	
end