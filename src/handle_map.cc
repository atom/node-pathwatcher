#include "handle_map.h"

#include <algorithm>

#include "node_internals.h"

HandleMap::HandleMap() {
}

HandleMap::~HandleMap() {
  for (Map::const_iterator iter = map_.begin(); iter != map_.end(); ++iter)
    DisposeHandle(iter->second);
}

bool HandleMap::Has(WatcherHandle key) const {
  return map_.find(key) != map_.end();
}

bool HandleMap::Erase(WatcherHandle key) {
  Map::iterator iter = map_.find(key);
  if (iter == map_.end())
    return false;

  DisposeHandle(iter->second);
  map_.erase(iter);
  return true;
}

void HandleMap::DisposeHandle(Persistent<Value> value) {
  value.Dispose();
  value.Clear();
}

// static
Handle<Value> HandleMap::New(const Arguments& args) {
  HandleMap* obj = new HandleMap();
  obj->Wrap(args.This());
  return args.This();
}

// static
Handle<Value> HandleMap::Add(const Arguments& args) {
  if (!IsV8ValueWatcherHandle(args[0]))
    return node::ThrowTypeError("Bad argument");

  HandleMap* obj = ObjectWrap::Unwrap<HandleMap>(args.This());
  WatcherHandle key = V8ValueToWatcherHandle(args[0]);
  if (obj->Has(key))
    return node::ThrowError("Duplicate key");

  obj->map_[key] = Persistent<Value>::New(args[1]);
  return Undefined();
}

// static
Handle<Value> HandleMap::Get(const Arguments& args) {
  if (!IsV8ValueWatcherHandle(args[0]))
    return node::ThrowTypeError("Bad argument");

  HandleMap* obj = ObjectWrap::Unwrap<HandleMap>(args.This());
  WatcherHandle key = V8ValueToWatcherHandle(args[0]);
  if (!obj->Has(key))
    return node::ThrowError("Invalid key");

  return obj->map_[key];
}

// static
Handle<Value> HandleMap::Has(const Arguments& args) {
  if (!IsV8ValueWatcherHandle(args[0]))
    return node::ThrowTypeError("Bad argument");

  HandleMap* obj = ObjectWrap::Unwrap<HandleMap>(args.This());
  return Boolean::New(obj->Has(V8ValueToWatcherHandle(args[0])));
}

// static
Handle<Value> HandleMap::Values(const Arguments& args) {
  HandleMap* obj = ObjectWrap::Unwrap<HandleMap>(args.This());

  size_t i = 0;
  Handle<Array> keys = Array::New(obj->map_.size());
  for (Map::const_iterator iter = obj->map_.begin();
       iter != obj->map_.end();
       ++iter, ++i) {
    keys->Set(i, iter->second);
  }

  return keys;
}

// static
Handle<Value> HandleMap::Remove(const Arguments& args) {
  if (!IsV8ValueWatcherHandle(args[0]))
    return node::ThrowTypeError("Bad argument");

  HandleMap* obj = ObjectWrap::Unwrap<HandleMap>(args.This());
  if (!obj->Erase(V8ValueToWatcherHandle(args[0])))
    return node::ThrowError("Invalid key");

  return Undefined();
}

// static
void HandleMap::Initialize(Handle<Object> target) {
  HandleScope scope;

  Local<FunctionTemplate> t = FunctionTemplate::New(HandleMap::New);
  t->InstanceTemplate()->SetInternalFieldCount(1);
  t->SetClassName(String::NewSymbol("HandleMap"));

  NODE_SET_PROTOTYPE_METHOD(t, "add", Add);
  NODE_SET_PROTOTYPE_METHOD(t, "get", Get);
  NODE_SET_PROTOTYPE_METHOD(t, "has", Has);
  NODE_SET_PROTOTYPE_METHOD(t, "values", Values);
  NODE_SET_PROTOTYPE_METHOD(t, "remove", Remove);

  target->Set(String::NewSymbol("HandleMap"), t->GetFunction());
}
