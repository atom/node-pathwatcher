pathWatcher = require '../lib/main'
fs = require 'fs'

describe "PathWatcher", ->
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
