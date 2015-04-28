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
    PathWatcher.closeAllWatchers()

  it "normalizes the specified path", ->
    expect(new Directory(directory.path + path.sep + 'abc' + path.sep + '..').getBaseName()).toBe 'fixtures'
    expect(new Directory(directory.path + path.sep + 'abc' + path.sep + '..').path.toLowerCase()).toBe directory.path.toLowerCase()

    expect(new Directory(directory.path + path.sep).getBaseName()).toBe 'fixtures'
    expect(new Directory(directory.path + path.sep).path.toLowerCase()).toBe directory.path.toLowerCase()

    expect(new Directory(directory.path + path.sep + path.sep).getBaseName()).toBe 'fixtures'
    expect(new Directory(directory.path + path.sep + path.sep).path.toLowerCase()).toBe directory.path.toLowerCase()

    expect(new Directory(path.sep).getBaseName()).toBe ''
    expect(new Directory(path.sep).path).toBe path.sep

  it 'returns false from isFile()', ->
    expect(directory.isFile()).toBe false

  it 'returns true from isDirectory()', ->
    expect(directory.isDirectory()).toBe true

  describe '::exists()', ->
    [callback, tempDir] = []

    beforeEach ->
      tempDir = temp.mkdirSync('node-pathwatcher-directory')
      callback = jasmine.createSpy('promiseCallback')

    it 'returns a Promise that resolves to true for an existing directory', ->
      directory = new Directory(tempDir)

      waitsForPromise ->
        directory.exists().then(callback)

      runs ->
        expect(callback.argsForCall[0][0]).toBe true

    it 'returns a Promise that resolves to false for a non-existent directory', ->
      directory = new Directory(path.join(tempDir, 'foo'))

      waitsForPromise ->
        directory.exists().then(callback)

      runs ->
        expect(callback.argsForCall[0][0]).toBe false

  describe '::existsSync()', ->
    [tempDir] = []

    beforeEach ->
      tempDir = temp.mkdirSync('node-pathwatcher-directory')

    it 'returns true for an existing directory', ->
      directory = new Directory(tempDir)
      expect(directory.existsSync()).toBe true

    it 'returns false for a non-existent directory', ->
      directory = new Directory(path.join(tempDir, 'foo'))
      expect(directory.existsSync()).toBe false

  describe '::create()', ->
    [callback, tempDir] = []

    beforeEach ->
      tempDir = temp.mkdirSync('node-pathwatcher-directory')
      callback = jasmine.createSpy('promiseCallback')

    it 'creates directory if directory does not exist', ->
      directoryName = path.join(tempDir, 'subdir')
      expect(fs.existsSync(directoryName)).toBe false
      nonExistentDirectory = new Directory(directoryName)

      waitsForPromise ->
        nonExistentDirectory.create(0o0700).then(callback)

      runs ->
        expect(callback.argsForCall[0][0]).toBe true
        expect(fs.existsSync(directoryName)).toBe true
        expect(fs.isDirectorySync(directoryName)).toBe true
        rawMode = fs.statSync(directoryName).mode
        mode = rawMode & 0o07777
        expect(mode.toString(8)).toBe (0o0700).toString(8)

    it 'leaves existing directory alone if it exists', ->
      directoryName = path.join(tempDir, 'subdir')
      fs.mkdirSync(directoryName)
      existingDirectory = new Directory(directoryName)

      waitsForPromise ->
        existingDirectory.create().then(callback)

      runs ->
        expect(callback.argsForCall[0][0]).toBe false
        expect(fs.existsSync(directoryName)).toBe true
        expect(fs.isDirectorySync(directoryName)).toBe true

    it 'creates parent directories if they do not exist', ->
      directoryName = path.join(tempDir, 'foo', 'bar', 'baz')
      expect(fs.existsSync(directoryName)).toBe false
      nonExistentDirectory = new Directory(directoryName)

      waitsForPromise ->
        nonExistentDirectory.create().then(callback)

      runs ->
        expect(callback.argsForCall[0][0]).toBe true

        expect(fs.existsSync(directoryName)).toBe true
        expect(fs.isDirectorySync(directoryName)).toBe true

        parentName = path.join(tempDir, 'foo', 'bar')
        expect(fs.existsSync(parentName)).toBe true
        expect(fs.isDirectorySync(parentName)).toBe true

    it "throws an error when called on a root directory that does not exist", ->
      spyOn(Directory::, 'isRoot').andReturn(true)
      directory = new Directory(path.join(tempDir, 'subdir'))

      waitsForPromise shouldReject: true, ->
        directory.create()

      runs ->
        expect(fs.existsSync(path.join(tempDir, 'subdir'))).toBe false

  describe '::delete()', ->
    tempDir = null

    beforeEach ->
      tempDir = temp.mkdirSync('node-pathwatcher-directory')

    it 'deletes empty directory', ->
      directoryName = path.join(tempDir, 'subdir')
      fs.mkdirSync(directoryName)
      existingDirectory = new Directory(directoryName)
      waitsForPromise ->
        existingDirectory.delete().then (result) ->
          expect(result).toBe true
          expect(fs.existsSync(directoryName)).toBe false

    it 'deletes non-empty directory', ->
      directoryName = path.join(tempDir, 'subdir')
      fs.makeTreeSync(path.join(directoryName, 'subdir'))
      existingDirectory = new Directory(directoryName)
      waitsForPromise ->
        existingDirectory.delete().then (result) ->
          expect(result).toBe true
          expect(fs.existsSync(directoryName)).toBe false

    it 'does nothing if directory does not exist', ->
      directoryName = path.join(tempDir, 'subdir')
      nonExistingDirectory = new Directory(directoryName)
      waitsForPromise ->
        nonExistingDirectory.delete().then (result) ->
          expect(result).toBe false
          expect(fs.existsSync(directoryName)).toBe false

  describe "when the contents of the directory change on disk", ->
    temporaryFilePath = null

    beforeEach ->
      temporaryFilePath = path.join(__dirname, 'fixtures', 'temporary')
      fs.removeSync(temporaryFilePath)

    afterEach ->
      fs.removeSync(temporaryFilePath)

    it "notifies ::onDidChange observers", ->
      changeHandler = null

      runs ->
        directory.onDidChange changeHandler = jasmine.createSpy('changeHandler')
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
      [subscription, changeHandler] = []

      runs ->
        subscription = directory.onDidChange changeHandler = jasmine.createSpy('changeHandler')
        fs.writeFileSync(temporaryFilePath, '')

      waitsFor "change event", -> changeHandler.callCount > 0

      runs ->
        changeHandler.reset()
        subscription.dispose()
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

  describe ".resolve(uri)", ->
    describe "when passed an absolute or relative path", ->
      it "returns an absolute path based on the directory's path", ->
        absolutePath = require.resolve('./fixtures/dir/a')
        expect(directory.resolve('dir/a')).toBe absolutePath
        expect(directory.resolve(absolutePath + '/../a')).toBe absolutePath
        expect(directory.resolve('dir/a/../a')).toBe absolutePath
        expect(directory.resolve()).toBeUndefined()

    describe "when passed a uri with a scheme", ->
      it "does not modify uris that begin with a scheme", ->
        expect(directory.resolve('http://zombo.com')).toBe 'http://zombo.com'

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
          expect(f.existsSync()).toBe(false)

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

      describe "isRoot()", ->
        it "returns false if the Directory isn't the root", ->
          expect(directory.isRoot()).toBe(false)

        it "returns true if the Directory is the root", ->
          [current, previous] = [directory, null]
          while current.getPath() isnt previous?.getPath()
            previous = current
            current = current.getParent()

          expect(current.isRoot()).toBe(true)
