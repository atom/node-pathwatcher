var binding = require('../build/Release/pathwatcher.node');
var events = require("events");
var util = require('util');

var handleWatchers = {};

function dispatch(event, handle, path) {
  if (!handle in handleWatchers)
    throw new Error('Emitting events for ' + path + ' while no one is listening to it');

  handleWatchers[handle].onEvent(event, path);
}

binding.setCallback(dispatch);

function HandleWatcher(path) {
  this.path = path;
  this.handle = binding.watch(path);

  handleWatchers[this.handle] = this;
}

util.inherits(HandleWatcher, events.EventEmitter);

HandleWatcher.prototype.onEvent = function(event, path) {
  if (event == 'rename') {
    this.path = path;
  } else if (event == 'delete') {
    this.close();
    this.emit('close');
    return;
  }

  this.emit('change', event, path);
}

HandleWatcher.prototype.closeIfNoListener = function() {
  if (this.listeners('change').length == 0)
    this.close();
}

HandleWatcher.prototype.close = function() {
  handleWatchers[this.handle] = undefined;
  binding.unwatch(this.handle);
}

function PathWatcher(path, callback) {
  this.handleWatcher = null;
  for (var i = 0; i < handleWatchers.length; ++i)
    if (handleWatchers[i].path == path) {
      this.handleWatcher = handleWatchers[i];
      break;
    }

  if (!this.handleWatcher) {
    this.handleWatcher = new HandleWatcher(path);
  }

  this.onChange = function(event, path) {
    if (typeof callback == 'function') callback.call(this, event, path);
    this.emit('change', event, path);
  }.bind(this);

  this.onClose = function() {
    this.emit('close');
  }.bind(this);

  this.handleWatcher.on('change', this.onChange);
  this.handleWatcher.on('close', this.onClose);
}

util.inherits(PathWatcher, events.EventEmitter);

PathWatcher.prototype.close = function() {
  this.handleWatcher.removeListener('change', this.onChange);
  this.handleWatcher.removeListener('close', this.onClose);
  this.handleWatcher.closeIfNoListener();
  this.emit('close');
}

exports.watch = function(path, callback) {
  path = require('path').resolve(path);
  return new PathWatcher(path, callback);
}

