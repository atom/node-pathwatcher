pathWatcher = require '../lib/main'
fs = require 'fs'

describe "PathWatcher", ->
  afterEach ->
    pathWatcher.closeAllWatchers()

  describe ".getWatchedPaths()", ->
    it "returns an array of all watched paths", ->
      fs.writeFileSync('/tmp/watch.txt', '')

      expect(pathWatcher.getWatchedPaths()).toEqual []
      watcher1 = pathWatcher.watch '/tmp/watch.txt', ->
      expect(pathWatcher.getWatchedPaths()).toEqual ['/tmp/watch.txt']
      watcher2 = pathWatcher.watch '/tmp/watch.txt', ->
      expect(pathWatcher.getWatchedPaths()).toEqual ['/tmp/watch.txt']
      watcher1.close()
      expect(pathWatcher.getWatchedPaths()).toEqual ['/tmp/watch.txt']
      watcher2.close()
      expect(pathWatcher.getWatchedPaths()).toEqual []

  describe ".closeAllWatchers()", ->
    it "closes all watched paths", ->
      fs.writeFileSync('/tmp/watch.txt', '')

      expect(pathWatcher.getWatchedPaths()).toEqual []
      watcher = pathWatcher.watch '/tmp/watch.txt', ->
      expect(pathWatcher.getWatchedPaths()).toEqual ['/tmp/watch.txt']
      pathWatcher.closeAllWatchers()
      expect(pathWatcher.getWatchedPaths()).toEqual []
