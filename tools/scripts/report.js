// Minimal helper that pulls in the vulnerable deps so SCA tools see them used.
const _ = require('lodash');
const args = require('minimist')(process.argv.slice(2));
console.log(_.merge({}, { source: args.in || 'export.csv' }));
