#ifndef SRC_HANDLE_MAP_H_
#define SRC_HANDLE_MAP_H_

#include <map>

#include "common.h"
#include "unsafe_persistent.h"

class HandleMap : public node::ObjectWrap {
 public:
  static void Initialize(Handle<Object> target);

 private:
  typedef std::map<WatcherHandle, NanUnsafePersistent<Value> > Map;

  HandleMap();
  virtual ~HandleMap();

  bool Has(WatcherHandle key) const;
  bool Erase(WatcherHandle key);
  void Clear();

  static void DisposeHandle(NanUnsafePersistent<Value>& value);

  static NAN_METHOD(New);
  static NAN_METHOD(Add);
  static NAN_METHOD(Get);
  static NAN_METHOD(Has);
  static NAN_METHOD(Values);
  static NAN_METHOD(Remove);
  static NAN_METHOD(Clear);

  Map map_;
};

#endif  // SRC_HANDLE_MAP_H_
