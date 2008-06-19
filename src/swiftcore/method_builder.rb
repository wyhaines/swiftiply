# Mixin to allow dynamic construction of instance methods.

module MethodBuilder
	def method_builder(method_name, method_args, chunks, callback_args = [])
		if Array === method_args
			pma = [] method_args.each do |ma|
				if Array === ma
					pma << "#{ma[0]}=#{ma[1]}"
				else
					pma << ma.to_s
				end
			end
			parsed_method_args = pma.join(',')
		else
			parsed_method_args = method_args.to_s
		end

		m = "def #{method_name}(#{parsed_method_args})\n" chunks.each do |chunk|
			if chunk.respond_to?(:call)
				m << chunk.call(*args)
			else
				m << chunk.to_s
			end
		end m << "\nend"

		class_eval m
	end
end
