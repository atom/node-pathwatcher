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

### PathWatcher.watch(filename, [listener])

Watch for changes on `filename`, where `filename` is either a file or a
directory. The returned object is a `PathWatcher`.

The listener callback gets two arguments `(event, path)`. `event` can be `rename`,
`delete` or `change`, and `path` is the path of the file which triggered the
event.

For directories, the `change` event is emitted when a file or directory under
the watched directory got created or deleted. And the `PathWatcher.watch` is
not recursive, so changes of subdirectories under the watched directory would
not be detected.

### PathWatcher.close()

Stop watching for changes on the given `PathWatcher`.
