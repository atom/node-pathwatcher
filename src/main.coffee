binding = require '../build/Release/pathwatcher.node'
{HandleMap} = binding
{EventEmitter} = require 'events'
{Emitter} = require 'event-kit'
fs = require 'fs'
path = require 'path'

handleWatchers = null

class HandleWatcher
  constructor: (@path) ->
    @emitter = new Emitter()
    @start()

  onEvent: (event, filePath, oldFilePath) ->
    filePath = path.normalize(filePath) if filePath
    oldFilePath = path.normalize(oldFilePath) if oldFilePath

    switch event
      when 'rename'
        # Detect atomic write.
        @close()
        detectRename = =>
          fs.stat @path, (err) =>
            if err # original file is gone it's a rename.
              @path = filePath
              # On OS X files moved to ~/.Trash should be handled as deleted.
              if process.platform is 'darwin' and (/\/\.Trash\//).test(filePath)
                @emitter.emit('did-change', {event: 'delete', newFilePath: null})
                @close()
              else
                @start()
                @emitter.emit('did-change', {event: 'rename', newFilePath: filePath})
            else # atomic write.
              @start()
              @emitter.emit('did-change', {event: 'change', newFilePath: null})
        setTimeout(detectRename, 100)
      when 'delete'
        @emitter.emit('did-change', {event: 'delete', newFilePath: null})
        @close()
      when 'unknown'
        throw new Error("Received unknown event for path: #{@path}")
      else
        @emitter.emit('did-change', {event, newFilePath: filePath, oldFilePath: oldFilePath})

  onDidChange: (callback) ->
    @emitter.on('did-change', callback)

  start: ->
    @handle = binding.watch(@path)
    if handleWatchers.has(@handle)
      troubleWatcher = handleWatchers.get(@handle)
      troubleWatcher.close()
      console.error("The handle(#{@handle}) returned by watching #{@path} is the same with an already watched path(#{troubleWatcher.path})")
    handleWatchers.add(@handle, this)

  closeIfNoListener: ->
    @close() if @emitter.getTotalListenerCount() is 0

  close: ->
    if handleWatchers.has(@handle)
      binding.unwatch(@handle)
      handleWatchers.remove(@handle)

class PathWatcher
  isWatchingParent: false
  path: null
  handleWatcher: null

  constructor: (filePath, callback) ->
    @path = filePath
    @emitter = new Emitter()

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

    @onChange = ({event, newFilePath, oldFilePath}) =>
      switch event
        when 'rename', 'change', 'delete'
          @path = newFilePath if event is 'rename'
          callback.call(this, event, newFilePath) if typeof callback is 'function'
          @emitter.emit('did-change', {event, newFilePath})
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

    @disposable = @handleWatcher.onDidChange(@onChange)

  onDidChange: (callback) ->
    @emitter.on('did-change', callback)

  close: ->
    @emitter.dispose()
    @disposable.dispose()
    @handleWatcher.closeIfNoListener()

exports.watch = (pathToWatch, callback) ->
  unless handleWatchers?
    handleWatchers = new HandleMap
    binding.setCallback (event, handle, filePath, oldFilePath) ->
      handleWatchers.get(handle).onEvent(event, filePath, oldFilePath) if handleWatchers.has(handle)

  new PathWatcher(path.resolve(pathToWatch), callback)

exports.closeAllWatchers = ->
  if handleWatchers?
    watcher.close() for watcher in handleWatchers.values()
    handleWatchers.clear()

exports.getWatchedPaths = ->
  paths = []
  if handleWatchers?
    paths.push(watcher.path) for watcher in handleWatchers.values()
  paths

exports.File = require './file'
exports.Directory = require './directory'
