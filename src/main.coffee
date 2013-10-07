binding = require('bindings')('pathwatcher.node')
HandleMap = binding.HandleMap
{EventEmitter} = require 'events'
fs = require 'fs'

handleWatchers = new HandleMap

binding.setCallback (event, handle, path) ->
  handleWatchers.get(handle).onEvent(event, path) if handleWatchers.has(handle)

class HandleWatcher extends EventEmitter
  constructor: (@path) ->
    @start()

  onEvent: (event, path) ->
    switch event
      when 'rename'
        # Detect atomic write.
        @close()
        detectRename = =>
          fs.stat @path, (err) =>
            if err # original file is gone it's a rename.
              @path = path
              @start()
              @emit('change', 'rename', path)
            else # atomic write.
              @start()
              @emit('change', 'change', null)
        setTimeout(detectRename, 100)
      when 'delete'
        @emit('change', 'delete', null)
        @close()
      else
        @emit('change', event, path)

  start: ->
    @handle = binding.watch(@path)
    handleWatchers.add(@handle, this)

  closeIfNoListener: ->
    @close() if @listeners('change').length is 0

  close: ->
    if handleWatchers.has(@handle)
      binding.unwatch(@handle)
      handleWatchers.remove(@handle)

class PathWatcher extends EventEmitter
  handleWatcher: null

  constructor: (path, callback) ->
    for watcher in handleWatchers.values()
      if watcher.path is path
        @handleWatcher = watcher
        break

    @handleWatcher ?= new HandleWatcher(path)

    @onChange = (event, path) =>
      callback.call(this, event, path) if typeof callback is 'function'
      @emit('change', event, path)

    @handleWatcher.on('change', @onChange)

  close: ->
    @handleWatcher.removeListener('change', @onChange)
    @handleWatcher.closeIfNoListener()

exports.watch = (path, callback) ->
  path = require('path').resolve(path)
  new PathWatcher(path, callback)

exports.closeAllWatchers = ->
  watcher.close() for watcher in handleWatchers.values()
  handleWatchers = new HandleMap

exports.getWatchedPaths = ->
  paths = []
  paths.push(watcher.path) for watcher in handleWatchers.values()
  paths
