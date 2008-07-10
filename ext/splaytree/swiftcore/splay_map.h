//  splay_map.h -- implementation af a STL complatible map/multimap based on a splay tree.
//  
//  Copyright (c) 2004 Ralf Mattethat, Danish Technological Institute, Informatics
//
//  Permission to copy, use, modify, sell and distribute this software
//  is granted provided this copyright notice appears in all copies.
//  This software is provided "as is" without express or implied
//  warranty, and with no claim as to its suitability for any purpose.
//
//  Please send questions, comments, complaints, performance data, etc to  
//  ralf.mattethat@teknologisk.dk

#ifndef SPLAY_MAP_H_RMA13022003
#define SPLAY_MAP_H_RMA13022003

#include "splay_tree.h"

#include <functional>

/*	Requirements for element type
	* must be copy-constructible
	* destructor must not throw exception

	Methods marked with note A only throws an exception if operator== or operator< 
	or the used predicate throws an exception

	iterators are only invalidated, if the element pointed to by the iterator 
	is deleted. The same goes for element references
*/

namespace swiftcore
{

	template <typename K, typename T, typename Compare = std::less<K>, typename Allocator = std::allocator<std::pair<const K,T> > >
	class splay_map
	{
	public:
		// container
		typedef K							key_type;
		typedef std::pair<const K,T>		value_type;

	private:
		// extract the keypart of a value of type value_type
		struct KeyPart : public std::unary_function<value_type,key_type>
		{
			const key_type& operator()( const value_type& x ) const { return x.first; }
		};
	    
		typedef detail::splay_tree<K, value_type, KeyPart, Compare, Allocator> Rep_type;

	public:

		// map
		typedef T							mapped_type;
		typedef Compare						key_compare;

		// map
		class value_compare : public std::binary_function<value_type, value_type, bool>
		{
			friend class splay_map<K,T,Compare,Allocator>;
		protected:
			Compare comp;
			value_compare( Compare c ) : comp( c ) { }

		public:
			bool operator()( const value_type& x, const value_type& y ) const
			{
				return comp( x.first, y.first );
			}
		};


		// container
		typedef typename Rep_type::reference			reference;
		typedef typename Rep_type::const_reference		const_reference;
		typedef typename Rep_type::size_type			size_type;
		typedef typename Rep_type::difference_type		difference_type;

		typedef typename Rep_type::allocator_type		allocator_type;
		typedef typename Rep_type::pointer				pointer;
		typedef typename Rep_type::const_pointer		const_pointer;

		// container
		typedef typename Rep_type::const_iterator		const_iterator;
		typedef typename Rep_type::iterator				iterator;


		// reversible container
		typedef std::reverse_iterator<const_iterator>	const_reverse_iterator;
		typedef std::reverse_iterator<iterator>			reverse_iterator;
		
		/////////////////////////////////////////////////////////////////
		// construct/copy/destroy:
			
		// container	| complexity : constant		| exception :
		explicit splay_map( const key_compare& comp = Compare(), const allocator_type& a = Allocator() )
			: rep_( comp, a )
		{ }

		// associative sequence		| complexity : NlogN		| exception :
		template <typename InputIterator>
		splay_map( InputIterator first, InputIterator last, const key_compare& comp = Compare(), const allocator_type& a = Allocator() )
			: rep_( comp, a )
		{ insert( first, last ); }

		// container	| complexity : linear		| exception : 
		splay_map( const splay_map& x )
			: rep_( x.rep_.key_comp(), x.rep_.get_allocator() )
		{ insert( x.begin(), x.end() ); }

		// container	| complexity : linear		| exception : nothrow
		~splay_map()	{ }

		// container	| complexity : linear		| exception : strong
		splay_map& operator= ( const splay_map& rhs )
		{
			splay_map temp( rhs );
			swap( temp );
			return *this;
		}

		//				| complexity : constant		| exception : nothrow
		allocator_type get_allocator() const { return rep_.get_allocator(); }


		/////////////////////////////////////////////////////////////////
		// iterators:
		
		// container	| complexity : constant		| exception : nothrow
		iterator		begin()			{ return rep_.begin(); }
		const_iterator	begin()	const	{ return rep_.begin(); }
		iterator		end()			{ return rep_.end(); }
		const_iterator	end()	const	{ return rep_.end(); }
		iterator		parent()			{ return rep_.parent(); }
		const_iterator	parent()	const	{ return rep_.parent(); }
		void erase_childfree_nodes() {rep_.erase_childfree_nodes();}
		void set_max_permitted_size(int sz) {rep_.set_max_permitted_size(sz);};
		int get_max_permitted_size() {return rep_.get_max_permitted_size();};

		// reversible container	| complexity : constant		| exception : nothrow
		reverse_iterator		rbegin()		{ return reverse_iterator( end() ); }
		const_reverse_iterator	rbegin() const	{ return const_reverse_iterator( end() ); }
		reverse_iterator		rend()			{ return reverse_iterator( begin() ); }
		const_reverse_iterator	rend()	 const	{ return const_reverse_iterator( begin() ); }

		
		/////////////////////////////////////////////////////////////////
		// capacity:
		
		// container	| complexity : constant		| exception : nothrow
		bool empty() const			{ return rep_.empty(); }

		// container	| complexity : constant		| exception : nothrow
		size_type size() const		{ return rep_.size(); }

		// container	| complexity : constant		| exception : nothrow
		size_type max_size() const	{ return rep_.max_size(); }

		
		/////////////////////////////////////////////////////////////////
		// element access:
		
		//				| complexity : logarithmic		| exception : strong
		mapped_type& operator[] ( const key_type& x )
		{
			return ( *( insert( std::make_pair(x, mapped_type() ) ).first ) ).second;
		}
		
		
		/////////////////////////////////////////////////////////////////
		// modifiers:
		
		// associative sequence		| complexity : logarithmic			| exception : strong
		std::pair<iterator, bool> insert( const value_type& x )
		{
			return rep_.insert_unique( x );
		}

		// associative sequence		| complexity : constant/logarithmic	| exception : strong
		iterator insert( iterator position, const value_type& x )
		{
			return rep_.insert_unique( position, x );
		}

		// associative sequence		| complexity : NlogN				| exception : weak
		template <typename InputIterator>
		void insert( InputIterator first, InputIterator last )
		{
			rep_.insert_unique( first, last );
		}
	    
		// associative sequence		| complexity : logarithmic			| exception : strong, note A
		size_type erase( const key_type& x )
		{
			return rep_.erase( x );
		}

		// associative sequence		| complexity : constant				| exception : nothrow
		void erase( iterator position )
		{
			rep_.erase( position );
		}

		// associative sequence		| complexity : linear				| exception : nothrow
		void erase( iterator first, iterator last )
		{
			rep_.erase( first, last );
		}

		// associative sequence		| complexity : linear				| exception : nothrow
		void clear()
		{
			rep_.clear();
		}

		// container	| complexity : constant		| exception : nothrow
		void swap( splay_map& x )
		{
			rep_.swap( x.rep_ );
		}


		/////////////////////////////////////////////////////////////////
		// observers:
		
		// associative sequence		| complexity : constant		| exception : nothrow
		key_compare key_comp()		const	{ return rep_.key_comp(); }
		value_compare value_comp()	const	{ return value_compare( rep_.key_comp() ); }


		/////////////////////////////////////////////////////////////////
		// map operations:
		
 		// associative sequence		| complexity : logarithmic		| exception : strong, note A
		iterator find( const key_type& x )
		{
			return rep_.find( x );
		}
	 
		// associative sequence		| complexity : logarithmic		| exception : strong, note A
		const_iterator find( const key_type& x ) const
		{
			return rep_.find( x );
 		}

		// associative sequence		| complexity : logarithmic		| exception : strong, note A
		size_type count( const key_type& x ) const
		{
			return rep_.count( x );
		}

		// associative sequence		| complexity : logarithmic		| exception : strong, note A
		iterator lower_bound( const key_type& x )
		{
			return rep_.lower_bound( x );
		}

		// associative sequence		| complexity : logarithmic		| exception : strong, note A
		const_iterator lower_bound( const key_type& x ) const
		{
			return rep_.lower_bound( x );
		}

		// associative sequence		| complexity : logarithmic		| exception : strong, note A
		iterator upper_bound( const key_type& x )
		{
			return rep_.upper_bound( x );
		}

		// associative sequence		| complexity : logarithmic		| exception : strong, note A
		const_iterator upper_bound( const key_type& x ) const
		{
			return rep_.upper_bound( x );
		}

		// associative sequence		| complexity : logarithmic		| exception : strong, note A
		std::pair<iterator, iterator> equal_range( const key_type& x )
		{
			return rep_.equal_range( x );
		}

		// associative sequence		| complexity : logarithmic		| exception : strong, note A
		std::pair<const_iterator, const_iterator> equal_range( const key_type& x ) const
		{
			return rep_.equal_range( x );
		}

	private:
		Rep_type rep_;
	};

	template <typename K, typename T, typename Compare = std::less<K>, typename Allocator = std::allocator<std::pair<const K,T> > >
	class splay_multimap
	{
	public:
		// container
		typedef K							key_type;
		typedef std::pair<const K,T>		value_type;

	private:
		// extract the keypart of a value of type value_type
		struct KeyPart : public std::unary_function<value_type,key_type>
		{
			const key_type& operator()( const value_type& x ) const { return x.first; }
		};
	    
		typedef detail::splay_tree<K, value_type, KeyPart, Compare, Allocator> Rep_type;

	public:

		// map
		typedef T							mapped_type;
		typedef Compare						key_compare;

		// map
		class value_compare : public std::binary_function<value_type, value_type, bool>
		{
			friend class splay_multimap<K,T,Compare,Allocator>;
		protected:
			Compare comp;
			value_compare( Compare c ) : comp( c ) { }

		public:
			bool operator()( const value_type& x, const value_type& y ) const
			{
				return comp( x.first, y.first );
			}
		};


		// container
		typedef typename Rep_type::reference			reference;
		typedef typename Rep_type::const_reference		const_reference;
		typedef typename Rep_type::size_type			size_type;
		typedef typename Rep_type::difference_type		difference_type;

		typedef typename Rep_type::allocator_type		allocator_type;
		typedef typename Rep_type::pointer				pointer;
		typedef typename Rep_type::const_pointer		const_pointer;

		// container
		typedef typename Rep_type::const_iterator		const_iterator;
		typedef typename Rep_type::iterator				iterator;


		// reversible container
		typedef std::reverse_iterator<const_iterator>	const_reverse_iterator;
		typedef std::reverse_iterator<iterator>			reverse_iterator;
		
		/////////////////////////////////////////////////////////////////
		// construct/copy/destroy:
			
		// container	| complexity : constant		| exception :
		explicit splay_multimap( const key_compare& comp = Compare(), const allocator_type& a = Allocator() )
			: rep_( comp, a )
		{ }

		// associative sequence		| complexity : NlogN		| exception :
		template <typename InputIterator>
		splay_multimap( InputIterator first, InputIterator last, const key_compare& comp = Compare(), const allocator_type& a = Allocator() )
			: rep_( comp, a )
		{ insert( first, last ); }

		// container	| complexity : linear		| exception : 
		splay_multimap( const splay_multimap& x )
			: rep_( x.rep_.key_comp(), x.rep_.get_allocator() )
		{ insert( x.begin(), x.end() ); }

		// container	| complexity : linear		| exception : nothrow
		~splay_multimap()	{ }

		// container	| complexity : linear		| exception : strong
		splay_multimap& operator= ( const splay_multimap& rhs )
		{
			splay_multimap temp( rhs );
			swap( temp );
			return *this;
		}

		//				| complexity : constant		| exception : nothrow
		allocator_type get_allocator() const { return rep_.get_allocator(); }


		/////////////////////////////////////////////////////////////////
		// iterators:
		
		// container	| complexity : constant		| exception : nothrow
		iterator		begin()			{ return rep_.begin(); }
		const_iterator	begin()	const	{ return rep_.begin(); }
		iterator		end()			{ return rep_.end(); }
		const_iterator	end()	const	{ return rep_.end(); }

		// reversible container	| complexity : constant		| exception : nothrow
		reverse_iterator		rbegin()		{ return reverse_iterator( end() ); }
		const_reverse_iterator	rbegin() const	{ return const_reverse_iterator( end() ); }
		reverse_iterator		rend()			{ return reverse_iterator( begin() ); }
		const_reverse_iterator	rend()	 const	{ return const_reverse_iterator( begin() ); }

		
		/////////////////////////////////////////////////////////////////
		// capacity:
		
		// container	| complexity : constant		| exception : nothrow
		bool empty() const			{ return rep_.empty(); }

		// container	| complexity : constant		| exception : nothrow
		size_type size() const		{ return rep_.size(); }

		// container	| complexity : constant		| exception : nothrow
		size_type max_size() const	{ return rep_.max_size(); }

		
		/////////////////////////////////////////////////////////////////
		// modifiers:
		
		// associative sequence		| complexity : logarithmic			| exception : strong
		iterator insert( const value_type& x )
		{
			return rep_.insert_equal( x );
		}

		// associative sequence		| complexity : constant/logarithmic	| exception : strong
		iterator insert( iterator position, const value_type& x )
		{
			return rep_.insert_equal( position, x );
		}

		// associative sequence		| complexity : NlogN				| exception : weak
		template <typename InputIterator>
		void insert( InputIterator first, InputIterator last )
		{
			rep_.insert_equal( first, last );
		}
	    
		// associative sequence		| complexity : logarithmic			| exception : strong, note A
		size_type erase( const key_type& x )
		{
			return rep_.erase( x );
		}

		// associative sequence		| complexity : constant				| exception : nothrow
		void erase( iterator position )
		{
			rep_.erase( position );
		}

		// associative sequence		| complexity : linear				| exception : nothrow
		void erase( iterator first, iterator last )
		{
			rep_.erase( first, last );
		}

		// associative sequence		| complexity : linear				| exception : nothrow
		void clear()
		{
			rep_.clear();
		}

		// container	| complexity : constant		| exception : nothrow
		void swap( splay_multimap& x )
		{
			rep_.swap( x.rep_ );
		}


		/////////////////////////////////////////////////////////////////
		// observers:
		
		// associative sequence		| complexity : constant		| exception : nothrow
		key_compare key_comp()		const	{ return rep_.key_comp(); }
		value_compare value_comp()	const	{ return value_compare( rep_.key_comp() ); }


		/////////////////////////////////////////////////////////////////
		// map operations:
		
 		// associative sequence		| complexity : logarithmic		| exception : strong, note A
		iterator find( const key_type& x )
		{
			return rep_.find( x );
		}
	 
		// associative sequence		| complexity : logarithmic		| exception : strong, note A
		const_iterator find( const key_type& x ) const
		{
			return rep_.find( x );
 		}

		// associative sequence		| complexity : logarithmic		| exception : strong, note A
		size_type count( const key_type& x ) const
		{
			return rep_.count( x );
		}

		// associative sequence		| complexity : logarithmic		| exception : strong, note A
		iterator lower_bound( const key_type& x )
		{
			return rep_.lower_bound( x );
		}

		// associative sequence		| complexity : logarithmic		| exception : strong, note A
		const_iterator lower_bound( const key_type& x ) const
		{
			return rep_.lower_bound( x );
		}

		// associative sequence		| complexity : logarithmic		| exception : strong, note A
		iterator upper_bound( const key_type& x )
		{
			return rep_.upper_bound( x );
		}

		// associative sequence		| complexity : logarithmic		| exception : strong, note A
		const_iterator upper_bound( const key_type& x ) const
		{
			return rep_.upper_bound( x );
		}

		// associative sequence		| complexity : logarithmic		| exception : strong, note A
		std::pair<iterator, iterator> equal_range( const key_type& x )
		{
			return rep_.equal_range( x );
		}

		// associative sequence		| complexity : logarithmic		| exception : strong, note A
		std::pair<const_iterator, const_iterator> equal_range( const key_type& x ) const
		{
			return rep_.equal_range( x );
		}

	private:
		Rep_type rep_;
	};

	// container	| complexity : linear		| exception : strong, note A
	template <typename K, typename T, typename Compare, typename Allocator>
	inline bool operator == ( const splay_map<K,T,Compare, Allocator>& lhs, const splay_map<K,T,Compare, Allocator>& rhs )
	{
		return lhs.size() == rhs.size() && std::equal( lhs.begin(), lhs.end(), rhs.begin() );
	}

	// container	| complexity : linear		| exception : strong, note A
	template <typename K, typename T, typename Compare, typename Allocator>
	inline bool operator < ( const splay_map<K,T,Compare, Allocator>& lhs, const splay_map<K,T,Compare, Allocator>& rhs )
	{
		return std::lexicographical_compare( lhs.begin(), lhs.end(), rhs.begin(), rhs.end() );
	}

	// container	| complexity : linear		| exception : strong, note A
	template <typename K, typename T, typename Compare, typename Allocator>
	inline bool operator != ( const splay_map<K,T,Compare, Allocator>& lhs, const splay_map<K,T,Compare, Allocator>& rhs )
	{
		return !( lhs == rhs );
	}

	// container	| complexity : linear		| exception : strong, note A
	template <typename K, typename T, typename Compare, typename Allocator>
	inline bool operator > ( const splay_map<K,T,Compare, Allocator>& lhs, const splay_map<K,T,Compare, Allocator>& rhs )
	{
		return rhs < lhs;
	}

	// container	| complexity : linear		| exception : strong, note A
	template <typename K, typename T, typename Compare, typename Allocator>
	inline bool operator <= ( const splay_map<K,T,Compare, Allocator>& lhs, const splay_map<K,T,Compare, Allocator>& rhs )
	{
		return !( rhs < lhs );
	}

	// container	| complexity : linear		| exception : strong, note A
	template <typename K, typename T, typename Compare, typename Allocator>
	inline bool operator >= ( const splay_map<K,T,Compare, Allocator>& lhs, const splay_map<K,T,Compare, Allocator>& rhs )
	{
		return !( lhs < rhs );
	}

	// container	| complexity : constant		| exception : nothrow
	template <typename K, typename T, typename Compare, typename Allocator>
	inline void swap( splay_map<K,T,Compare, Allocator>& x, splay_map<K,T,Compare, Allocator>& y )
	{
		x.swap( y );
	}

	// container	| complexity : linear		| exception : strong, note A
	template <typename K, typename T, typename Compare, typename Allocator>
	inline bool operator == ( const splay_multimap<K,T,Compare, Allocator>& lhs, const splay_multimap<K,T,Compare, Allocator>& rhs )
	{
		return lhs.size() == rhs.size() && std::equal( lhs.begin(), lhs.end(), rhs.begin() );
	}

	// container	| complexity : linear		| exception : strong, note A
	template <typename K, typename T, typename Compare, typename Allocator>
	inline bool operator < ( const splay_multimap<K,T,Compare, Allocator>& lhs, const splay_multimap<K,T,Compare, Allocator>& rhs )
	{
		return std::lexicographical_compare( lhs.begin(), lhs.end(), rhs.begin(), rhs.end() );
	}

	// container	| complexity : linear		| exception : strong, note A
	template <typename K, typename T, typename Compare, typename Allocator>
	inline bool operator != ( const splay_multimap<K,T,Compare, Allocator>& lhs, const splay_multimap<K,T,Compare, Allocator>& rhs )
	{
		return !( lhs == rhs );
	}

	// container	| complexity : linear		| exception : strong, note A
	template <typename K, typename T, typename Compare, typename Allocator>
	inline bool operator > ( const splay_multimap<K,T,Compare, Allocator>& lhs, const splay_multimap<K,T,Compare, Allocator>& rhs )
	{
		return rhs < lhs;
	}

	// container	| complexity : linear		| exception : strong, note A
	template <typename K, typename T, typename Compare, typename Allocator>
	inline bool operator <= ( const splay_multimap<K,T,Compare, Allocator>& lhs, const splay_multimap<K,T,Compare, Allocator>& rhs )
	{
		return !( rhs < lhs );
	}

	// container	| complexity : linear		| exception : strong, note A
	template <typename K, typename T, typename Compare, typename Allocator>
	inline bool operator >= ( const splay_multimap<K,T,Compare, Allocator>& lhs, const splay_multimap<K,T,Compare, Allocator>& rhs )
	{
		return !( lhs < rhs );
	}

	// container	| complexity : constant		| exception : nothrow
	template <typename K, typename T, typename Compare, typename Allocator>
	inline void swap( splay_multimap<K,T,Compare, Allocator>& x, splay_multimap<K,T,Compare, Allocator>& y )
	{
		x.swap( y );
	}

}	// namespace swiftcore

#endif // SPLAY_MAP_H_RMA13022003
