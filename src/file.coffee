crypto = require 'crypto'
path = require 'path'

_ = require 'underscore-plus'
EmitterMixin = require('emissary').Emitter
{Emitter, Disposable} = require 'event-kit'
fs = require 'fs-plus'
Grim = require 'grim'
Q = null # Defer until used
runas = null # Defer until used

Directory = null
PathWatcher = require './main'

# Public: Represents an individual file that can be watched, read from, and
# written to.
#
# ## Events
#
# ### contents-changed
#
# Public: Fired when the contents of the file has changed.
#
# ### moved
#
# Public: Fired when the file has been renamed. {::getPath} will reflect the new path.
#
# ### removed
#
# Public: Fired when the file has been deleted.
#
module.exports =
class File
  EmitterMixin.includeInto(this)

  realPath: null
  subscriptionCount: 0

  # Public: Creates a new file.
  #
  # * `filePath` A {String} containing the absolute path to the file
  # * `symlink` A {Boolean} indicating if the path is a symlink (default: false).
  constructor: (filePath, @symlink=false) ->
    throw new Error("#{filePath} is a directory") if fs.isDirectorySync(filePath)

    filePath = path.normalize(filePath) if filePath
    @path = filePath
    @emitter = new Emitter

    @cachedContents = null

  on: (eventName) ->
    switch eventName
      when 'content-changed'
        Grim.deprecate("Use File::onDidChange instead")
      when 'moved'
        Grim.deprecate("Use File::onDidRename instead")
      when 'removed'
        Grim.deprecate("Use File::onDidDelete instead")
      else
        Grim.deprecate("Use explictly-named event subscription methods instead")

    @willAddSubscription()
    @trackUnsubscription(EmitterMixin::on.apply(this, arguments))

  onDidChange: (callback) ->
    @willAddSubscription()
    @trackUnsubscription(@emitter.on('did-change', callback))

  onDidRename: (callback) ->
    @willAddSubscription()
    @trackUnsubscription(@emitter.on('did-rename', callback))

  onDidDelete: (callback) ->
    @willAddSubscription()
    @trackUnsubscription(@emitter.on('did-delete', callback))

  willAddSubscription: ->
    @subscribeToNativeChangeEvents() if @exists() and @subscriptionCount is 0
    @subscriptionCount++

  didRemoveSubscription: ->
    @unsubscribeFromNativeChangeEvents() if @subscriptionCount is 0
    @subscriptionCount--

  trackUnsubscription: (subscription) ->
    new Disposable =>
      subscription.dispose()
      @didRemoveSubscription()

  # Public: Returns a {Boolean}, always true.
  isFile: -> true

  # Public: Returns a {Boolean}, always false.
  isDirectory: -> false

  # Sets the path for the file.
  setPath: (@path) ->
    @realPath = null

  # Public: Returns the {String} path for the file.
  getPath: -> @path

  # Public: Return the {Directory} that contains this file.
  getParent: ->
    Directory ?= require './directory'
    new Directory(path.dirname @path)

  # Public: Returns this file's completely resolved {String} path.
  getRealPathSync: ->
    unless @realPath?
      try
        @realPath = fs.realpathSync(@path)
      catch error
        @realPath = @path
    @realPath

  # Public: Return the {String} filename without any directory information.
  getBaseName: ->
    path.basename(@path)

  # Public: Overwrites the file with the given text.
  #
  # * `text` The {String} text to write to the underlying file.
  #
  # Return undefined.
  write: (text) ->
    previouslyExisted = @exists()
    @writeFileWithPrivilegeEscalationSync(@getPath(), text)
    @cachedContents = text
    @subscribeToNativeChangeEvents() if not previouslyExisted and @hasSubscriptions()
    undefined

  readSync: (flushCache) ->
    if not @exists()
      @cachedContents = null
    else if not @cachedContents? or flushCache
      @cachedContents = fs.readFileSync(@getPath(), 'utf8')

    @setDigest(@cachedContents)
    @cachedContents

  # Public: Reads the contents of the file.
  #
  # * `flushCache` A {Boolean} indicating whether to require a direct read or if
  #   a cached copy is acceptable.
  #
  # Returns a promise that resovles to a String.
  read: (flushCache) ->
    Q ?= require 'q'

    if not @exists()
      promise = Q(null)
    else if not @cachedContents? or flushCache
      deferred = Q.defer()
      promise = deferred.promise
      content = []
      bytesRead = 0
      readStream = fs.createReadStream @getPath(), encoding: 'utf8'
      readStream.on 'data', (chunk) ->
        content.push(chunk)
        bytesRead += chunk.length
        deferred.notify(bytesRead)

      readStream.on 'end', ->
        deferred.resolve(content.join(''))

      readStream.on 'error', (error) ->
        deferred.reject(error)
    else
      promise = Q(@cachedContents)

    promise.then (contents) =>
      @setDigest(contents)
      @cachedContents = contents

  # Public: Returns a {Boolean}, true if the file exists, false otherwise.
  exists: ->
    fs.existsSync(@getPath())

  setDigest: (contents) ->
    @digest = crypto.createHash('sha1').update(contents ? '').digest('hex')

  # Public: Get the SHA-1 digest of this file
  #
  # Returns a {String}.
  getDigest: ->
    @digest ? @setDigest(@readSync())

  # Writes the text to specified path.
  #
  # Privilege escalation would be asked when current user doesn't have
  # permission to the path.
  writeFileWithPrivilegeEscalationSync: (filePath, text) ->
    try
      fs.writeFileSync(filePath, text)
    catch error
      if error.code is 'EACCES' and process.platform is 'darwin'
        runas ?= require 'runas'
        # Use dd to read from stdin and write to filePath, same thing could be
        # done with tee but it would also copy the file to stdout.
        unless runas('/bin/dd', ["of=#{filePath}"], stdin: text, admin: true) is 0
          throw error
      else
        throw error

  handleNativeChangeEvent: (eventType, eventPath) ->
    switch eventType
      when 'delete'
        @unsubscribeFromNativeChangeEvents()
        @detectResurrectionAfterDelay()
      when 'rename'
        @setPath(eventPath)
        @emit 'moved'
        @emitter.emit 'did-rename'
      when 'change'
        oldContents = @cachedContents
        @read(true).done (newContents) =>
          unless oldContents is newContents
            @emit 'contents-changed'
            @emitter.emit 'did-change'

  detectResurrectionAfterDelay: ->
    _.delay (=> @detectResurrection()), 50

  detectResurrection: ->
    if @exists()
      @subscribeToNativeChangeEvents()
      @handleNativeChangeEvent('change', @getPath())
    else
      @cachedContents = null
      @emit 'removed'
      @emitter.emit 'did-delete'

  subscribeToNativeChangeEvents: ->
    @watchSubscription ?= PathWatcher.watch @path, (args...) =>
      @handleNativeChangeEvent(args...)

  unsubscribeFromNativeChangeEvents: ->
    if @watchSubscription?
      @watchSubscription.close()
      @watchSubscription = null
