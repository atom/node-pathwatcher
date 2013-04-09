# Path Watcher Node Module

## Install

```bash
npm install pathwatcher
```

## Usage

### watch(filename, [listener])

Watch for changes on `filename`, where `filename` is either a file or a
directory. The returned object is a PathWatcher.

The listener callback gets two arguments `(event, path)`. `event` is either
'rename' or 'change', and `path` is the path of the file which triggered the
event.

### PathWatcher.close()

Stop watching for changes on the given `PathWatcher`.
