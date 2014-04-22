path = require 'path'
fs = require 'fs-plus'
temp = require 'temp'
File = require '../lib/file'
PathWatcher = require '../lib/main'

describe 'File', ->
  [filePath, file] = []

  beforeEach ->
    filePath = path.join(__dirname, 'fixtures', 'file-test.txt') # Don't put in /tmp because /tmp symlinks to /private/tmp and screws up the rename test
    fs.removeSync(filePath)
    fs.writeFileSync(filePath, "this is old!")
    file = new File(filePath)

  afterEach ->
    file.off()
    fs.removeSync(filePath)
    PathWatcher.closeAllWatchers()

  describe 'identification', ->

    it 'is a file', ->
      expect(file.isFile()).toBe(true)

    it "isn't a directory", ->
      expect(file.isDirectory()).toBe(false)

  describe "when the file has not been read", ->
    describe "when the contents of the file change", ->
      it "triggers 'contents-changed' event handlers", ->
        file.on 'contents-changed', changeHandler = jasmine.createSpy('changeHandler')
        fs.writeFileSync(file.getPath(), "this is new!")

        waitsFor "change event", ->
          changeHandler.callCount > 0

  describe "when the file has already been read #darwin", ->
    beforeEach ->
      file.readSync()

    describe "when the contents of the file change", ->
      it "triggers 'contents-changed' event handlers", ->
        changeHandler = jasmine.createSpy('changeHandler')
        file.on 'contents-changed', changeHandler
        fs.writeFileSync(file.getPath(), "this is new!")

        waitsFor "change event", ->
          changeHandler.callCount > 0

        runs ->
          changeHandler.reset()
          fs.writeFileSync(file.getPath(), "this is newer!")

        waitsFor "second change event", ->
          changeHandler.callCount > 0

    describe "when the file is removed", ->
      it "triggers 'remove' event handlers", ->
        removeHandler = jasmine.createSpy('removeHandler')
        file.on 'removed', removeHandler
        fs.removeSync(file.getPath())

        waitsFor "remove event", ->
          removeHandler.callCount > 0

    describe "when a file is moved (via the filesystem)", ->
      newPath = null

      beforeEach ->
        newPath = path.join(path.dirname(filePath), "file-was-moved-test.txt")

      afterEach ->
        if fs.existsSync(newPath)
          fs.removeSync(newPath)
          removeHandler = jasmine.createSpy('removeHandler')
          file.on 'removed', removeHandler
          waitsFor "remove event", 30000, -> removeHandler.callCount > 0

      it "it updates its path", ->
        moveHandler = jasmine.createSpy('moveHandler')
        file.on 'moved', moveHandler

        fs.moveSync(filePath, newPath)

        waitsFor "move event", 30000, ->
          moveHandler.callCount > 0

        runs ->
          expect(file.getPath()).toBe newPath

      it "maintains 'contents-changed' events set on previous path", ->
        moveHandler = null
        moveHandler = jasmine.createSpy('moveHandler')
        file.on 'moved', moveHandler
        changeHandler = null
        changeHandler = jasmine.createSpy('changeHandler')
        file.on 'contents-changed', changeHandler

        fs.moveSync(filePath, newPath)

        waitsFor "move event", ->
          moveHandler.callCount > 0

        runs ->
          expect(changeHandler).not.toHaveBeenCalled()
          fs.writeFileSync(file.getPath(), "this is new!")

        waitsFor "change event", ->
          changeHandler.callCount > 0

    describe "when a file is deleted and the recreated within a small amount of time (git sometimes does this)", ->
      it "triggers a contents change event if the contents change", ->
        changeHandler = jasmine.createSpy("file changed")
        removeHandler = jasmine.createSpy("file removed")
        file.on 'contents-changed', changeHandler
        file.on 'removed', removeHandler

        expect(changeHandler).not.toHaveBeenCalled()

        fs.removeSync(filePath)

        expect(changeHandler).not.toHaveBeenCalled()
        waits 20
        runs ->
          fs.writeFileSync(filePath, "HE HAS RISEN!")
          expect(changeHandler).not.toHaveBeenCalled()

        waitsFor "resurrection change event", ->
          changeHandler.callCount == 1

        runs ->
          expect(removeHandler).not.toHaveBeenCalled()
          fs.writeFileSync(filePath, "Hallelujah!")
          changeHandler.reset()

        waitsFor "post-resurrection change event", ->
          changeHandler.callCount > 0

  describe "getRealPathSync()", ->
    it "returns the resolved path to the file", ->
      tempDir = temp.mkdirSync('node-pathwatcher-directory')
      fs.writeFileSync(path.join(tempDir, 'file'), '')
      fs.writeFileSync(path.join(tempDir, 'file2'), '')

      tempFile = new File(path.join(tempDir, 'file'))
      expect(tempFile.getRealPathSync()).toBe fs.realpathSync(path.join(tempDir, 'file'))
      tempFile.setPath(path.join(tempDir, 'file2'))
      expect(tempFile.getRealPathSync()).toBe fs.realpathSync(path.join(tempDir, 'file2'))

      fs.symlinkSync(path.join(tempDir, 'file2'), path.join(tempDir, 'file3'))
      tempFile.setPath(path.join(tempDir, 'file3'))
      expect(tempFile.getRealPathSync()).toBe fs.realpathSync(path.join(tempDir, 'file2'))
