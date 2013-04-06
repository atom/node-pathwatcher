#include "common.h"

void Init(Handle<Object> exports) {
  CommonInit();
  PlatformInit();

  exports->Set(String::NewSymbol("setCallback"),
      FunctionTemplate::New(SetCallback)->GetFunction());
  exports->Set(String::NewSymbol("watch"),
      FunctionTemplate::New(Watch)->GetFunction());
  exports->Set(String::NewSymbol("unwatch"),
      FunctionTemplate::New(Unwatch)->GetFunction());
}

NODE_MODULE(pathwatcher, Init)

