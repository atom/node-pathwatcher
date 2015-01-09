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
    file.unsubscribeFromNativeChangeEvents()
    fs.removeSync(filePath)
    PathWatcher.closeAllWatchers()

  it "normalizes the specified path", ->
    expect(new File(__dirname + path.sep + 'fixtures' + path.sep + 'abc' + path.sep + '..' + path.sep + 'file-test.txt').getBaseName()).toBe 'file-test.txt'
    expect(new File(__dirname + path.sep + 'fixtures' + path.sep + 'abc' + path.sep + '..' + path.sep + 'file-test.txt').path.toLowerCase()).toBe file.path.toLowerCase()

  it 'returns true from isFile()', ->
    expect(file.isFile()).toBe true

  it 'returns false from isDirectory()', ->
    expect(file.isDirectory()).toBe false

  describe "when the file has not been read", ->
    describe "when the contents of the file change", ->
      it "notifies ::onDidChange observers", ->
        file.onDidChange changeHandler = jasmine.createSpy('changeHandler')
        fs.writeFileSync(file.getPath(), "this is new!")

        waitsFor "change event", ->
          changeHandler.callCount > 0

    describe "when the contents of the file are deleted", ->
      it "notifies ::onDidChange observers", ->
        file.onDidChange changeHandler = jasmine.createSpy('changeHandler')
        fs.writeFileSync(file.getPath(), "")

        waitsFor "change event", ->
          changeHandler.callCount > 0

  describe "when the file has already been read #darwin", ->
    beforeEach ->
      file.readSync()

    describe "when the contents of the file change", ->
      it "notifies ::onDidChange observers", ->
        changeHandler = jasmine.createSpy('changeHandler')
        file.onDidChange changeHandler
        fs.writeFileSync(file.getPath(), "this is new!")

        waitsFor "change event", ->
          changeHandler.callCount > 0

        runs ->
          changeHandler.reset()
          fs.writeFileSync(file.getPath(), "this is newer!")

        waitsFor "second change event", ->
          changeHandler.callCount > 0

    describe "when the file is deleted", ->
      it "notifies ::onDidDelete observers", ->
        deleteHandler = jasmine.createSpy('deleteHandler')
        file.onDidDelete(deleteHandler)
        fs.removeSync(file.getPath())

        waitsFor "remove event", ->
          deleteHandler.callCount > 0

    describe "when a file is moved (via the filesystem)", ->
      newPath = null

      beforeEach ->
        newPath = path.join(path.dirname(filePath), "file-was-moved-test.txt")

      afterEach ->
        if fs.existsSync(newPath)
          fs.removeSync(newPath)
          deleteHandler = jasmine.createSpy('deleteHandler')
          file.onDidDelete(deleteHandler)
          waitsFor "remove event", 30000, -> deleteHandler.callCount > 0

      it "it updates its path", ->
        moveHandler = jasmine.createSpy('moveHandler')
        file.on 'moved', moveHandler

        fs.moveSync(filePath, newPath)

        waitsFor "move event", 30000, ->
          moveHandler.callCount > 0

        runs ->
          expect(file.getPath()).toBe newPath

      it "maintains ::onDidChange observers that were subscribed on the previous path", ->
        moveHandler = null
        moveHandler = jasmine.createSpy('moveHandler')
        file.on 'moved', moveHandler
        changeHandler = null
        changeHandler = jasmine.createSpy('changeHandler')
        file.onDidChange changeHandler

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
        deleteHandler = jasmine.createSpy("file deleted")
        file.onDidChange changeHandler
        file.onDidDelete deleteHandler

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
          expect(deleteHandler).not.toHaveBeenCalled()
          fs.writeFileSync(filePath, "Hallelujah!")
          changeHandler.reset()

        waitsFor "post-resurrection change event", ->
          changeHandler.callCount > 0

    describe "when a file cannot be opened after the watch has been applied", ->
      errorSpy = null
      beforeEach ->
        errorSpy = jasmine.createSpy()
        errorSpy.andCallFake ({error, handle})->
          handle()
        file.onWillThrowWatchError errorSpy

      describe "when the error happens in the promise callback chain", ->
        beforeEach ->
          spyOn(file, 'setDigest').andCallFake ->
            error = new Error('ENOENT open "FUUU"')
            error.code = 'ENOENT'
            throw error

        it "emits an event with the error when the error happens in the promise callback chain", ->
          changeHandler = jasmine.createSpy('changeHandler')
          file.onDidChange changeHandler
          fs.writeFileSync(file.getPath(), "this is new!!")

          waitsFor "change event", ->
            errorSpy.callCount > 0

          runs ->
            args = errorSpy.mostRecentCall.args[0]
            expect(args.error.code).toBe 'ENOENT'
            expect(args.handle).toBeTruthy()

      describe "when the error happens in the read method", ->
        beforeEach ->
          spyOn(file, 'read').andCallFake ->
            error = new Error('ENOENT open "FUUU"')
            error.code = 'ENOENT'
            throw error

        it "emits an event with the error when the error happens in the promise callback chain", ->
          changeHandler = jasmine.createSpy('changeHandler')
          file.onDidChange changeHandler
          fs.writeFileSync(file.getPath(), "this is new!!")

          waitsFor "change event", ->
            errorSpy.callCount > 0

          runs ->
            args = errorSpy.mostRecentCall.args[0]
            expect(args.error.code).toBe 'ENOENT'
            expect(args.handle).toBeTruthy()

  describe "getRealPathSync()", ->
    tempDir = null

    beforeEach ->
      tempDir = temp.mkdirSync('node-pathwatcher-directory')
      fs.writeFileSync(path.join(tempDir, 'file'), '')
      fs.writeFileSync(path.join(tempDir, 'file2'), '')

    it "returns the resolved path to the file", ->
      tempFile = new File(path.join(tempDir, 'file'))
      expect(tempFile.getRealPathSync()).toBe fs.realpathSync(path.join(tempDir, 'file'))
      tempFile.setPath(path.join(tempDir, 'file2'))
      expect(tempFile.getRealPathSync()).toBe fs.realpathSync(path.join(tempDir, 'file2'))

    describe "on #darwin and #linux", ->
      it "returns the target path for symlinks", ->
        fs.symlinkSync(path.join(tempDir, 'file2'), path.join(tempDir, 'file3'))
        tempFile = new File(path.join(tempDir, 'file3'))
        expect(tempFile.getRealPathSync()).toBe fs.realpathSync(path.join(tempDir, 'file2'))

  describe "getParent()", ->
    it "gets the parent Directory", ->
      d = file.getParent()
      expected = path.join __dirname, 'fixtures'
      expect(d.getRealPathSync()).toBe(expected)

  describe 'encoding', ->
    it "should be 'utf8' by default", ->
      expect(file.getEncoding()).toBe('utf8')

    it "should be settable", ->
      file.setEncoding('cp1252')
      expect(file.getEncoding()).toBe('cp1252')

  describe 'encoding support', ->
    [unicodeText, unicodeBytes] = []

    beforeEach ->
      unicodeText = 'ё'
      unicodeBytes = new Buffer('\x51\x04') # 'ё'

    it 'should read a file in UTF-16', ->
      fs.writeFileSync(file.getPath(), unicodeBytes)
      file.setEncoding('utf16le')

      readHandler = jasmine.createSpy('read handler')
      file.read().then(readHandler)

      waitsFor 'read handler', ->
        readHandler.callCount > 0

      runs ->
        expect(readHandler.argsForCall[0][0]).toBe(unicodeText)

    it 'should readSync a file in UTF-16', ->
      fs.writeFileSync(file.getPath(), unicodeBytes)
      file.setEncoding('utf16le')
      expect(file.readSync()).toBe(unicodeText)

    it 'should write a file in UTF-16', ->
      file.setEncoding('utf16le')
      file.write(unicodeText)

      expect(fs.statSync(file.getPath()).size).toBe(2)
      content = fs.readFileSync(file.getPath()).toString('ascii')
      expect(content).toBe(unicodeBytes.toString('ascii'))
