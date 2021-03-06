'use strict';
const common = require('../common');
const assert = require('assert');
const spawn = require('child_process').spawn;

if (!common.hasCrypto) {
  common.skip('missing crypto');
  return;
}

const child = spawn(process.execPath, ['debug']);
child.stderr.setEncoding('utf8');

const expectedUsageMessage = `Usage: node debug script.js
       node debug <host>:<port>
       node debug -p <pid>
`;
let actualUsageMessage = '';
child.stderr.on('data', function(data) {
  actualUsageMessage += data.toString();
});

child.on('exit', common.mustCall(function(code) {
  assert.strictEqual(code, 1);
  assert.strictEqual(actualUsageMessage, expectedUsageMessage);
}));
