#include <deque>
#include <iostream>
#include <string>
using namespace std;

#include <ruby.h>

static VALUE SwiftcoreModule;
static VALUE DequeClass;


static void deque_mark (deque<VALUE>* dq)
{
	deque<VALUE>::iterator q_iterator;
	if (dq) {
		for ( q_iterator = (*dq).begin(); q_iterator != (*dq).end(); q_iterator++ ) {
			rb_gc_mark(*q_iterator);
		}
	}
}

static void deque_free (deque<VALUE>* dq)
{
	if (dq)
		delete dq;
}

static VALUE deque_new (VALUE self)
{
	deque<VALUE>* dq = new deque<VALUE>;
	VALUE v = Data_Wrap_Struct (DequeClass, deque_mark, deque_free, dq);
	return v;
}

static VALUE deque_push_front (VALUE self, VALUE obj)
{
	deque<VALUE>* dq = NULL;
	Data_Get_Struct (self, deque<VALUE>, dq);
	if (!dq)
		rb_raise (rb_eException, "No Deque Object");

	(*dq).push_front(obj);

	return self;
}

static VALUE deque_pop_front (VALUE self)
{
	deque<VALUE>* dq = NULL;
	Data_Get_Struct(self, deque<VALUE>, dq);
	if (!dq)
		rb_raise (rb_eException, "No Deque Object");

	if ((*dq).empty()) {
		return Qnil;
	} else {
		VALUE r = (*dq).front();
		(*dq).pop_front();
		return r;
	}
}

static VALUE deque_push_back (VALUE self, VALUE obj)
{
	deque<VALUE>* dq = NULL;
	Data_Get_Struct (self, deque<VALUE>, dq);
	if (!dq)
		rb_raise (rb_eException, "No Deque Object");

	(*dq).push_back(obj);

	return self;
}

static VALUE deque_pop_back (VALUE self)
{
	deque<VALUE>* dq = NULL;
	Data_Get_Struct(self, deque<VALUE>, dq);
	if (!dq)
		rb_raise (rb_eException, "No Deque Object");

	if ((*dq).empty()) {
		return Qnil;
	} else {
		VALUE r = (*dq).back();
		(*dq).pop_back();
		return r;
	}
}

static VALUE deque_size (VALUE self)
{
	deque<VALUE>* dq = NULL;
	Data_Get_Struct(self, deque<VALUE>, dq);
	if (!dq)
		rb_raise (rb_eException, "No Deque Object");

	return INT2NUM((*dq).size());
}

static VALUE deque_max_size (VALUE self)
{
	deque<VALUE>* dq = NULL;
	Data_Get_Struct(self, deque<VALUE>, dq);
	if (!dq)
		rb_raise (rb_eException, "No Deque Object");

	return INT2NUM((*dq).max_size());
}

static VALUE deque_clear (VALUE self)
{
	deque<VALUE>* dq = NULL;
	Data_Get_Struct(self, deque<VALUE>, dq);
	if (!dq)
		rb_raise (rb_eException, "No Deque Object");

	(*dq).clear();
	return self;
}

static VALUE deque_empty (VALUE self)
{
	deque<VALUE>* dq = NULL;
	Data_Get_Struct(self, deque<VALUE>, dq);
	if (!dq)
		rb_raise (rb_eException, "No Deque Object");

	if ((*dq).empty()) {
		return Qtrue;
	} else {
		return Qfalse;
	}
}

static VALUE deque_to_s (VALUE self)
{
	VALUE s = rb_str_new2("");
	ID to_s = rb_intern("to_s");
	ID concat = rb_intern("concat");

	deque<VALUE>* dq = NULL;
	deque<VALUE>::iterator q_iterator;
	Data_Get_Struct(self, deque<VALUE>, dq);
	if (!dq)
		rb_raise (rb_eException, "No Deque Object");

/*
	for ( q_iterator = (*dq).begin(); q_iterator != (*dq).end(); q_iterator++ ) {
		rb_funcall(s,concat,1,rb_funcall(*q_iterator,to_s,0));
	} 
*/

	for ( q_iterator = (*dq).begin(); q_iterator != (*dq).end(); q_iterator++ ) {
		s = rb_str_concat(s,rb_funcall(*q_iterator, to_s, 0));
	}
	return rb_str_to_str(s);
}

/*
static VALUE deque_join (VALUE self, VALUE delimiter)
{
	VALUE s = rb_str_new2("");
	ID to_s = rb_intern("to_s");
	ID concat = rb_intern("concat");

	deque<VALUE>* dq = NULL;
	deque<VALUE>::iterator q_iterator;
	Data_Get_Struct(self, deque<VALUE>, dq);
	if (!dq)
		rb_raise (rb_eException, "No Deque Object");

	for ( q_iterator = (*dq).begin(); q_iterator != (*dq).end(); q_iterator++ ) {
		rb_funcall(s,concat,1,rb_funcall(*q_iterator,to_s,0));
	} 

	return rb_str_to_str(s);
}
*/
static VALUE deque_to_a (VALUE self)
{
	VALUE ary = rb_ary_new();
	ID push = rb_intern("push");

	deque<VALUE>* dq = NULL;
	deque<VALUE>::iterator q_iterator;
	Data_Get_Struct(self, deque<VALUE>, dq);
	if (!dq)
		rb_raise (rb_eException, "No Deque Object");

	for ( q_iterator = (*dq).begin(); q_iterator != (*dq).end(); q_iterator++ ) {
		//rb_funcall(ary,push,1,*q_iterator);
		rb_ary_push(ary,*q_iterator);
	}

	return ary;
}

static VALUE deque_inspect (VALUE self)
{
	VALUE s = rb_str_new2("[");
	VALUE comma = rb_str_new2(",");
	ID inspect = rb_intern("inspect");
	ID concat = rb_intern("concat");

	deque<VALUE>* dq = NULL;
	deque<VALUE>::iterator q_iterator;
	deque<VALUE>::iterator last_q_iterator;
	Data_Get_Struct(self, deque<VALUE>, dq);
	if (!dq)
		rb_raise (rb_eException, "No Deque Object");

	last_q_iterator = (*dq).end();

	for ( q_iterator = (*dq).begin(); q_iterator != last_q_iterator; q_iterator++ ) {
//		rb_funcall(s,concat,1,rb_funcall(*q_iterator,inspect,0));
		rb_str_concat(s,rb_funcall(*q_iterator,inspect,0));
		if (q_iterator != (last_q_iterator - 1))
//			rb_funcall(s,concat,1,comma);
			rb_str_concat(s,comma);
	}
//	rb_funcall(s,concat,1,rb_str_new2("]"));
	rb_str_concat(s,rb_str_new2("]"));

	return rb_str_to_str(s);
}

static VALUE deque_first (VALUE self)
{
	deque<VALUE>* dq = NULL;
	Data_Get_Struct(self, deque<VALUE>, dq);
	if (!dq)
		rb_raise (rb_eException, "No Deque Object");

	return (*dq).front();
}

static VALUE deque_last (VALUE self)
{
	deque<VALUE>* dq = NULL;
	Data_Get_Struct(self, deque<VALUE>, dq);
	if (!dq)
		rb_raise (rb_eException, "No Deque Object");

	return (*dq).back();
}

static VALUE deque_replace (VALUE self, VALUE new_dq)
{
	deque<VALUE>* dq = NULL;
	deque<VALUE>* ndq = NULL;
	deque<VALUE>::iterator q_iterator;
	Data_Get_Struct(self, deque<VALUE>, dq);
	Data_Get_Struct(new_dq, deque<VALUE>, ndq);
	if (!dq)
		rb_raise (rb_eException, "No Deque Object");

	if (!ndq)
		rb_raise (rb_eException, "No Deque object to copy");

	(*dq).clear();
	for ( q_iterator = (*ndq).begin(); q_iterator != (*ndq).end(); q_iterator++ ) {
		(*dq).push_back(*q_iterator);
	}

	return self;
}

static VALUE deque_at (VALUE self, VALUE pos)
{
	deque<VALUE>* dq = NULL;
	long c_pos = rb_num2long(pos);

	Data_Get_Struct(self, deque<VALUE>, dq);

	if (!dq)
		rb_raise (rb_eException, "No Deque Object");

	if ((c_pos < 0) || (c_pos >= (*dq).size()))
		rb_raise (rb_eException, "Out of bounds index on Deque object");

   return *((*dq).begin() + c_pos);
}

static VALUE deque_delete (VALUE self, VALUE obj)
{
	deque<VALUE>* dq = NULL;
	deque<VALUE>::iterator q_iterator;
	deque<VALUE>::iterator last_q_iterator;

	Data_Get_Struct(self, deque<VALUE>, dq);

	if (!dq)
		rb_raise (rb_eException, "No Deque Object");

	last_q_iterator = (*dq).end();
	for ( q_iterator = (*dq).begin(); q_iterator != last_q_iterator; q_iterator++ ) {
		if (rb_equal(*q_iterator, obj)) {
			(*dq).erase(q_iterator);
			break;
		}
	}

	return self;
}

static VALUE deque_delete_at (VALUE self, VALUE pos)
{
	deque<VALUE>* dq = NULL;
	deque<VALUE>::iterator q_iterator;
	long c_pos = rb_num2long(pos);

	Data_Get_Struct(self, deque<VALUE>, dq);
	
	if (!dq)
		rb_raise (rb_eException, "No Deque Object");

	if ((c_pos < 0) || (c_pos >= (*dq).size()))
		rb_raise (rb_eException, "Out of bounds index on Deque object");

	q_iterator = (*dq).begin();
	for ( int n = 0; n < c_pos; n++) {
		q_iterator++;
	}
	(*dq).erase(q_iterator);

	return *q_iterator;
}

static VALUE deque_insert (VALUE self, VALUE pos, VALUE val)
{
	deque<VALUE>* dq = NULL;
	deque<VALUE>::iterator q_iterator;
	long c_pos = rb_num2long(pos);

	Data_Get_Struct(self, deque<VALUE>, dq);

	if (!dq)
		rb_raise (rb_eException, "No Deque Object");

	if ((c_pos < 0) || (c_pos > (*dq).size()))
		rb_raise (rb_eException, "Out of bounds index on Deque object");

	q_iterator = (*dq).begin() + c_pos;
	(*dq).insert(q_iterator,val);

	return self;
}

static VALUE deque_assign_at (VALUE self, VALUE pos, VALUE val)
{
	deque_delete(self,pos);
	deque_insert(self,pos,val);

	return self;
}

static VALUE deque_each (VALUE self)
{
	deque<VALUE>* dq = NULL;
	deque<VALUE>::iterator q_iterator;
	deque<VALUE>::iterator last_q_iterator;
	
	Data_Get_Struct(self, deque<VALUE>, dq);

	if (!dq)
		rb_raise (rb_eException, "No Deque Object");

	last_q_iterator = (*dq).end();
	for ( q_iterator = (*dq).begin(); q_iterator != last_q_iterator; q_iterator++ ) {
		rb_yield(*q_iterator);
	}
	
	return self;
}

static VALUE deque_index (VALUE self, VALUE match_obj)
{
	deque<VALUE>* dq = NULL;
	deque<VALUE>::iterator q_iterator;
	deque<VALUE>::iterator last_q_iterator;

	Data_Get_Struct(self, deque<VALUE>, dq);
	if (!dq)
		rb_raise (rb_eException, "No Deque Object");

	last_q_iterator = (*dq).end();
	int pos = 0;
	for ( q_iterator = (*dq).begin(); q_iterator != last_q_iterator; q_iterator++ ) {
		if (rb_equal(*q_iterator,match_obj) == Qtrue) {
			return INT2NUM(pos);
		} else {
			pos++;
		}
	}
	return Qnil;
}

/**********************
Init_deque
**********************/

extern "C" void Init_deque()
{
	SwiftcoreModule = rb_define_module ("Swiftcore");
	DequeClass = rb_define_class_under (SwiftcoreModule, "Deque", rb_cObject);

	rb_define_module_function (DequeClass, "new", (VALUE(*)(...))deque_new, 0);
	rb_define_method (DequeClass, "unshift", (VALUE(*)(...))deque_push_front,1);
	rb_define_method (DequeClass, "shift", (VALUE(*)(...))deque_pop_front,0);
	rb_define_method (DequeClass, "push", (VALUE(*)(...))deque_push_back,1);
	rb_define_method (DequeClass, "<<", (VALUE(*)(...))deque_push_back,1);
	rb_define_method (DequeClass, "pop", (VALUE(*)(...))deque_pop_back,0);
	rb_define_method (DequeClass, "size", (VALUE(*)(...))deque_size,0);
	rb_define_method (DequeClass, "length", (VALUE(*)(...))deque_size,0);
	rb_define_method (DequeClass, "max_size", (VALUE(*)(...))deque_max_size,0);
	rb_define_method (DequeClass, "clear", (VALUE(*)(...))deque_clear,0);
	rb_define_method (DequeClass, "empty?", (VALUE(*)(...))deque_empty,0);
	rb_define_method (DequeClass, "to_s", (VALUE(*)(...))deque_to_s,0);
	rb_define_method (DequeClass, "to_a", (VALUE(*)(...))deque_to_a,0);
	rb_define_method (DequeClass, "first", (VALUE(*)(...))deque_first,0);
	rb_define_method (DequeClass, "last", (VALUE(*)(...))deque_last,0);
	rb_define_method (DequeClass, "replace", (VALUE(*)(...))deque_replace,1);
	rb_define_method (DequeClass, "inspect", (VALUE(*)(...))deque_inspect,0);
	rb_define_method (DequeClass, "at", (VALUE(*)(...))deque_at,1);
	rb_define_method (DequeClass, "[]", (VALUE(*)(...))deque_at,1);
	rb_define_method (DequeClass, "delete", (VALUE(*)(...))deque_delete,1);
	rb_define_method (DequeClass, "delete_at", (VALUE(*)(...))deque_delete_at,1);
	rb_define_method (DequeClass, "insert", (VALUE(*)(...))deque_insert,2);
	rb_define_method (DequeClass, "[]=", (VALUE(*)(...))deque_assign_at,2);
	rb_define_method (DequeClass, "each", (VALUE(*)(...))deque_each,0);
	rb_define_method (DequeClass, "index", (VALUE(*)(...))deque_index,1);

	rb_include_module (DequeClass, rb_mEnumerable);
}
