#ifndef SRC_HANDLE_MAP_H_
#define SRC_HANDLE_MAP_H_

#include <map>

#include "common.h"

class HandleMap : public node::ObjectWrap {
 public:
  static void Initialize(Handle<Object> target);

 private:
  typedef std::map<WatcherHandle, Persistent<Value> > Map;

  HandleMap();
  virtual ~HandleMap();

  bool Has(WatcherHandle key) const;
  bool Erase(WatcherHandle key);

  static void DisposeHandle(Persistent<Value> value);

  static Handle<Value> New(const Arguments& args);
  static Handle<Value> Add(const Arguments& args);
  static Handle<Value> Get(const Arguments& args);
  static Handle<Value> Has(const Arguments& args);
  static Handle<Value> Values(const Arguments& args);
  static Handle<Value> Remove(const Arguments& args);

  Map map_;
};

#endif  // SRC_HANDLE_MAP_H_
