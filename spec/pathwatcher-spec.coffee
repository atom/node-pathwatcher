pathWatcher = require '../lib/main'
fs = require 'fs'

describe 'PathWatcher', ->
  beforeEach ->
    fs.writeFileSync('/tmp/watch.txt', '')

  afterEach ->
    pathWatcher.closeAllWatchers()

  describe '.getWatchedPaths()', ->
    it 'returns an array of all watched paths', ->
      expect(pathWatcher.getWatchedPaths()).toEqual []
      watcher1 = pathWatcher.watch '/tmp/watch.txt', ->
      expect(pathWatcher.getWatchedPaths()).toEqual ['/tmp/watch.txt']
      watcher2 = pathWatcher.watch '/tmp/watch.txt', ->
      expect(pathWatcher.getWatchedPaths()).toEqual ['/tmp/watch.txt']
      watcher1.close()
      expect(pathWatcher.getWatchedPaths()).toEqual ['/tmp/watch.txt']
      watcher2.close()
      expect(pathWatcher.getWatchedPaths()).toEqual []

  describe '.closeAllWatchers()', ->
    it 'closes all watched paths', ->
      expect(pathWatcher.getWatchedPaths()).toEqual []
      watcher = pathWatcher.watch '/tmp/watch.txt', ->
      expect(pathWatcher.getWatchedPaths()).toEqual ['/tmp/watch.txt']
      pathWatcher.closeAllWatchers()
      expect(pathWatcher.getWatchedPaths()).toEqual []

  describe 'when a watched path is changed', ->
    it 'fires the callback with the event type and empty path', ->
      eventType = null
      eventPath = null
      watcher = pathWatcher.watch '/tmp/watch.txt', (type, path) ->
        eventType = type
        eventPath = path

      fs.writeFileSync('/tmp/watch.txt', 'changed')
      waitsFor -> eventType?
      runs ->
        expect(eventType).toBe 'change'
        expect(eventPath).toBe ''

  describe 'when a watched path is renamed', ->
    it 'fires the callback with the event type and new path and watches the new path', ->
      eventType = null
      eventPath = null
      watcher = pathWatcher.watch '/tmp/watch.txt', (type, path) ->
        eventType = type
        eventPath = path

      fs.renameSync('/tmp/watch.txt', '/tmp/watch-renamed.txt')
      waitsFor -> eventType?
      runs ->
        expect(eventType).toBe 'rename'
        expect(eventPath).toBe fs.realpathSync('/tmp/watch-renamed.txt')
        expect(pathWatcher.getWatchedPaths()).toEqual [fs.realpathSync('/tmp/watch-renamed.txt')]

  describe 'when a watched path is deleted', ->
    it 'fires the callback with the event type and null path', ->
      eventType = null
      eventPath = null
      watcher = pathWatcher.watch '/tmp/watch.txt', (type, path) ->
        eventType = type
        eventPath = path

      fs.unlinkSync('/tmp/watch.txt')
      waitsFor -> eventType?
      runs ->
        expect(eventType).toBe 'delete'
        expect(eventPath).toBe null
