watcher = require('./lib/main.js');

var r = watcher.watch('/tmp/test.txt', function(event, path) {
  console.log(event, path);
});

require('fs').writeFileSync('/tmp/test.txt', '1');
