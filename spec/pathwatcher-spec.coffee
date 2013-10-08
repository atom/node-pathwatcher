pathWatcher = require '../lib/main'
fs = require 'fs'
path = require 'path'
temp = require 'temp'

temp.track()

describe 'PathWatcher', ->
  tempDir = temp.mkdirSync('node-pathwatcher-directory')
  tempFile = path.join(tempDir, 'file')

  beforeEach ->
    fs.writeFileSync(tempFile, '')

  afterEach ->
    pathWatcher.closeAllWatchers()

  describe '.getWatchedPaths()', ->
    it 'returns an array of all watched paths', ->
      expect(pathWatcher.getWatchedPaths()).toEqual []
      watcher1 = pathWatcher.watch tempFile, ->
      expect(pathWatcher.getWatchedPaths()).toEqual [tempFile]
      watcher2 = pathWatcher.watch tempFile, ->
      expect(pathWatcher.getWatchedPaths()).toEqual [tempFile]
      watcher1.close()
      expect(pathWatcher.getWatchedPaths()).toEqual [tempFile]
      watcher2.close()
      expect(pathWatcher.getWatchedPaths()).toEqual []

  describe '.closeAllWatchers()', ->
    it 'closes all watched paths', ->
      expect(pathWatcher.getWatchedPaths()).toEqual []
      watcher = pathWatcher.watch tempFile, ->
      expect(pathWatcher.getWatchedPaths()).toEqual [tempFile]
      pathWatcher.closeAllWatchers()
      expect(pathWatcher.getWatchedPaths()).toEqual []

  describe 'when a watched path is changed', ->
    it 'fires the callback with the event type and empty path', ->
      eventType = null
      eventPath = null
      watcher = pathWatcher.watch tempFile, (type, path) ->
        eventType = type
        eventPath = path

      fs.writeFileSync(tempFile, 'changed')
      waitsFor -> eventType?
      runs ->
        expect(eventType).toBe 'change'
        expect(eventPath).toBe ''

  describe 'when a watched path is renamed', ->
    it 'fires the callback with the event type and new path and watches the new path', ->
      eventType = null
      eventPath = null
      watcher = pathWatcher.watch tempFile, (type, path) ->
        eventType = type
        eventPath = path

      tempRenamed = path.join(tempDir, 'renamed')
      fs.renameSync(tempFile, tempRenamed)
      waitsFor -> eventType?
      runs ->
        expect(eventType).toBe 'rename'
        expect(eventPath).toBe fs.realpathSync(tempRenamed)
        expect(pathWatcher.getWatchedPaths()).toEqual [fs.realpathSync(tempRenamed)]

  describe 'when a watched path is deleted', ->
    it 'fires the callback with the event type and null path', ->
      eventType = null
      eventPath = null
      watcher = pathWatcher.watch tempFile, (type, path) ->
        eventType = type
        eventPath = path

      fs.unlinkSync(tempFile)
      waitsFor -> eventType?
      runs ->
        expect(eventType).toBe 'delete'
        expect(eventPath).toBe null

  describe 'when a file under watched directory is deleted', ->
    it 'fires the callback with the change event and empty path', (done) ->
      fileUnderDir = path.join(tempDir, 'file')
      fs.writeFileSync(fileUnderDir, '')
      watcher = pathWatcher.watch tempDir, (type, path) ->
        expect(type).toBe 'change'
        expect(path).toBe ''
        done()
      fs.unlinkSync(fileUnderDir)

  describe 'when a new file is created under watched directory', ->
    it 'fires the callback with the change event and empty path', ->
      newFile = path.join(tempDir, 'file')
      watcher = pathWatcher.watch tempDir, (type, path) ->
        fs.unlinkSync(newFile)

        expect(type).toBe 'change'
        expect(path).toBe ''
        done()
      fs.writeFileSync(newFile, '')

  describe 'when a file under watched directory is moved', ->
    it 'fires the callback with the change event and empty path', (done) ->
      newName = path.join(tempDir, 'file2')
      watcher = pathWatcher.watch tempDir, (type, path) ->
        expect(type).toBe 'change'
        expect(path).toBe ''
        done()
      fs.renameSync(tempFile, newName)
