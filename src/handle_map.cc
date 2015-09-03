#include "handle_map.h"

#include <algorithm>

HandleMap::HandleMap() {
}

HandleMap::~HandleMap() {
  Clear();
}

bool HandleMap::Has(WatcherHandle key) const {
  return map_.find(key) != map_.end();
}

bool HandleMap::Erase(WatcherHandle key) {
  Map::iterator iter = map_.find(key);
  if (iter == map_.end())
    return false;

  NanDisposeUnsafePersistent(iter->second);
  map_.erase(iter);
  return true;
}

void HandleMap::Clear() {
  for (Map::iterator iter = map_.begin(); iter != map_.end(); ++iter)
    NanDisposeUnsafePersistent(iter->second);
  map_.clear();
}

// static
NAN_METHOD(HandleMap::New) {
  Nan::HandleScope scope;
  HandleMap* obj = new HandleMap();
  obj->Wrap(info.This());
  return;
}

// static
NAN_METHOD(HandleMap::Add) {
  Nan::HandleScope scope;

  if (!IsV8ValueWatcherHandle(info[0]))
    return Nan::ThrowTypeError("Bad argument");

  HandleMap* obj = Nan::ObjectWrap::Unwrap<HandleMap>(info.This());
  WatcherHandle key = V8ValueToWatcherHandle(info[0]);
  if (obj->Has(key))
    return Nan::ThrowError("Duplicate key");

  NanAssignUnsafePersistent(obj->map_[key], info[1]);
  return;
}

// static
NAN_METHOD(HandleMap::Get) {
  Nan::HandleScope scope;

  if (!IsV8ValueWatcherHandle(info[0]))
    return Nan::ThrowTypeError("Bad argument");

  HandleMap* obj = Nan::ObjectWrap::Unwrap<HandleMap>(info.This());
  WatcherHandle key = V8ValueToWatcherHandle(info[0]);
  if (!obj->Has(key))
    return Nan::ThrowError("Invalid key");

  info.GetReturnValue().Set(NanUnsafePersistentToLocal(obj->map_[key]));
}

// static
NAN_METHOD(HandleMap::Has) {
  Nan::HandleScope scope;

  if (!IsV8ValueWatcherHandle(info[0]))
    return Nan::ThrowTypeError("Bad argument");

  HandleMap* obj = Nan::ObjectWrap::Unwrap<HandleMap>(info.This());
  info.GetReturnValue().Set(Nan::New<Boolean>(obj->Has(V8ValueToWatcherHandle(info[0]))));
}

// static
NAN_METHOD(HandleMap::Values) {
  Nan::HandleScope scope;

  HandleMap* obj = Nan::ObjectWrap::Unwrap<HandleMap>(info.This());

  int i = 0;
  v8::Local<Array> keys = Nan::New<Array>(obj->map_.size());
  for (Map::const_iterator iter = obj->map_.begin();
       iter != obj->map_.end();
       ++iter, ++i) {
    keys->Set(i, NanUnsafePersistentToLocal(iter->second));
  }

  info.GetReturnValue().Set(keys);
}

// static
NAN_METHOD(HandleMap::Remove) {
  Nan::HandleScope scope;

  if (!IsV8ValueWatcherHandle(info[0]))
    return Nan::ThrowTypeError("Bad argument");

  HandleMap* obj = Nan::ObjectWrap::Unwrap<HandleMap>(info.This());
  if (!obj->Erase(V8ValueToWatcherHandle(info[0])))
    return Nan::ThrowError("Invalid key");

  return;
}

// static
NAN_METHOD(HandleMap::Clear) {
  Nan::HandleScope scope;

  HandleMap* obj = Nan::ObjectWrap::Unwrap<HandleMap>(info.This());
  obj->Clear();

  return;
}

// static
void HandleMap::Initialize(Handle<Object> target) {
  Nan::HandleScope scope;

  Local<FunctionTemplate> t = Nan::New<FunctionTemplate>(HandleMap::New);
  t->InstanceTemplate()->SetInternalFieldCount(1);
  t->SetClassName(Nan::New<String>("HandleMap").ToLocalChecked());

  Nan::SetPrototypeMethod(t, "add", Add);
  Nan::SetPrototypeMethod(t, "get", Get);
  Nan::SetPrototypeMethod(t, "has", Has);
  Nan::SetPrototypeMethod(t, "values", Values);
  Nan::SetPrototypeMethod(t, "remove", Remove);
  Nan::SetPrototypeMethod(t, "clear", Clear);

  target->Set(Nan::New<String>("HandleMap").ToLocalChecked(), t->GetFunction());
}
