# Simple test using Node's test runner with CommonJS
{ test } = require 'node:test'
assert = require 'node:assert'

test 'basic math', ->
  assert.equal 1 + 1, 2

test 'async test', ->
  await new Promise (resolve) -> setTimeout(resolve, 10)
  assert.ok true, 'Async works'

test 'objects', ->
  obj = { a: 1, b: 2 }
  assert.deepEqual obj, { a: 1, b: 2 }