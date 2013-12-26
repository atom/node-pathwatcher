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
      expect(pathWatcher.getWatchedPaths()).toEqual [watcher1.handleWatcher.path]
      watcher2 = pathWatcher.watch tempFile, ->
      expect(pathWatcher.getWatchedPaths()).toEqual [watcher1.handleWatcher.path]
      watcher1.close()
      expect(pathWatcher.getWatchedPaths()).toEqual [watcher1.handleWatcher.path]
      watcher2.close()
      expect(pathWatcher.getWatchedPaths()).toEqual []

  describe '.closeAllWatchers()', ->
    it 'closes all watched paths', ->
      expect(pathWatcher.getWatchedPaths()).toEqual []
      watcher = pathWatcher.watch tempFile, ->
      expect(pathWatcher.getWatchedPaths()).toEqual [watcher.handleWatcher.path]
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
      if process.platform is 'linux'
        return

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
        expect(pathWatcher.getWatchedPaths()).toEqual [watcher.handleWatcher.path]

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

  describe 'when en exception is thrown in the closed watcher\'s callback', ->
    it 'does not crash', (done) ->
      watcher = pathWatcher.watch tempFile, (type, path) ->
        watcher.close()
        try
          throw new Error('test')
        catch e
          done()
      fs.writeFileSync(tempFile, 'changed')

  describe 'when watching multiple files under the same directory', ->
    it 'fires the callbacks when both of the files are modifiled', ->
      called = 0
      tempFile2 = path.join(tempDir, 'file2')
      fs.writeFileSync(tempFile2, '')
      pathWatcher.watch tempFile, (type, path) ->
        called |= 1
      pathWatcher.watch tempFile2, (type, path) ->
        called |= 2
      fs.writeFileSync(tempFile, 'changed')
      fs.writeFileSync(tempFile2, 'changed')
      waitsFor -> called == 3

    it 'shares the same handle watcher between the two files on Windows', ->
      if process.platform is 'win32'
        tempFile2 = path.join(tempDir, 'file2')
        fs.writeFileSync(tempFile2, '')
        watcher1 = pathWatcher.watch tempFile, (type, path) ->
        watcher2 = pathWatcher.watch tempFile2, (type, path) ->
        expect(watcher1.handleWatcher).toBe(watcher2.handleWatcher)

  describe 'when a file is unwatched', ->
    it 'it does not lock the filesystem tree', ->
      nested1 = path.join(tempDir, 'nested1')
      nested2 = path.join(nested1, 'nested2')
      nested3 = path.join(nested2, 'nested3')
      fs.mkdirSync(nested1)
      fs.mkdirSync(nested2)
      fs.writeFileSync(nested3)

      subscription1 = pathWatcher.watch nested1, ->
      subscription2 = pathWatcher.watch nested2, ->
      subscription3 = pathWatcher.watch nested3, ->

      subscription1.close()
      subscription2.close()
      subscription3.close()

      fs.unlinkSync(nested3)
      fs.rmdirSync(nested2)
      fs.rmdirSync(nested1)
