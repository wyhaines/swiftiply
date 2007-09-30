//  splay_tree.h -- implementation af a STL complatible splay tree.
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

#ifndef SPLAY_TREE_H_RMA05022003
#define SPLAY_TREE_H_RMA05022003

#include <cstddef>
#include <iterator>
#include <utility>
#include <memory>
#include <iostream>
#include <string>

/*	Requirements for element type
	* must be copy-constructible
	* destructor must not throw exception

	Methods marked with note A only throws an exception if the predicate throws 
	an exception. If an exception is thrown the call has no effect on the 
	containers state

	iterators are only invalidated, if the element pointed to by the iterator 
	is deleted. The same goes for element references


	Implementation:
	splay_tree is an implementation of a binary search tree. The tree is self 
	balancing using the spay algorithm as described in
	
		"Self-Adjusting Binary Search Trees 
		by Daniel Dominic Sleator and Robert Endre Tarjan
		AT&T Bell Laboratories, Murray Hill, NJ
		Jorunal of the ACM, Vol 32, no 3, July 1985, pp 652-686

	A node in the search tree has references to its children and its parent. This 
	is to allow traversal of the whole tree from a given node making the 
	implementation of iterator a pointer to a node.
	At the top of the tree a node is used specially. This node's parent pointer 
	is pointing to the root of the tree. It's left and right pointer points to the 
	leftmost and rightmost node in the tree respectively. This node is used to 
	represent the end-iterator.

										     +---------+
		tree_ ------------------------------>|         |
										     |         |
					+-----------(left)-------|         |-------(right)--------+
					|					     +---------+                      |
                    |                             |                           |
                    |                             | (parent)                  |
                    |                             |                           |
                    |                             |                           |
					|					     +---------+                      |
	 root of tree ..|.......................>|         |                      |
					|					     |    D    |                      |
					|					     |         |                      |
					|				         +---------+                      |
                    |                         /       \                       |
                    |                        /         \                      |
					|					    /           \                     |
					|					   /             \                    |
					|					  /               \                   |
					|	         +---------+             +---------+          |
					|	         |         |             |         |          |
					|	         |    B    |             |    F    |          |
					|	         |         |             |         |          |
					|	         +---------+             +---------+          |
                    |             /       \               /       \           |
                    |            /         \             /         \          |
                    |           /           \           /           \         |
					|	+---------+   +---------+  +---------+  +---------+   |
					+-->|         |   |         |  |         |  |         |<--+
						|    A    |   |    C    |  |    E    |  |    G    |
						|         |   |         |  |         |  |         |
						+---------+   +---------+  +---------+  +---------+

	Figure 1: Representation of data

*/

namespace swiftcore
{
	namespace detail
	{

		// contains logic manipulating the tree structure
		class splay_tree_base
		{
		protected:

			struct node_base
			{
				node_base*	parent;
				node_base*	left;
				node_base*	right;

				node_base() throw()
					: parent( 0 ), left( 0 ), right( 0 )
				{ }
				
				node_base( node_base* p, node_base* l, node_base* r ) throw()
					: parent( p ), left( l ), right( r )
				{ }

				// return pointer to the node preceding this node
				node_base* previous()
				{
					node_base* n = this;

					if( n->parent == 0 || n->parent == n->right || ( n->right != 0 && n->right->parent != n ) )
					{
						n = n->right;	// sentinel (end) node
					}
					else if( n->left != 0 )
					{
						n = n->left;
						while( n->right != 0 )
						{
							n = n->right;
						}
					}
					else
					{
						node_base* p = n->parent;
						while( n == p->left )
						{
							n = p;
							p = p->parent;
						}
						n = p;
					}

					return n;
				}

				// return pointer to the node succeding this node
				node_base* next()
				{
					node_base* n = this;

					if( n->right != 0 )
					{
						n = n->right;
						while( n->left != 0 )
						{
							n = n->left;
						}
					}
					else
					{
						// NOTE: infinite loop if end-iterator is incremented
						node_base* p = n->parent;
						while( n == p->right )
						{
							n = p;
							p = p->parent;
						}
						if( n->right != p )
						{
							n = p;
						}
					}

					return n;
				}
			};

		protected:

			splay_tree_base() : data_( 0 ) { }

			// update parent pointers for child nodes	| complexity : constant		| exception : nothrow
			static void link_to_parent( node_base* n )
			{
				if( n->left != 0 )
				{
					n->left->parent = n;
				}

				if( n->right != 0 )
				{
					n->right->parent = n;
				}
			}

			// insert new_node after n			| complexity : constant		| exception : nothrow
			void insert_after( node_base* n,  node_base* new_node )
			{
				if( n->right != 0 )
				{
					n->right->parent = new_node;
				}
				else
				{
					data_->right = new_node;
				}

				n->right = new_node;
			}

			// insert new_node to the left of n	| complexity : constant		| exception : nothrow
			void insert_left( node_base* n,  node_base* new_node )
			{
				n->left = 0;

				link_to_parent( new_node );

				data_->parent = new_node;
				if( new_node->left == 0 )
				{
					data_->left = new_node;
				}
			}

			// insert new_node to the right of n| complexity : constant		| exception : nothrow
			void insert_right( node_base* n,  node_base* new_node )
			{
				n->right = 0;

				link_to_parent( new_node );

				data_->parent = new_node;
				if( new_node->right == 0 )
				{
					data_->right = new_node;
				}
			}

			// delete node						| complexity : constant		| exception : nothrow
			void erase( node_base* t )
			{
				node_base* n = t->right;

				if( t->left != 0 )
				{
					node_base* l = t->previous();
					
					splay( l , t );

					n = t->left;

					n->right = t->right;
					if( n->right != 0 )
					{
						n->right->parent = n;
					}
				}

				if( n != 0 )
				{
					n->parent = t->parent;
				}

				if( t->parent == data_ )
				{
					data_->parent = n;
				}
				else if( t->parent->left == t )
				{
					t->parent->left = n;
				}
				else // must be ( t->parent->right == t )
				{
					t->parent->right = n;
				}

				if( data_->left == t )
				{
					data_->left = find_leftmost();
				}
				if( data_->right == t )
				{
					data_->right = find_rightmost();
				}
			}

			// rotate node t with left child			| complexity : constant		| exception : nothrow
			static void rotate_left( node_base*& t )
			{
				node_base* x = t->right;
				t->right = x->left;
				if( t->right != 0 )
				{
					t->right->parent = t;
				}
				x->left = t;
				t->parent = x;
				t = x;
			}

			// rotate node t with right child			| complexity : constant		| exception : nothrow
			static void rotate_right( node_base*& t )
			{
				node_base* x = t->left;
				t->left = x->right;
				if( t->left != 0 )
				{
					t->left->parent = t;
				}
				x->right = t;
				t->parent = x;
				t = x;
			}

			// break link to left child node and attach it to left tree pointed to by l   | complexity : constant | exception : nothrow
			static void link_left( node_base*& t, node_base*& l )
			{
				l->right = t;
				t->parent = l;
				l = t;
				t = t->right;
			}

			// break link to right child node and attach it to right tree pointed to by r | complexity : constant | exception : nothrow
			static void link_right( node_base*& t, node_base*& r )
			{
				r->left = t;
				t->parent = r;
				r = t;
				t = t->left;
			}

			// assemble the three sub-trees into new tree pointed to by t	| complexity : constant		| exception : nothrow
			static void assemble( node_base* t, node_base* l, node_base* r, const node_base& null_node )
			{
				l->right = t->left;
				r->left = t->right;

				if( l->right != 0 )
				{
					l->right->parent = l;
				}

				if( r->left != 0 )
				{
					r->left->parent = r;
				}

				t->left = null_node.right;
				t->right = null_node.left;
				link_to_parent( t );
			}

			// bottom-up splay, use data_ as parent for n	| complexity : logaritmic	| exception : nothrow
			void splay( node_base* n ) const
			{
				if( n == data_ )
				{
					n = data_->right;
				}

				splay( n, data_ );
			}

		private:

			// rotate n with its parent					 | complexity : constant	| exception : nothrow
			void rotate( node_base* n ) const
			{
				node_base* p = n->parent;
				node_base* g = p->parent;
				
				if( p->left == n )
				{
					p->left = n->right;
					if( p->left != 0 )
					{
						p->left->parent = p;
					}
					n->right = p;
				}
				else // must be ( p->right == n )
				{
					p->right = n->left;
					if( p->right != 0 )
					{
						p->right->parent = p;
					}
					n->left = p;
				}

				p->parent = n;
				n->parent = g;

				if( g == data_ )
				{
					g->parent = n;
				}
				else if( g->left == p )
				{
					g->left = n;
				}
				else //must be ( g->right == p )
				{
					g->right = n;
				}
			}

			// bottom-up splay, use t as parent for n		| complexity : logaritmic	| exception : nothrow
			void splay( node_base* n, node_base* t ) const
			{
				if( n == t ) return;
				
				for( ;; )
				{
					node_base* p = n->parent;

					if( p == t )
						break;
					
					node_base* g = p->parent;
					
					if( g == t )
					{	// zig
						rotate( n );				
					}
					else if( ( p->left == n && g->left == p ) || ( p->right == n && g->right == p ) )
					{	// zig-zig
						rotate( p );
						rotate( n );				
					}
					else
					{	// zig-zag
						rotate( n );
						rotate( n );
					}
				}
			}

			// find the left most node in tree	| complexity : logaritmic	| exception : nothrow
			node_base* find_leftmost() const
			{
				node_base* n = data_->parent;
				if( n == 0 )
					return data_;

				while( n->left != 0 )
				{
					n = n->left;
				}

				return n;
			}

			// find the right most node in tree	| complexity : logaritmic	| exception : nothrow
			node_base* find_rightmost() const
			{
				node_base* n = data_->parent;
				if( n == 0 )
					return data_;

				while( n->right != 0 )
				{
					n = n->right;
				}

				return n;
			}

		protected:
			node_base* data_;
		};

		template <typename K, typename T, typename Key, typename Compare, typename Allocator>
		class splay_tree : private splay_tree_base
		{

			struct node : splay_tree_base::node_base 
			{
				T	element;

				node( const T& item, node_base* p, node_base* l, node_base* r )
					: node_base( p, l, r ), element( item )
				{ }

			private:
				node& operator= ( const node& );	// to disable warning C4512 (compiler bug)
			};

			// return key part of value in node
			const K& key_from_node( const node_base* n ) const { return Key()( static_cast<const node*>( n )->element ); }

		public:
			// container
			typedef K									key_type;
			typedef T									value_type;
			typedef Compare								key_compare;
			typedef typename Allocator::reference		reference;
			typedef typename Allocator::const_reference	const_reference;
			typedef typename Allocator::size_type		size_type;
			typedef typename Allocator::difference_type	difference_type;

			typedef Allocator							allocator_type;
			typedef typename Allocator::pointer			pointer;
			typedef typename Allocator::const_pointer	const_pointer;

			// container
			class iterator_base
			{
			protected:
				iterator_base() : item_( 0 ) { }
				iterator_base( node_base* e ) : item_( e ) { }

			public:
				bool operator== ( const iterator_base& iter ) const	{ return item_ == iter.item_; }
				bool operator!= ( const iterator_base& iter ) const	{ return item_ != iter.item_; }

			protected:
				node_base* item_;
			};

			class const_iterator;

			class iterator : public std::iterator<std::bidirectional_iterator_tag, value_type, difference_type, pointer, reference>,
							 public iterator_base
			{
				friend class splay_tree<K, T, Key, Compare, Allocator>;
				friend class const_iterator;

				iterator( node_base* e ) : iterator_base( e ) { }

			public:
				typedef std::bidirectional_iterator_tag		iterator_category;
				typedef T									value_type;
				typedef typename Allocator::reference		reference;
				typedef typename Allocator::pointer			pointer;
				typedef typename Allocator::difference_type	difference_type;

				iterator() { }

				reference operator* ()  const	{ return static_cast<node*>( this->item_ )->element; }
				pointer   operator-> () const	{ return &**this; }

				iterator& operator++ ()			{ this->item_ = this->item_->next(); return *this; }
				iterator  operator++ ( int )	{ iterator tmp( *this ); this->item_ = this->item_->next(); return tmp; }

				iterator& operator-- ()			{ this->item_ = this->item_->previous(); return *this; }
				iterator  operator-- ( int )	{ iterator tmp( *this ); this->item_ = this->item_->previous(); return tmp; }
			};

			class const_iterator : public std::iterator<std::bidirectional_iterator_tag, value_type, difference_type, const_pointer, const_reference>,
								   public iterator_base
			{
				friend class splay_tree<K, T, Key, Compare, Allocator>;
				friend class iterator;

				const_iterator( node_base* e ) : iterator_base( e ) { }

			public:
				typedef std::bidirectional_iterator_tag		iterator_category;
				typedef T									value_type;
				typedef typename Allocator::const_reference	reference;
				typedef typename Allocator::const_pointer	pointer;
				typedef typename Allocator::difference_type	difference_type;

				const_iterator() { }
				const_iterator( const iterator& it ) : iterator_base( it.item_ ) { }

				reference operator* ()  const		{ return static_cast<node*>( this->item_ )->element; }
				pointer   operator-> () const		{ return &**this; }

				const_iterator&	operator++ ()		{ this->item_ = this->item_->next(); return *this; }
				const_iterator	operator++ ( int )	{ const_iterator tmp( *this ); this->item_ = this->item_->next(); return tmp; }

				const_iterator&	operator-- ()		{ this->item_ = this->item_->previous(); return *this; }
				const_iterator	operator-- ( int )	{ const_iterator tmp( *this ); this->item_ = this->item_->previous(); return tmp; }
			};


			/////////////////////////////////////////////////////////////////
			// construct/copy/destroy:

			// container	| complexity : constant		| exception :
			explicit splay_tree( const key_compare& comp, const allocator_type& a )
				: size_( 0 ), comp_( comp ), allocator_( a ), node_allocator_( a )
			{
				data_ = node_allocator_.allocate( 1, 0 );

				new ( data_ ) node_base( 0 , data_, data_ );
			}

			// container	| complexity : linear		| exception : nothrow
			~splay_tree()
			{
				clear();
				data_->~node_base();
				node_allocator_.deallocate( static_cast<node*>( data_ ), 1 );
			}

			//				| complexity : constant		| exception : nothrow
			allocator_type get_allocator() const { return allocator_; }


			/////////////////////////////////////////////////////////////////
			// iterators:
			
			// container	| complexity : constant		| exception : nothrow
			iterator		begin()			{ return iterator( data_->left ); }
			const_iterator	begin()	const	{ return const_iterator( data_->left ); }
			iterator		end()			{ return iterator( data_ ); }
			const_iterator	end()	const	{ return const_iterator( data_ ); }
			iterator parent() { return iterator( data_->parent ); }
			const_iterator parent() const { return const_iterator( data_->parent ); }


			/////////////////////////////////////////////////////////////////
			// capacity:
			
			// container	| complexity : constant		| exception : nothrow
			bool empty() const			{ return size_ == 0; }

			// container	| complexity : constant		| exception : nothrow
			size_type size() const		{ return size_; }

			// container	| complexity : constant		| exception : nothrow
			size_type max_size() const	{ return allocator_.max_size(); }


			/////////////////////////////////////////////////////////////////
			// modifiers:

			// associative sequence		| complexity : logarithmic			| exception : strong
			std::pair<iterator, bool> insert_unique( const value_type& x )
			{
				bool inserted = false;

				splay( Key()( x ) );
				node_base* n = data_->parent;

				if( n == 0 )
				{ // empty tree
					node* new_node = construct( x, data_, 0, 0 );
					data_->parent = data_->left = data_->right = new_node;
					size_ = 1;
					inserted = true;
				}
				else if( comp_( Key()( x ), key_from_node( n ) ) )
				{
					node* new_node = construct( x, data_, n->left, n );
					insert_left( n,  new_node );
					++size_;
					inserted = true;
				}
				else if( comp_( key_from_node( n ), Key()( x ) ) )
				{
					node* new_node = construct( x, data_, n, n->right );
					insert_right( n,  new_node );
					++size_;
					inserted = true;
				}

				return std::pair<iterator, bool>( iterator( data_->parent ), inserted );
			}

			// associative sequence		| complexity : constant/logarithmic	| exception : strong
			iterator insert_unique( iterator position, const value_type& x )
			{	// complexity should be amortized constant time if x is inserted right after position

				if( position != end() && comp_( key_from_node( position.item_ ), Key()( x ) ) )
				{	// 'position' is before x
					splay_tree_base::splay( position.item_ );

					iterator next = position;
					++next;

					if( next == end() || comp_( Key()( x ), key_from_node( next.item_ ) ) )
					{
						return iterator( insert_after( position.item_, x ) );
					}
					else if( !comp_( key_from_node( next.item_ ), Key()( x ) ) )
					{	// x already inserted
						return next;
					}
				}

				// 'position' didn´t point the right place
				return insert_unique( x ).first;
			}

			// associative sequence		| complexity : NlogN					| exception : weak
			template <typename InputIterator>
			void insert_unique( InputIterator first, InputIterator last )
			{
				iterator pos = end();
				for( InputIterator it = first; it != last; ++it )
				{
					pos = insert_unique( pos, *it );
				}
			}
		    
			// associative sequence		| complexity : logarithmic				| exception : strong
			iterator insert_equal( const value_type& x )
			{
				splay( Key()( x ) );
				node_base* n = data_->parent;

				if( n == 0 )
				{ // empty tree
					node* new_node = construct( x, data_, 0, 0 );
					data_->parent = data_->left = data_->right = new_node;
					size_ = 1;
				}
				else if( comp_( Key()( x ), key_from_node( n ) ) )
				{
					node* new_node = construct( x, data_, n->left, n );
					insert_left( n,  new_node );
					++size_;
				}
				else
				{
					node* new_node = construct( x, data_, n, n->right );
					insert_right( n,  new_node );
					++size_;
				}

				return iterator( data_->parent );
			}

			// associative sequence		| complexity : constant(a)/logarithmic	| exception : strong
			iterator insert_equal( iterator position, const value_type& x )
			{	// complexity should be amortized constant time if x is inserted right after position

				if( position != end() && !comp_( Key()( x ), key_from_node( position.item_ ) ) )
				{	// 'position' isn't after x
					splay_tree_base::splay( position.item_ );

					iterator next = position;
					++next;

					if( next == end() || !comp_( key_from_node( next.item_ ), Key()( x ) ) )
					{
						return iterator( insert_after( position.item_, x ) );
					}
				}

				// 'position' didn´t point the right place
				return insert_equal( x );
			}

			// associative sequence		| complexity : NlogN					| exception : weak
			template <typename InputIterator>
			void insert_equal( InputIterator first, InputIterator last )
			{
				iterator pos = end();
				for( InputIterator it = first; it != last; ++it )
				{
					pos = insert_equal( pos, *it );
				}
			}

			// associative sequence		| complexity : logarithmic				| exception : strong, note A
			size_type erase( const key_type& x )
			{
				std::pair<iterator,iterator> p = equal_range( x );
				size_type n = std::distance( p.first, p.second );
				erase( p.first, p.second );
				return n;
			}

			// associative sequence		| complexity : constant					| exception : nothrow
			void erase( iterator position )
			{
				node_base* t = position.item_;

				splay_tree_base::erase( t );

				--size_;
				destroy( t );
			}

			// associative sequence		| complexity : linear		| exception : nothrow
			void erase( iterator first, iterator last )
			{
				if( first == begin() && last == end() )
				{
					clear();
				}
				else
				{
					for( iterator it = first; it != last; )
					{
						erase( it++ );
					}
				}
			}

			// associative sequence		| complexity : linear		| exception : nothrow
			void clear()
			{
				node_base* n = data_->left;

				while( n != data_ )
				{
					if( n->left != 0 )
					{
						n = n->left;
					}
					else if( n->right != 0 )
					{
						n = n->right;
					}
					else
					{
						node_base* p = n->parent;
						if( p->left == n )
						{
							p->left = 0;
						}
						else // must be ( p->right == n )
						{
							p->right = 0;
						}

						destroy( n );
						n = p;
					}
				}
				data_->parent = 0;
				data_->left = data_->right = data_;
				size_ = 0;
			}

			// container	| complexity : constant		| exception : nothrow
			void swap( splay_tree& x )
			{
				std::swap( data_, x.data_ );
				std::swap( size_, x.size_ );		

				std::swap( comp_, x.comp_ );		
			}


			/////////////////////////////////////////////////////////////////
			// observers:
			
			// associative sequence		| complexity : constant		| exception : nothrow
			key_compare key_comp() const { return comp_; }


			/////////////////////////////////////////////////////////////////
			// splay tree operations:
			
 			// associative sequence		| complexity : logarithmic		| exception : strong, note A
			iterator find( const key_type& x )
			{
				splay( x );
				return iterator( internal_find( x ) );
			}
		 
			// associative sequence		| complexity : logarithmic		| exception : strong, note A
			const_iterator find( const key_type& x ) const
			{
				splay( x );
				return const_iterator( internal_find( x ) );
 			}

			// associative sequence		| complexity : logarithmic		| exception : strong, note A
			size_type count( const key_type& x ) const
			{
				std::pair<const_iterator, const_iterator> p = equal_range( x );
				return std::distance( p.first, p.second );
			}

			// associative sequence		| complexity : logarithmic		| exception : strong, note A
			iterator lower_bound( const key_type& x )
			{
				//splay( x );
				//return iterator( internal_lower_bound( x ) );
				node_base* n = internal_lower_bound( x );
				splay_tree_base::splay( n );
				return iterator( n );
			}

			// associative sequence		| complexity : logarithmic		| exception : strong, note A
			const_iterator lower_bound( const key_type& x ) const
			{
				node_base* n = internal_lower_bound( x );
				splay_tree_base::splay( n );
				return const_iterator( n );
			}

			// associative sequence		| complexity : logarithmic		| exception : strong, note A
			iterator upper_bound( const key_type& x )
			{
				node_base* n = internal_upper_bound( x );
				splay_tree_base::splay( n );
				return iterator( n );
			}

			// associative sequence		| complexity : logarithmic		| exception : strong, note A
			const_iterator upper_bound( const key_type& x ) const
			{
				node_base* n = internal_upper_bound( x );
				splay_tree_base::splay( n );
				return const_iterator( n );
			}

			// associative sequence		| complexity : logarithmic		| exception : strong, note A
			std::pair<iterator, iterator> equal_range( const key_type& x )
			{
				return std::make_pair( lower_bound( x ), upper_bound( x ) );
			}

			// associative sequence		| complexity : logarithmic		| exception : strong, note A
			std::pair<const_iterator, const_iterator> equal_range( const key_type& x ) const
			{
				return std::make_pair( lower_bound( x ), upper_bound( x ) );
			}

		private:

			// return a newly allocate node holding the value x | complexity : constant	| exception : strong
			node* construct( const value_type& x, node_base* p, node_base* l, node_base* r )
			{
				node* n = node_allocator_.allocate( 1, 0 );

				try
				{
					new ( n ) node( x, p, l, r );
				}
				catch( ... )
				{
					node_allocator_.deallocate( n, 1 );
					throw;
				}

				return n;
			}

			// deallocate node pointed to by n	| complexity : constant		| exception : nothrow
			void destroy( node_base* n )
			{
				node* p = static_cast<node*>( n );
				node_allocator_.destroy( p );
				node_allocator_.deallocate( p, 1 );
			}

			// insert new node after n			| complexity : constant		| exception : strong
			node_base* insert_after( node_base* n, const value_type& x )
			{
				node* new_node = construct( x, n, 0, n->right );
				splay_tree_base::insert_after( n, new_node );
				++size_;
				return new_node;
			}

			// find node with key x				| complexity : logaritmic	| exception : strong, note A
			node_base* internal_find( const key_type& x ) const
			{
				node_base* n = data_->parent;
		    
				while( n != 0 )
				{
					if( comp_( x, key_from_node( n ) ) )
					{
						n = n->left;
					}
					else if( comp_( key_from_node( n ), x ) )
					{
						n = n->right;
					}
					else
					{
						break;
					}
				}

				if( n == 0 )
				{
					n = data_;
				}

				return n;
			}

			// find first node with key not less than x	| complexity : logaritmic	| exception : strong, note A
			node_base* internal_lower_bound( const key_type& x ) const
			{
				node_base* p = data_;
				node_base* n = data_->parent;
		    
				while( n != 0 )
				{
					if( !comp_( key_from_node( n ), x ) )
					{
						p = n;
						n = n->left;
					}
					else
					{
						n = n->right;
					}
				}

				return p;
			}

			// find first node with key greater than x	| complexity : logaritmic	| exception : strong, note A
			node_base* internal_upper_bound( const key_type& x ) const
			{
				node_base* p = data_;
				node_base* n = data_->parent;
		    
				while( n != 0 )
				{
					if( comp_( x, key_from_node( n ) ) )
					{
						p = n;
						n = n->left;
					}
					else
					{
						n = n->right;
					}
				}

				return p;
			}

			// top-down splay, use t as root			| complexity : logaritmic	| exception : strong, note A
			void splay( const key_type& i, node_base*& t ) const
			{
				node_base null_node;
				node_base* l = &null_node;
				node_base* r = &null_node;
			
				for( ;; )
				{
					if( comp_( i, key_from_node( t ) ) )
					{
						if( t->left == 0 )
							break;

						if( comp_( i, key_from_node( t->left ) ) )
						{
							rotate_right( t );

							if( t->left == 0 )
								break;
						}

						link_right( t, r );
					}
					else if( comp_( key_from_node( t ), i ) )
					{
						if( t->right == 0 )
							break;

						if( comp_( key_from_node( t->right ), i ) )
						{
							rotate_left( t );

							if( t->right == 0 )
								break;
						}

						link_left( t, l );
					}
					else
					{
						break;
					}
				}

				assemble( t, l, r, null_node );
			}

			// top-down splay							| complexity : logaritmic	| exception : strong, note A
			void splay( const key_type& x ) const
			{
				if( data_->parent != 0 )
				{
					splay( x, data_->parent );
					data_->parent->parent = data_;
				}
			}

		private:
			size_type size_;
			key_compare comp_;
			allocator_type allocator_;
			typename allocator_type::template rebind<node>::other node_allocator_;
		};

	}	// namespace detail
}	// namespace swiftcore

#endif // SPLAY_TREE_H_RMA05022003
