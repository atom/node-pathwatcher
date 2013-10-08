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
    @isParent = false

    # On Windows watching a file is emulated by watching its parent folder.
    if process.platform is 'win32'
      stats = fs.statSync(@path)
      @isParent = not stats.isDirectory()
      @watchedPath = require('path').dirname(@path, '..')

    @start(if @isParent then @watchedPath else @path)

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
      when 'change'
        @emit('change', 'change', filePath)
      when 'child-rename'
        if @isParent
          @onEvent('rename', filePath) if @path is oldFilePath
        else
          @onEvent('change', '')
      when 'child-delete'
        if @isParent
          @onEvent('delete', filePath) if @path is filePath
        else
          @onEvent('change', '')
      when 'child-change'
        @onEvent('change', '') if @isParent and @path is filePath
      when 'child-create'
        @onEvent('change', '') unless @isParent

  start: (path) ->
    @handle = binding.watch(path)
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
