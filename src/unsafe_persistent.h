#ifndef UNSAFE_PERSISTENT_H_
#define UNSAFE_PERSISTENT_H_

#include "nan.h"

#if NODE_VERSION_AT_LEAST(0, 11, 0)
template<class T>
struct NanUnsafePersistentTraits {
  typedef v8::Persistent<T, NanUnsafePersistentTraits<T> > HandleType;
  static const bool kResetInDestructor = false;
  template<class S, class M>
  static V8_INLINE void Copy(const Persistent<S, M>& source,
                             HandleType* dest) {
    // do nothing, just allow copy
  }
};
template<class T>
class NanUnsafePersistent : public NanUnsafePersistentTraits<T>::HandleType {
 public:
  V8_INLINE NanUnsafePersistent() {}

  template <class S>
  V8_INLINE NanUnsafePersistent(v8::Isolate* isolate, S that)
      : NanUnsafePersistentTraits<T>::HandleType(isolate, that) {
  }
};
template<typename T>
NAN_INLINE void NanAssignUnsafePersistent(
    NanUnsafePersistent<T>& handle
  , v8::Handle<T> obj) {
    handle.Reset();
    handle = NanUnsafePersistent<T>(v8::Isolate::GetCurrent(), obj);
}
template<typename T>
NAN_INLINE v8::Local<T> NanUnsafePersistentToLocal(const NanUnsafePersistent<T> &arg1) {
  return v8::Local<T>::New(v8::Isolate::GetCurrent(), arg1);
}
#define NanDisposeUnsafePersistent(handle) handle.Reset()
#else
#define NanUnsafePersistent v8::Persistent
#define NanAssignUnsafePersistent NanAssignPersistent
#define NanUnsafePersistentToLocal Nan::New
#define NanDisposeUnsafePersistent NanDisposePersistent
#endif

#endif  // UNSAFE_PERSISTENT_H_
