pathWatcher = require '../lib/main'
fs = require 'fs'
path = require 'path'
temp = require 'temp'

temp.track()

describe 'PathWatcher', ->
  tempFile = temp.openSync('node-pathwatcher-file')
  tempDir = temp.mkdirSync('node-pathwatcher-directory')

  beforeEach ->
    fs.writeFileSync(tempFile.path, '')

  afterEach ->
    pathWatcher.closeAllWatchers()

  describe '.getWatchedPaths()', ->
    it 'returns an array of all watched paths', ->
      expect(pathWatcher.getWatchedPaths()).toEqual []
      watcher1 = pathWatcher.watch tempFile.path, ->
      expect(pathWatcher.getWatchedPaths()).toEqual [tempFile.path]
      watcher2 = pathWatcher.watch tempFile.path, ->
      expect(pathWatcher.getWatchedPaths()).toEqual [tempFile.path]
      watcher1.close()
      expect(pathWatcher.getWatchedPaths()).toEqual [tempFile.path]
      watcher2.close()
      expect(pathWatcher.getWatchedPaths()).toEqual []

  describe '.closeAllWatchers()', ->
    it 'closes all watched paths', ->
      expect(pathWatcher.getWatchedPaths()).toEqual []
      watcher = pathWatcher.watch tempFile.path, ->
      expect(pathWatcher.getWatchedPaths()).toEqual [tempFile.path]
      pathWatcher.closeAllWatchers()
      expect(pathWatcher.getWatchedPaths()).toEqual []

  describe 'when a watched path is changed', ->
    it 'fires the callback with the event type and empty path', ->
      eventType = null
      eventPath = null
      watcher = pathWatcher.watch tempFile.path, (type, path) ->
        eventType = type
        eventPath = path

      fs.writeFileSync(tempFile.path, 'changed')
      waitsFor -> eventType?
      runs ->
        expect(eventType).toBe 'change'
        expect(eventPath).toBe ''

  describe 'when a watched path is renamed', ->
    it 'fires the callback with the event type and new path and watches the new path', ->
      eventType = null
      eventPath = null
      watcher = pathWatcher.watch tempFile.path, (type, path) ->
        eventType = type
        eventPath = path

      tempRenamed = temp.path('node-pathwatcher-renamed')
      fs.renameSync(tempFile.path, tempRenamed)
      waitsFor -> eventType?
      runs ->
        expect(eventType).toBe 'rename'
        expect(eventPath).toBe fs.realpathSync(tempRenamed)
        expect(pathWatcher.getWatchedPaths()).toEqual [fs.realpathSync(tempRenamed)]

  describe 'when a watched path is deleted', ->
    it 'fires the callback with the event type and null path', ->
      eventType = null
      eventPath = null
      watcher = pathWatcher.watch tempFile.path, (type, path) ->
        eventType = type
        eventPath = path

      fs.unlinkSync(tempFile.path)
      waitsFor -> eventType?
      runs ->
        expect(eventType).toBe 'delete'
        expect(eventPath).toBe null

  fdescribe 'when a file under watched directory is deleted', ->
    it 'fires the callback with the change event and empty path', (done) ->
      fileUnderDir = path.join(tempDir, 'file')
      fs.writeFileSync(fileUnderDir, '')
      watcher = pathWatcher.watch tempDir, (type, path) ->
        expect(type).toBe 'change'
        expect(path).toBe ''
        watcher.close()
        done()
      fs.unlinkSync(fileUnderDir)

  fdescribe 'when a new file is created under watched directory', ->
    it 'fires the callback with the change event and empty path', ->
      newFile = path.join(tempDir, 'file')
      watcher = pathWatcher.watch tempDir, (type, path) ->
        expect(type).toBe 'change'
        expect(path).toBe ''
        watcher.close()
        done()
      fs.writeFileSync(newFile, '')
