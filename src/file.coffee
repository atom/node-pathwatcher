crypto = require 'crypto'
path = require 'path'

_ = require 'underscore-plus'
{Emitter} = require 'emissary'
fs = require 'fs-plus'
Q = require 'q'
runas = require 'runas'

Directory = null
PathWatcher = require './main'

# Public: Represents an individual file that can be watched, read from, and
# written to.
#
# ## Events
#
# ### contents-changed
#
# Fired when the contents of the file has changed.
#
# ### moved
#
# Fired when the file has been renamed. {::getPath} will reflect the new path.
#
# ### removed
#
# Fired when the file has been deleted.
#
module.exports =
class File
  Emitter.includeInto(this)

  realPath: null

  # Public: Creates a new file.
  #
  # `filePath` A {String} containing the absolute path to the file
  # `symlink` A {Boolean} indicating if the path is a symlink (default: false).
  constructor: (filePath, @symlink=false) ->
    throw new Error("#{filePath} is a directory") if fs.isDirectorySync(filePath)

    filePath = path.normalize(filePath) if filePath
    @path = filePath

    @cachedContents = null
    @handleEventSubscriptions()

  # Subscribes to file system notifications when necessary.
  handleEventSubscriptions: ->
    eventNames = ['contents-changed', 'moved', 'removed']

    subscriptionsAdded = eventNames.map (eventName) -> "first-#{eventName}-subscription-will-be-added"
    @on subscriptionsAdded.join(' '), =>
      # Only subscribe when a listener of eventName attaches (triggered by emissary)
      @subscribeToNativeChangeEvents() if @exists()

    subscriptionsRemoved = eventNames.map (eventName) -> "last-#{eventName}-subscription-removed"
    @on subscriptionsRemoved.join(' '), =>
      # Detach when the last listener of eventName detaches (triggered by emissary)
      subscriptionsEmpty = _.every eventNames, (eventName) => @getSubscriptionCount(eventName) is 0
      @unsubscribeFromNativeChangeEvents() if subscriptionsEmpty

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
  # `text` - The {String} text to write to the underlying file.
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
  # `flushCache` A {Boolean} indicating whether to require a direct read or if
  #              a cached copy is acceptable.
  #
  # Returns a promise that resovles to a String.
  read: (flushCache) ->
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
      when 'change'
        oldContents = @cachedContents
        @read(true).done (newContents) =>
          @emit 'contents-changed' unless oldContents is newContents

  detectResurrectionAfterDelay: ->
    _.delay (=> @detectResurrection()), 50

  detectResurrection: ->
    if @exists()
      @subscribeToNativeChangeEvents()
      @handleNativeChangeEvent('change', @getPath())
    else
      @cachedContents = null
      @emit 'removed'

  subscribeToNativeChangeEvents: ->
    @watchSubscription ?= PathWatcher.watch @path, (args...) =>
      @handleNativeChangeEvent(args...)

  unsubscribeFromNativeChangeEvents: ->
    if @watchSubscription?
      @watchSubscription.close()
      @watchSubscription = null
