# Path Watcher Node module
[![mac OS Build Status](https://travis-ci.org/atom/node-pathwatcher.svg?branch=master)](https://travis-ci.org/atom/node-pathwatcher) [![Windows Build Status](https://ci.appveyor.com/api/projects/status/li8dkoucdrc2ryts/branch/master?svg=true
)](https://ci.appveyor.com/project/Atom/node-pathwatcher) [![Depenency Status](https://david-dm.org/atom/node-pathwatcher/status.svg)](https://david-dm.org/atom/node-pathwatcher)

## Installing

```bash
npm install pathwatcher
```

## Building

  * Clone the repository
  * Run `npm install` to install the dependencies
  * Run `npm test` to run the specs

## Using

```coffeescript
PathWatcher = require 'pathwatcher'
```

### PathWatcher.watch(filename, [options], [listener])

Watch for changes on `filename`, where `filename` is either a file or a
directory. The returned object is a `PathWatcher`.

The options argument is a javascript object:
`{ recursive: true }` will allow pathWatcher to watch a Windows directory
recursively for any changes to files or directories under it.  This option has
no effect on non-Windows operating systems.

The listener callback gets two arguments `(event, path)`. `event` can be `rename`,
`delete` or `change`, and `path` is the path of the file which triggered the
event.

For directories, the `change` event is emitted when a file or directory under
the watched directory got created or deleted. And if the `PathWatcher.watch` is
not recursive i.e. non-Windows operating systems or if the option has not
been enabled on Windows, changes of subdirectories under the watched directory
would not be detected.

### PathWatcher.close()

Stop watching for changes on the given `PathWatcher`.
