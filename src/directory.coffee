path = require 'path'

async = require 'async'
{Emitter} = require 'emissary'
fs = require 'fs-plus'

File = require './file'
PathWatcher = require './main'

# Public: Represents a directory on disk that can be watched for changes.
module.exports =
class Directory
  Emitter.includeInto(this)

  realPath: null

  # Public: Configures a new Directory instance, no files are accessed.
  #
  # path - A {String} containing the absolute path to the directory.
  # symlink - A {Boolean} indicating if the path is a symlink (default: false).
  constructor: (@path, @symlink=false) ->
    @on 'first-contents-changed-subscription-will-be-added', =>
      # Triggered by emissary, when a new contents-changed listener attaches
      @subscribeToNativeChangeEvents()

    @on 'last-contents-changed-subscription-removed', =>
      # Triggered by emissary, when the last contents-changed listener detaches
      @unsubscribeFromNativeChangeEvents()

    @lowerCasePath = @path.toLowerCase() if fs.isCaseInsensitive()

  # Public: Returns the {String} basename of the directory.
  getBaseName: ->
    path.basename(@path)

  # Public: Returns the directory's symbolic path.
  #
  # This may include unfollowed symlinks or relative directory entries. Or it
  # may be fully resolved, it depends on what you give it.
  getPath: -> @path

  # Public: Returns this directory's completely resolved path.
  #
  # All relative directory entries are removed and symlinks are resolved to
  # their final destination.
  getRealPathSync: ->
    unless @realPath?
      try
        @realPath = fs.realpathSync(@path)
        @lowerCaseRealPath = @realPath.toLowerCase() if fs.isCaseInsensitive()
      catch e
        @realPath = @path
        @lowerCaseRealPath = @lowerCasePath if fs.isCaseInsensitive()
    @realPath

  # Public: Returns whether the given path (real or symbolic) is inside this
  # directory. This method does not actually check if the path exists, it just
  # checks if the path is under this directory.
  contains: (pathToCheck) ->
    return false unless pathToCheck

    # Normalize forward slashes to back slashes on windows
    fullPath = fullPath.replace(/\//g, '\\') if process.platform is 'win32'

    if fs.isCaseInsensitive()
      directoryPath = @lowerCasePath
      pathToCheck = pathToCheck.toLowerCase()
    else
      directoryPath = @path

    return true if @isPathPrefixOf(directoryPath, pathToCheck)

    # Check real path
    @getRealPathSync()
    if fs.isCaseInsensitive()
      directoryPath = @lowerCaseRealPath
    else
      directoryPath = @realPath

    @isPathPrefixOf(directoryPath, pathToCheck)

  # Public: Returns the relative path to the given path from this directory.
  relativize: (fullPath) ->
    return fullPath unless fullPath

    # Normalize forward slashes to back slashes on windows
    fullPath = fullPath.replace(/\//g, '\\') if process.platform is 'win32'

    if fs.isCaseInsensitive()
      pathToCheck = fullPath.toLowerCase()
      directoryPath = @lowerCasePath
    else
      pathToCheck = fullPath
      directoryPath = @path

    if pathToCheck is directoryPath
      return ''
    else if @isPathPrefixOf(directoryPath, pathToCheck)
      return fullPath.substring(directoryPath.length + 1)

    # Check real path
    @getRealPathSync()
    if fs.isCaseInsensitive()
      directoryPath = @lowerCaseRealPath
    else
      directoryPath = @realPath

    if pathToCheck is directoryPath
      ''
    else if @isPathPrefixOf(directoryPath, pathToCheck)
      fullPath.substring(directoryPath.length + 1)
    else
      fullPath

  # Public: Reads file entries in this directory from disk synchronously.
  #
  # Returns an {Array} of {File} and {Directory} objects.
  getEntriesSync: ->
    directories = []
    files = []
    for entryPath in fs.listSync(@path)
      try
        stat = fs.lstatSync(entryPath)
        symlink = stat.isSymbolicLink()
        stat = fs.statSync(entryPath) if symlink

      if stat?.isDirectory()
        directories.push(new Directory(entryPath, symlink))
      else if stat?.isFile()
        files.push(new File(entryPath, symlink))

    directories.concat(files)

  # Public: Reads file entries in this directory from disk asynchronously.
  #
  # callback - A {Function} to call with an {Error} as the 1st argument and
  #            an {Array} of {File} and {Directory} objects as the 2nd argument.
  getEntries: (callback) ->
    fs.list @path, (error, entries) ->
      return callback(error) if error?

      directories = []
      files = []
      addEntry = (entryPath, stat, symlink, callback) ->
        if stat?.isDirectory()
          directories.push(new Directory(entryPath, symlink))
        else if stat?.isFile()
          files.push(new File(entryPath, symlink))
        callback()

      statEntry = (entryPath, callback) ->
        fs.lstat entryPath, (error, stat) ->
          if stat?.isSymbolicLink()
            fs.stat entryPath, (error, stat) ->
              addEntry(entryPath, stat, true, callback)
          else
            addEntry(entryPath, stat, false, callback)

      async.eachLimit entries, 1, statEntry, ->
        callback(null, directories.concat(files))

  subscribeToNativeChangeEvents: ->
    @watchSubscription ?= PathWatcher.watch @path, (eventType) =>
      @emit "contents-changed" if eventType is "change"

  unsubscribeFromNativeChangeEvents: ->
    if @watchSubscription?
      @watchSubscription.close()
      @watchSubscription = null

  # Does given full path start with the given prefix?
  isPathPrefixOf: (prefix, fullPath) ->
    fullPath.indexOf(prefix) is 0 and fullPath[prefix.length] is path.sep
