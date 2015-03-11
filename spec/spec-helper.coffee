jasmine.getEnv().setIncludedTags([process.platform])

# Simplified version of waitsForPromise() from Atom.
#
# * fn {Function} that returns a {Promise}.
# * name {String} optional name to pass to `waitsFor()`.
global.waitsForPromise = (fn, name = 'waitsForPromise') ->
  promise = null
  isResolved = false
  waitsFor name, ->
    unless promise
      promise = fn()
      promise.then ->
        isResolved = true
      promise.catch (error) ->
        console.error("#{name} error: #{error}")
        jasmine.getEnv().currentSpec.fail(
          "Expected promise to be resolved, but it was rejected with #{jasmine.pp(error)}")
    isResolved
