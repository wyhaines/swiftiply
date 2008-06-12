#include <iostream>
#include <map>
#include <string>
#include "string.h"
using namespace std;

#include <ruby.h>

static VALUE SwiftcoreModule;
static VALUE MapClass;

struct classcomp {
  bool operator() (const char *s1, const char *s2) const
	{
		if ( strcmp(s1,s2) < 0) {
			return true;
		} else {
			return false;
		}
	}
};

typedef std::map<char *,VALUE,classcomp> rb_map;
typedef std::map<char *,VALUE,classcomp>::iterator rb_map_iterator;

static void sptm_mark (rb_map* st)
{
	rb_map_iterator q_iterator;
	if (st) {
		for ( q_iterator = (*st).begin(); q_iterator != (*st).end(); q_iterator++ ) {
			rb_gc_mark(q_iterator->second);
		}
	}
}

static void sptm_free (rb_map* st)
{
	if (st)
		delete st;
}

static VALUE sptm_new (VALUE self)
{
	rb_map* st = new rb_map;
	VALUE v = Data_Wrap_Struct (MapClass, sptm_mark, sptm_free, st);
	return v;
}

/*
static VALUE sptm_parent (VALUE self)
{
	rb_map* st = NULL;
	Data_Get_Struct(self, rb_map, st);
	if (!st)
		rb_raise (rb_eException, "No Map Object");

	if ((*st).empty()) {
		return Qnil;
	} else {
		rb_map_iterator parent = (*st).parent();
		VALUE r = rb_ary_new();

		rb_ary_push(r,rb_str_new2(parent->first));
		rb_ary_push(r,parent->second);
		return r;
	}
}
*/

static VALUE sptm_pop_front (VALUE self)
{
	rb_map* st = NULL;
	Data_Get_Struct(self, rb_map, st);
	if (!st)
		rb_raise (rb_eException, "No Map Object");

	if ((*st).empty()) {
		return Qnil;
	} else {
		rb_map_iterator front = (*st).begin();
		VALUE r = rb_ary_new();
		
		rb_ary_push(r,rb_str_new2(front->first));
		rb_ary_push(r,front->second);
		(*st).erase(front);
		return r;
	}
}

static VALUE sptm_pop_back (VALUE self)
{
	rb_map* st = NULL;
	Data_Get_Struct(self, rb_map, st);
	if (!st)
		rb_raise (rb_eException, "No Map Object");

	if ((*st).empty()) {
		return Qnil;
	} else {
		rb_map_iterator back = (*st).end();
		back--;
		VALUE r = rb_ary_new();
		rb_ary_push(r,rb_str_new2(back->first));
		rb_ary_push(r,back->second);
		(*st).erase(back);
		return r;
	}
}


static VALUE sptm_size (VALUE self)
{
	rb_map* st = NULL;
	Data_Get_Struct(self, rb_map, st);
	if (!st)
		rb_raise (rb_eException, "No Map Object");

	return INT2NUM((*st).size());
}


static VALUE sptm_max_size (VALUE self)
{
	rb_map* st = NULL;
	Data_Get_Struct(self, rb_map, st);
	if (!st)
		rb_raise (rb_eException, "No Map Object");

	return INT2NUM((*st).max_size());
}

static VALUE sptm_clear (VALUE self)
{
	rb_map* st = NULL;
	Data_Get_Struct(self, rb_map, st);
	if (!st)
		rb_raise (rb_eException, "No Map Object");

	(*st).clear();
	return self;
}

static VALUE sptm_empty (VALUE self)
{
	rb_map* st = NULL;
	Data_Get_Struct(self, rb_map, st);
	if (!st)
		rb_raise (rb_eException, "No Map Object");

	if ((*st).empty()) {
		return Qtrue;
	} else {
		return Qfalse;
	}
}

static VALUE sptm_to_s (VALUE self)
{
	VALUE s = rb_str_new2("");

	rb_map* st = NULL;
	rb_map_iterator q_iterator;
	Data_Get_Struct(self, rb_map, st);
	if (!st)
		rb_raise (rb_eException, "No Map Object");

	for ( q_iterator = (*st).begin(); q_iterator != (*st).end(); q_iterator++ ) {
		rb_str_concat(s,rb_str_new2(q_iterator->first));
		rb_str_concat(s,rb_convert_type(q_iterator->second, T_STRING, "String", "to_str"));
	} 

	return rb_str_to_str(s);
}
	
static VALUE sptm_to_a (VALUE self)
{
	VALUE ary = rb_ary_new();

	rb_map* st = NULL;
	rb_map_iterator q_iterator;
	Data_Get_Struct(self, rb_map, st);
	if (!st)
		rb_raise (rb_eException, "No Map Object");

	for ( q_iterator = (*st).begin(); q_iterator != (*st).end(); q_iterator++ ) {
		rb_ary_push(ary,rb_str_new2(q_iterator->first));
		rb_ary_push(ary,q_iterator->second);
	}

	return ary;
}

static VALUE sptm_inspect (VALUE self)
{
	VALUE s = rb_str_new2("{");
	VALUE arrow = rb_str_new2("=>");
	VALUE comma = rb_str_new2(",");

	cout << "*1\n";

	rb_map* st = NULL;
	rb_map_iterator q_iterator;
	rb_map_iterator last_q_iterator;
	rb_map_iterator before_last_q_iterator;
	Data_Get_Struct(self, rb_map, st);
	if (!st)
		rb_raise (rb_eException, "No Map Object");

	cout << "*1\n";
	if (!((*st).end() == (*st).begin())) {
		before_last_q_iterator = last_q_iterator = (*st).end();
		before_last_q_iterator--;

		cout << "*1\n";
		for ( q_iterator = (*st).begin(); q_iterator != last_q_iterator; q_iterator++ ) {
		cout << "*1\n";
			rb_str_concat(s,rb_inspect(rb_str_new2((*q_iterator).first)));
			rb_str_concat(s,arrow);
			rb_str_concat(s,rb_inspect((*q_iterator).second));
			if (q_iterator != before_last_q_iterator)
				rb_str_concat(s,comma);
		}
	}

	rb_str_concat(s,rb_str_new2("}"));

	return rb_str_to_str(s);
}

static VALUE sptm_first (VALUE self)
{
	rb_map* st = NULL;
	Data_Get_Struct(self, rb_map, st);
	if (!st)
		rb_raise (rb_eException, "No Map Object");

	if ((*st).empty()) {
		return Qnil;
	} else {
		rb_map_iterator front = (*st).begin();
		VALUE r = rb_ary_new();
		rb_ary_push(r,rb_str_new2(front->first));
		rb_ary_push(r,front->second);
		return r;
	}
}

static VALUE sptm_last (VALUE self)
{
	rb_map* st = NULL;
	Data_Get_Struct(self, rb_map, st);
	if (!st)
		rb_raise (rb_eException, "No Map Object");

	if ((*st).empty()) {
		return Qnil;
	} else {
		rb_map_iterator back = (*st).end();
		back--;
		VALUE r = rb_ary_new();
		rb_ary_push(r,rb_str_new2(back->first));
		rb_ary_push(r,back->second);
		return r;
	}
}

/*
static VALUE sptm_replace (VALUE self, VALUE new_st)
{
	rb_map* st = NULL;
	rb_map* nst = NULL;
	rb_map_iterator q_iterator;
	Data_Get_Struct(self, rb_map, st);
	Data_Get_Struct(new_st, rb_map, nst);
	if (!st)
		rb_raise (rb_eException, "No Map Object");

	if (!nst)
		rb_raise (rb_eException, "No Map object to copy");

	(*st).clear();
	for ( q_iterator = (*nst).begin(); q_iterator != (*nst).end(); q_iterator++ ) {
		(*st).push_back(*q_iterator);
	}

	return self;
}
*/


static VALUE sptm_insert (VALUE self, VALUE key, VALUE val)
{
	rb_map* st = NULL;
	std::pair<rb_map_iterator, bool> rv;
	std::pair<char *,VALUE> sp;
	char * skey;
	char * svp;

	svp = StringValuePtr(key);
	skey = new char[strlen(svp)+1];
	strcpy(skey,svp);

	Data_Get_Struct(self, rb_map, st);

	if (!st)
		rb_raise (rb_eException, "No Map Object");

	sp = make_pair(skey,val);
	rv = (*st).insert(sp);
	if (!rv.second) {
		(*st).erase(rv.first);
		(*st).insert(sp);
	}

	return self;
}

static VALUE sptm_at (VALUE self, VALUE key)
{
	rb_map* st = NULL;
	rb_map_iterator q_iterator;

	char * skey = StringValuePtr(key);

	Data_Get_Struct(self, rb_map, st);

	if (!st)
		rb_raise (rb_eException, "No Map Object");

	q_iterator = (*st).find(skey);
	if (q_iterator == (*st).end()) {
		return Qnil;
	} else {
		return q_iterator->second;
	}
}


static VALUE sptm_delete (VALUE self, VALUE key)
{
	rb_map* st = NULL;
	rb_map_iterator q_iterator;

	char * skey = StringValuePtr(key);

	Data_Get_Struct(self, rb_map, st);

	if (!st)
		rb_raise (rb_eException, "No Map Object");

	q_iterator = (*st).find(skey);
	if (q_iterator == (*st).end()) {
		return Qnil;
	} else {
		(*st).erase(q_iterator);
	}

	return self;
}

/*
static VALUE sptm_delete_value (VALUE self, VALUE obj)
{
	rb_map* st = NULL;
	rb_map_iterator q_iterator;
	rb_map_iterator last_q_iterator;

	Data_Get_Struct(self, rb_map, st);

	if (!st)
		rb_raise (rb_eException, "No Map Object");

	last_q_iterator = (*st).end();
	for ( q_iterator = (*st).begin(); q_iterator != last_q_iterator; q_iterator++ ) {
		if (rb_equal(q_iterator->second, obj)) {
			(*st).erase(q_iterator);
			break;
		}
	}

	return self;
}
*/
 
static VALUE sptm_each (VALUE self)
{
	rb_map* st = NULL;
	rb_map_iterator q_iterator;
	rb_map_iterator last_q_iterator;
	
	Data_Get_Struct(self, rb_map, st);

	if (!st)
		rb_raise (rb_eException, "No Map Object");

	last_q_iterator = (*st).end();
	for ( q_iterator = (*st).begin(); q_iterator != last_q_iterator; q_iterator++ ) {
		rb_yield_values(2,rb_str_new2(q_iterator->first),q_iterator->second);
	}
	
	return self;
}

static VALUE sptm_index (VALUE self, VALUE match_obj)
{
	rb_map* st = NULL;
	rb_map_iterator q_iterator;
	rb_map_iterator last_q_iterator;

	Data_Get_Struct(self, rb_map, st);

	if (!st)
		rb_raise (rb_eException, "No Map Object");

	last_q_iterator = (*st).end();
	for ( q_iterator = (*st).begin(); q_iterator != last_q_iterator; q_iterator++ ) {
		if (rb_equal(q_iterator->second, match_obj)) {
			return rb_str_new2(q_iterator->first);
		}
	}
	return Qnil;
}

static VALUE sptm_keys (VALUE self)
{
	rb_map* st = NULL;
	rb_map_iterator q_iterator;
	rb_map_iterator last_q_iterator;

	Data_Get_Struct(self, rb_map, st);

	if (!st)
		rb_raise (rb_eException, "No Map Object");

	last_q_iterator = (*st).end();
	VALUE r = rb_ary_new();
	for ( q_iterator = (*st).begin(); q_iterator != last_q_iterator; q_iterator++ ) {
		rb_ary_push(r,rb_str_new2(q_iterator->first));
	}

	return r;
}

static VALUE sptm_values (VALUE self)
{
	rb_map* st = NULL;
	rb_map_iterator q_iterator;
	rb_map_iterator last_q_iterator;

	Data_Get_Struct(self, rb_map, st);

	if (!st)
		rb_raise (rb_eException, "No Map Object");

	last_q_iterator = (*st).end();
	VALUE r = rb_ary_new();
	for ( q_iterator = (*st).begin(); q_iterator != last_q_iterator; q_iterator++ ) {
		rb_ary_push(r,q_iterator->second);
	}

	return r;
}

/**********************
Init_sptm
**********************/

extern "C" void Init_map()
{
	SwiftcoreModule = rb_define_module ("Swiftcore");
	MapClass = rb_define_class_under (SwiftcoreModule, "Map", rb_cObject);

	rb_define_module_function (MapClass, "new", (VALUE(*)(...))sptm_new, 0);
	rb_define_method (MapClass, "shift", (VALUE(*)(...))sptm_pop_front,0);
	rb_define_method (MapClass, "pop", (VALUE(*)(...))sptm_pop_back,0);
	rb_define_method (MapClass, "size", (VALUE(*)(...))sptm_size,0);
	rb_define_method (MapClass, "length", (VALUE(*)(...))sptm_size,0);
	rb_define_method (MapClass, "max_size", (VALUE(*)(...))sptm_max_size,0);
	rb_define_method (MapClass, "clear", (VALUE(*)(...))sptm_clear,0);
	rb_define_method (MapClass, "empty?", (VALUE(*)(...))sptm_empty,0);
	rb_define_method (MapClass, "to_s", (VALUE(*)(...))sptm_to_s,0);
	rb_define_method (MapClass, "to_a", (VALUE(*)(...))sptm_to_a,0);
	rb_define_method (MapClass, "first", (VALUE(*)(...))sptm_first,0);
	rb_define_method (MapClass, "last", (VALUE(*)(...))sptm_last,0);
	//rb_define_method (MapClass, "parent", (VALUE(*)(...))sptm_parent,0);
	//rb_define_method (MapClass, "replace", (VALUE(*)(...))sptm_replace,1);
	rb_define_method (MapClass, "inspect", (VALUE(*)(...))sptm_inspect,0);
	rb_define_method (MapClass, "at", (VALUE(*)(...))sptm_at,1);
	rb_define_method (MapClass, "[]", (VALUE(*)(...))sptm_at,1);
	rb_define_method (MapClass, "delete", (VALUE(*)(...))sptm_delete,1);
	rb_define_method (MapClass, "insert", (VALUE(*)(...))sptm_insert,2);
	rb_define_method (MapClass, "[]=", (VALUE(*)(...))sptm_insert,2);
	rb_define_method (MapClass, "each", (VALUE(*)(...))sptm_each,0);
	rb_define_method (MapClass, "index", (VALUE(*)(...))sptm_index,1);
	rb_define_method (MapClass, "keys", (VALUE(*)(...))sptm_keys,0);
	rb_define_method (MapClass, "values", (VALUE(*)(...))sptm_values,0);

/*    ==   []   []   []=   clear   default   default=   default_proc   delete   delete_if   each   each_key   each_pair   each_value   empty?   fetch   has_key?   has_value?   include?   index   indexes   indices   initialize_copy   inspect   invert   key?   keys   length   member?   merge   merge!   new   pretty_print   pretty_print_cycle   rehash   reject   reject!   replace   select   shift   size   sort   store   to_a   to_hash   to_s   to_yaml   update   value?   values   values_at  */
//	rb_include_module (MapClass, rb_mEnumerable);
}
