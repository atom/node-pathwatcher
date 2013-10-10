binding = require('bindings')('pathwatcher.node')
HandleMap = binding.HandleMap
{EventEmitter} = require 'events'
fs = require 'fs'
path = require 'path'

handleWatchers = new HandleMap

binding.setCallback (event, handle, filePath, oldFilePath) ->
  handleWatchers.get(handle).onEvent(event, filePath, oldFilePath) if handleWatchers.has(handle)

class HandleWatcher extends EventEmitter
  constructor: (@path) ->
    @start()

  onEvent: (event, filePath, oldFilePath) ->
    switch event
      when 'rename'
        # Detect atomic write.
        @close()
        detectRename = =>
          fs.stat @path, (err) =>
            if err # original file is gone it's a rename.
              @path = filePath
              @start()
              @emit('change', 'rename', filePath)
            else # atomic write.
              @start()
              @emit('change', 'change', null)
        setTimeout(detectRename, 100)
      when 'delete'
        @emit('change', 'delete', null)
        @close()
      when 'unknown'
        throw new Error("Received unknown event for path: #{@path}")
      else
        @emit('change', event, filePath, oldFilePath)

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
  isWatchingParent: false
  path: null
  handleWatcher: null

  constructor: (filePath, callback) ->
    @path = filePath

    # On Windows watching a file is emulated by watching its parent folder.
    if process.platform is 'win32'
      stats = fs.statSync(filePath)
      @isWatchingParent = not stats.isDirectory()

    filePath = path.dirname(filePath) if @isWatchingParent
    for watcher in handleWatchers.values()
      if watcher.path is filePath
        @handleWatcher = watcher
        break

    @handleWatcher ?= new HandleWatcher(filePath)

    @onChange = (event, newFilePath, oldFilePath) =>
      switch event
        when 'rename', 'change', 'delete'
          @path = newFilePath if event is 'rename'
          callback.call(this, event, newFilePath) if typeof callback is 'function'
          @emit('change', event, newFilePath)
        when 'child-rename'
          if @isWatchingParent
            @onChange('rename', newFilePath) if @path is oldFilePath
          else
            @onChange('change', '')
        when 'child-delete'
          if @isWatchingParent
            @onChange('delete', null) if @path is newFilePath
          else
            @onChange('change', '')
        when 'child-change'
          @onChange('change', '') if @isWatchingParent and @path is newFilePath
        when 'child-create'
          @onChange('change', '') unless @isWatchingParent

    @handleWatcher.on('change', @onChange)

  close: ->
    @handleWatcher.removeListener('change', @onChange)
    @handleWatcher.closeIfNoListener()

exports.watch = (path, callback) ->
  path = require('path').resolve(path)
  new PathWatcher(path, callback)

exports.closeAllWatchers = ->
  watcher.close() for watcher in handleWatchers.values()
  handleWatchers.clear()

exports.getWatchedPaths = ->
  paths = []
  paths.push(watcher.path) for watcher in handleWatchers.values()
  paths
