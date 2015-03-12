crypto = require 'crypto'
path = require 'path'

_ = require 'underscore-plus'
EmitterMixin = require('emissary').Emitter
{Emitter, Disposable} = require 'event-kit'
fs = require 'fs-plus'
Grim = require 'grim'

Q = require 'q'
runas = null # Defer until used
iconv = null # Defer until used

Directory = null
PathWatcher = require './main'

# Extended: Represents an individual file that can be watched, read from, and
# written to.
module.exports =
class File
  EmitterMixin.includeInto(this)

  encoding: 'utf8'
  realPath: null
  subscriptionCount: 0

  ###
  Section: Construction
  ###

  # Public: Creates a new file.
  #
  # * `filePath` A {String} containing the absolute path to the file
  # * `symlink` A {Boolean} indicating if the path is a symlink (default: false).
  constructor: (filePath, @symlink=false) ->
    filePath = path.normalize(filePath) if filePath
    @path = filePath
    @emitter = new Emitter

    @on 'contents-changed-subscription-will-be-added', @willAddSubscription
    @on 'moved-subscription-will-be-added', @willAddSubscription
    @on 'removed-subscription-will-be-added', @willAddSubscription
    @on 'contents-changed-subscription-removed', @didRemoveSubscription
    @on 'moved-subscription-removed', @didRemoveSubscription
    @on 'removed-subscription-removed', @didRemoveSubscription

    @cachedContents = null

  on: (eventName) ->
    switch eventName
      when 'contents-changed'
        Grim.deprecate("Use File::onDidChange instead")
      when 'moved'
        Grim.deprecate("Use File::onDidRename instead")
      when 'removed'
        Grim.deprecate("Use File::onDidDelete instead")

    EmitterMixin::on.apply(this, arguments)

  ###
  Section: Event Subscription
  ###

  # Public: Invoke the given callback when the file's contents change.
  #
  # * `callback` {Function} to be called when the file's contents change.
  #
  # Returns a {Disposable} on which `.dispose()` can be called to unsubscribe.
  onDidChange: (callback) ->
    @willAddSubscription()
    @trackUnsubscription(@emitter.on('did-change', callback))

  # Public: Invoke the given callback when the file's path changes.
  #
  # * `callback` {Function} to be called when the file's path changes.
  #
  # Returns a {Disposable} on which `.dispose()` can be called to unsubscribe.
  onDidRename: (callback) ->
    @willAddSubscription()
    @trackUnsubscription(@emitter.on('did-rename', callback))

  # Public: Invoke the given callback when the file is deleted.
  #
  # * `callback` {Function} to be called when the file is deleted.
  #
  # Returns a {Disposable} on which `.dispose()` can be called to unsubscribe.
  onDidDelete: (callback) ->
    @willAddSubscription()
    @trackUnsubscription(@emitter.on('did-delete', callback))

  # Public: Invoke the given callback when there is an error with the watch.
  # When your callback has been invoked, the file will have unsubscribed from
  # the file watches.
  #
  # * `callback` {Function} callback
  #   * `errorObject` {Object}
  #     * `error` {Object} the error object
  #     * `handle` {Function} call this to indicate you have handled the error.
  #       The error will not be thrown if this function is called.
  onWillThrowWatchError: (callback) ->
    @emitter.on('will-throw-watch-error', callback)

  willAddSubscription: =>
    @subscriptionCount++
    try
      @subscribeToNativeChangeEvents()

  didRemoveSubscription: =>
    @subscriptionCount--
    @unsubscribeFromNativeChangeEvents() if @subscriptionCount is 0

  trackUnsubscription: (subscription) ->
    new Disposable =>
      subscription.dispose()
      @didRemoveSubscription()

  ###
  Section: File Metadata
  ###

  # Public: Returns a {Boolean}, always true.
  isFile: -> true

  # Public: Returns a {Boolean}, always false.
  isDirectory: -> false

  # Returns a promise that resolves to a {Boolean}, true if the file exists, false otherwise.
  exists: ->
    Q.Promise (resolve, reject) =>
      fs.exists @getPath(), resolve

  # Public: Returns a {Boolean}, true if the file exists, false otherwise.
  existsSync: ->
    fs.existsSync(@getPath())

  # Public: Get the SHA-1 digest of this file
  #
  # Returns a promise that resolves to a {String}.
  getDigest: ->
    return Q(@digest) if @digest
    @read().then (contents) =>
      # read sets digest
      @digest

  # Public: Get the SHA-1 digest of this file
  #
  # Returns a {String}.
  getDigestSync: ->
    @readSync()
    # read sets digest
    @digest

  setDigest: (contents) ->
    @digest = crypto.createHash('sha1').update(contents ? '').digest('hex')

  # Public: Sets the file's character set encoding name.
  #
  # * `encoding` The {String} encoding to use (default: 'utf8')
  setEncoding: (@encoding='utf8') ->

  # Public: Returns the {String} encoding name for this file (default: 'utf8').
  getEncoding: -> @encoding

  ###
  Section: Managing Paths
  ###

  # Public: Returns the {String} path for the file.
  getPath: -> @path

  # Sets the path for the file.
  setPath: (@path) ->
    @realPath = null

  # Public: Returns this file's completely resolved {String} path.
  getRealPathSync: ->
    Grim.deprecate("Use File::getRealPath instead")
    unless @realPath?
      try
        @realPath = fs.realpathSync(@path)
      catch error
        @realPath = @path
    @realPath

  # Public: Returns a promise that resolves to the file's completely resolved {String} path.
  getRealPath: ->
    if @realPath?
      Q(@realPath)
    else
      Q.nfcall(fs.realpath, @path).then (realPath) =>
        @realPath = realPath

  # Public: Return the {String} filename without any directory information.
  getBaseName: ->
    path.basename(@path)

  ###
  Section: Traversing
  ###

  # Public: Return the {Directory} that contains this file.
  getParent: ->
    Directory ?= require './directory'
    new Directory(path.dirname @path)

  ###
  Section: Reading and Writing
  ###

  readSync: (flushCache) ->
    Grim.deprecate("Use File::read instead")
    if not @existsSync()
      @cachedContents = null
    else if not @cachedContents? or flushCache
      encoding = @getEncoding()
      if encoding is 'utf8'
        @cachedContents = fs.readFileSync(@getPath(), encoding)
      else
        iconv ?= require 'iconv-lite'
        @cachedContents = iconv.decode(fs.readFileSync(@getPath()), encoding)

    @setDigest(@cachedContents)
    @cachedContents

  writeFileSync: (filePath, contents) ->
    Grim.deprecate("Use File::write instead")
    encoding = @getEncoding()
    if encoding is 'utf8'
      fs.writeFileSync(filePath, contents, {encoding})
    else
      iconv ?= require 'iconv-lite'
      fs.writeFileSync(filePath, iconv.encode(contents, encoding))

  # Public: Reads the contents of the file.
  #
  # * `flushCache` A {Boolean} indicating whether to require a direct read or if
  #   a cached copy is acceptable.
  #
  # Returns a promise that resovles to a String.
  read: (flushCache) ->
    if @cachedContents? and not flushCache
      promise = Q(@cachedContents)
    else
      deferred = Q.defer()
      promise = deferred.promise
      content = []
      bytesRead = 0
      encoding = @getEncoding()
      if encoding is 'utf8'
        readStream = fs.createReadStream(@getPath(), {encoding})
      else
        iconv ?= require 'iconv-lite'
        readStream = fs.createReadStream(@getPath()).pipe(iconv.decodeStream(encoding))

      readStream.on 'data', (chunk) ->
        content.push(chunk)
        bytesRead += chunk.length
        deferred.notify(bytesRead)

      readStream.on 'end', ->
        deferred.resolve(content.join(''))

      readStream.on 'error', (error) ->
        if error.code == 'ENOENT'
          deferred.resolve(null)
        else
          deferred.reject(error)

    promise.then (contents) =>
      @setDigest(contents)
      @cachedContents = contents

  # Public: Overwrites the file with the given text.
  #
  # * `text` The {String} text to write to the underlying file.
  #
  # Returns a {Promise} that resolves when the file has been written.
  write: (text) ->
    @exists().then (previouslyExisted) =>
      @writeFile(@getPath(), text).then =>
        @cachedContents = text
        @subscribeToNativeChangeEvents() if not previouslyExisted and @hasSubscriptions()
        undefined

  # Public: Overwrites the file with the given text.
  #
  # * `text` The {String} text to write to the underlying file.
  #
  # Return undefined.
  writeSync: (text) ->
    previouslyExisted = @exists()
    @writeFileWithPrivilegeEscalationSync(@getPath(), text)
    @cachedContents = text
    @subscribeToNativeChangeEvents() if not previouslyExisted and @hasSubscriptions()
    undefined

  writeFile: (filePath, contents) ->
    encoding = @getEncoding()
    if encoding is 'utf8'
      Q.nfcall(fs.writeFile, filePath, contents, {encoding})
    else
      iconv ?= require 'iconv-lite'
      Q.nfcall(fs.writeFile, filePath, iconv.encode(contents, encoding))

  # Writes the text to specified path.
  #
  # Privilege escalation would be asked when current user doesn't have
  # permission to the path.
  writeFileWithPrivilegeEscalationSync: (filePath, text) ->
    try
      @writeFileSync(filePath, text)
    catch error
      if error.code is 'EACCES' and process.platform is 'darwin'
        runas ?= require 'runas'
        # Use dd to read from stdin and write to filePath, same thing could be
        # done with tee but it would also copy the file to stdout.
        unless runas('/bin/dd', ["of=#{filePath}"], stdin: text, admin: true) is 0
          throw error
      else
        throw error

  ###
  Section: Private
  ###

  handleNativeChangeEvent: (eventType, eventPath) ->
    switch eventType
      when 'delete'
        @unsubscribeFromNativeChangeEvents()
        @detectResurrectionAfterDelay()
      when 'rename'
        @setPath(eventPath)
        @emit 'moved'
        @emitter.emit 'did-rename'
      when 'change', 'resurrect'
        oldContents = @cachedContents
        handleReadError = (error) =>
          # We cant read the file, so we GTFO on the watch
          @unsubscribeFromNativeChangeEvents()

          handled = false
          handle = -> handled = true
          error.eventType = eventType
          @emitter.emit('will-throw-watch-error', {error, handle})
          unless handled
            newError = new Error("Cannot read file after file `#{eventType}` event: #{@path}")
            newError.originalError = error
            newError.code = "ENOENT"
            newError.path
            # I want to throw the error here, but it stops the event loop or
            # something. No longer do interval or timeout methods get run!
            # throw newError
            console.error newError

        try
          @read(true).catch(handleReadError).done (newContents) =>
            unless oldContents is newContents
              @emit 'contents-changed'
              @emitter.emit 'did-change'
        catch error
          handleReadError(error)

  detectResurrectionAfterDelay: ->
    _.delay (=> @detectResurrection()), 50

  detectResurrection: ->
    @exists().then (exists) =>
      if exists
        @subscribeToNativeChangeEvents()
        @handleNativeChangeEvent('resurrect', @getPath())
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
