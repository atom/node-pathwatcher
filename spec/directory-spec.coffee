path = require 'path'
fs = require 'fs-plus'
temp = require 'temp'
Directory = require '../lib/directory'
PathWatcher = require '../lib/main'

describe "Directory", ->
  directory = null

  beforeEach ->
    directory = new Directory(path.join(__dirname, 'fixtures'))

  afterEach ->
    directory.off()
    PathWatcher.closeAllWatchers()

  it 'returns false from isFile()', ->
    expect(directory.isFile()).toBe false

  it 'returns true from isDirectory()', ->
    expect(directory.isDirectory()).toBe true

  describe "when the contents of the directory change on disk", ->
    temporaryFilePath = null

    beforeEach ->
      temporaryFilePath = path.join(__dirname, 'fixtures', 'temporary')
      fs.removeSync(temporaryFilePath)

    afterEach ->
      fs.removeSync(temporaryFilePath)

    it "triggers 'contents-changed' event handlers", ->
      changeHandler = null

      runs ->
        changeHandler = jasmine.createSpy('changeHandler')
        directory.on 'contents-changed', changeHandler
        fs.writeFileSync(temporaryFilePath, '')

      waitsFor "first change", -> changeHandler.callCount > 0

      runs ->
        changeHandler.reset()
        fs.removeSync(temporaryFilePath)

      waitsFor "second change", -> changeHandler.callCount > 0

  describe "when the directory unsubscribes from events", ->
    temporaryFilePath = null

    beforeEach ->
      temporaryFilePath = path.join(directory.path, 'temporary')
      fs.removeSync(temporaryFilePath) if fs.existsSync(temporaryFilePath)

    afterEach ->
      fs.removeSync(temporaryFilePath) if fs.existsSync(temporaryFilePath)

    it "no longer triggers events", ->
      changeHandler = null

      runs ->
        changeHandler = jasmine.createSpy('changeHandler')
        directory.on 'contents-changed', changeHandler
        fs.writeFileSync(temporaryFilePath, '')

      waitsFor "change event", -> changeHandler.callCount > 0

      runs ->
        changeHandler.reset()
        directory.off()
      waits 20

      runs -> fs.removeSync(temporaryFilePath)
      waits 20
      runs -> expect(changeHandler.callCount).toBe 0

  describe "on #darwin or #linux", ->
    it "includes symlink information about entries", ->
      entries = directory.getEntriesSync()
      for entry in entries
        name = entry.getBaseName()
        if name is 'symlink-to-dir' or name is 'symlink-to-file'
          expect(entry.symlink).toBeTruthy()
        else
          expect(entry.symlink).toBeFalsy()

      callback = jasmine.createSpy('getEntries')
      directory.getEntries(callback)

      waitsFor -> callback.callCount is 1

      runs ->
        entries = callback.mostRecentCall.args[1]
        for entry in entries
          name = entry.getBaseName()
          if name is 'symlink-to-dir' or name is 'symlink-to-file'
            expect(entry.symlink).toBeTruthy()
          else
            expect(entry.symlink).toBeFalsy()

  describe ".relativize(path)", ->
    describe "on #darwin or #linux", ->
      it "returns a relative path based on the directory's path", ->
        absolutePath = directory.getPath()
        expect(directory.relativize(absolutePath)).toBe ''
        expect(directory.relativize(path.join(absolutePath, "b"))).toBe "b"
        expect(directory.relativize(path.join(absolutePath, "b/file.coffee"))).toBe "b/file.coffee"
        expect(directory.relativize(path.join(absolutePath, "file.coffee"))).toBe "file.coffee"

      it "returns a relative path based on the directory's symlinked source path", ->
        symlinkPath = path.join(__dirname, 'fixtures', 'symlink-to-dir')
        symlinkDirectory = new Directory(symlinkPath)
        realFilePath = require.resolve('./fixtures/dir/a')
        expect(symlinkDirectory.relativize(symlinkPath)).toBe ''
        expect(symlinkDirectory.relativize(realFilePath)).toBe 'a'

      it "returns the full path if the directory's path is not a prefix of the path", ->
        expect(directory.relativize('/not/relative')).toBe '/not/relative'

      it "handled case insensitive filesystems", ->
        spyOn(fs, 'isCaseInsensitive').andReturn true
        directoryPath = temp.mkdirSync('Mixed-case-directory-')
        directory = new Directory(directoryPath)

        expect(directory.relativize(directoryPath.toUpperCase())).toBe ""
        expect(directory.relativize(path.join(directoryPath.toUpperCase(), "b"))).toBe "b"
        expect(directory.relativize(path.join(directoryPath.toUpperCase(), "B"))).toBe "B"
        expect(directory.relativize(path.join(directoryPath.toUpperCase(), "b/file.coffee"))).toBe "b/file.coffee"
        expect(directory.relativize(path.join(directoryPath.toUpperCase(), "file.coffee"))).toBe "file.coffee"

        expect(directory.relativize(directoryPath.toLowerCase())).toBe ""
        expect(directory.relativize(path.join(directoryPath.toLowerCase(), "b"))).toBe "b"
        expect(directory.relativize(path.join(directoryPath.toLowerCase(), "B"))).toBe "B"
        expect(directory.relativize(path.join(directoryPath.toLowerCase(), "b/file.coffee"))).toBe "b/file.coffee"
        expect(directory.relativize(path.join(directoryPath.toLowerCase(), "file.coffee"))).toBe "file.coffee"

        expect(directory.relativize(directoryPath)).toBe ""
        expect(directory.relativize(path.join(directoryPath, "b"))).toBe "b"
        expect(directory.relativize(path.join(directoryPath, "B"))).toBe "B"
        expect(directory.relativize(path.join(directoryPath, "b/file.coffee"))).toBe "b/file.coffee"
        expect(directory.relativize(path.join(directoryPath, "file.coffee"))).toBe "file.coffee"

    describe "on #win32", ->
      it "returns a relative path based on the directory's path", ->
        absolutePath = directory.getPath()
        expect(directory.relativize(absolutePath)).toBe ''
        expect(directory.relativize(path.join(absolutePath, "b"))).toBe "b"
        expect(directory.relativize(path.join(absolutePath, "b/file.coffee"))).toBe "b\\file.coffee"
        expect(directory.relativize(path.join(absolutePath, "file.coffee"))).toBe "file.coffee"

      it "returns the full path if the directory's path is not a prefix of the path", ->
        expect(directory.relativize('/not/relative')).toBe "\\not\\relative"

  describe ".contains(path)", ->
    it "returns true if the path is a child of the directory's path", ->
      absolutePath = directory.getPath()
      expect(directory.contains(path.join(absolutePath))).toBe false
      expect(directory.contains(path.join(absolutePath, "b"))).toBe true
      expect(directory.contains(path.join(absolutePath, "b", "file.coffee"))).toBe true
      expect(directory.contains(path.join(absolutePath, "file.coffee"))).toBe true

    it "returns false if the directory's path is not a prefix of the path", ->
      expect(directory.contains('/not/relative')).toBe false

    it "handles case insensitive filesystems", ->
      spyOn(fs, 'isCaseInsensitive').andReturn true
      directoryPath = temp.mkdirSync('Mixed-case-directory-')
      directory = new Directory(directoryPath)

      expect(directory.contains(directoryPath.toUpperCase())).toBe false
      expect(directory.contains(path.join(directoryPath.toUpperCase(), "b"))).toBe true
      expect(directory.contains(path.join(directoryPath.toUpperCase(), "B"))).toBe true
      expect(directory.contains(path.join(directoryPath.toUpperCase(), "b", "file.coffee"))).toBe true
      expect(directory.contains(path.join(directoryPath.toUpperCase(), "file.coffee"))).toBe true

      expect(directory.contains(directoryPath.toLowerCase())).toBe false
      expect(directory.contains(path.join(directoryPath.toLowerCase(), "b"))).toBe true
      expect(directory.contains(path.join(directoryPath.toLowerCase(), "B"))).toBe true
      expect(directory.contains(path.join(directoryPath.toLowerCase(), "b", "file.coffee"))).toBe true
      expect(directory.contains(path.join(directoryPath.toLowerCase(), "file.coffee"))).toBe true

      expect(directory.contains(directoryPath)).toBe false
      expect(directory.contains(path.join(directoryPath, "b"))).toBe true
      expect(directory.contains(path.join(directoryPath, "B"))).toBe true
      expect(directory.contains(path.join(directoryPath, "b", "file.coffee"))).toBe true
      expect(directory.contains(path.join(directoryPath, "file.coffee"))).toBe true

    describe "on #darwin or #linux", ->
      it "returns true if the path is a child of the directory's symlinked source path", ->
        symlinkPath = path.join(__dirname, 'fixtures', 'symlink-to-dir')
        symlinkDirectory = new Directory(symlinkPath)
        realFilePath = require.resolve('./fixtures/dir/a')
        expect(symlinkDirectory.contains(realFilePath)).toBe true

    describe "traversal", ->
      beforeEach ->
        directory = new Directory(path.join __dirname, 'fixtures', 'dir')

      fixturePath = (parts...) ->
        path.join __dirname, 'fixtures', parts...

      describe "getFile(filename)", ->
        it "returns a File within this directory", ->
          f = directory.getFile("a")
          expect(f.isFile()).toBe(true)
          expect(f.getRealPathSync()).toBe(fixturePath 'dir', 'a')

        it "can descend more than one directory at a time", ->
          f = directory.getFile("subdir", "b")
          expect(f.isFile()).toBe(true)
          expect(f.getRealPathSync()).toBe(fixturePath 'dir', 'subdir', 'b')

        it "doesn't have to actually exist", ->
          f = directory.getFile("the-silver-bullet")
          expect(f.isFile()).toBe(true)
          expect(f.exists()).toBe(false)

        it "does fail if you give it a directory though", ->
          tryit = -> directory.getFile("subdir")
          expect(tryit).toThrow()

      describe "getSubdir(dirname)", ->
        it "returns a subdirectory within this directory", ->
          d = directory.getSubdirectory("subdir")
          expect(d.isDirectory()).toBe(true)
          expect(d.getRealPathSync()).toBe(fixturePath 'dir', 'subdir')

        it "can descend more than one directory at a time", ->
          d = directory.getSubdirectory("subdir", "subsubdir")
          expect(d.isDirectory()).toBe(true)
          expect(d.getRealPathSync()).toBe(fixturePath 'dir', 'subdir', 'subsubdir')

        it "doesn't have to exist", ->
          d = directory.getSubdirectory("why-would-you-call-a-directory-this-come-on-now")
          expect(d.isDirectory()).toBe(true)

      describe "getParent()", ->
        it "returns the parent Directory", ->
          d = directory.getParent()
          expect(d.isDirectory()).toBe(true)
          expect(d.getRealPathSync()).toBe(fixturePath())
