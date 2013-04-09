binding = require('bindings')('pathwatcher.node')
{EventEmitter} = require 'events'
fs = require 'fs'
util = require 'util'

handleWatchers = {}

binding.setCallback (event, handle, path) ->
  handleWatchers[handle]?.onEvent(event, path)

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
    handleWatchers[@handle] = this

  closeIfNoListener: ->
    @close() if @listeners('change').length is 0

  close: ->
    if handleWatchers[@handle]?
      binding.unwatch(@handle)
      delete handleWatchers[@handle]

class PathWatcher extends EventEmitter
  constructor: (path, callback) ->
    @handleWatcher = null
    for handle, watcher of handleWatchers
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
  watcher.close() for handle, watcher of handleWatchers
  handleWatchers = {}

exports.getWatchedPaths = ->
  paths = []
  paths.push(watcher.path) for handle, watcher of handleWatchers
  paths
