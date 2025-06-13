# BaseLLM Tests (CommonJS)
{ describe, it, beforeEach } = require 'node:test'
assert = require 'node:assert'
{ mock } = require 'node:test'

# We'll need to update these paths when the source files are converted
# BaseLLM = require '../../src/services/base-llm'

# For now, let's create a simple test structure
describe 'BaseLLM', ->
  mockAxios = null
  mockNeo4j = null

  beforeEach ->
    # Create mocks using Node's built-in mock
    mockAxios = {
      post: mock.fn()
      get: mock.fn()
    }

    mockNeo4j = {
      connect: mock.fn()
      executeQuery: mock.fn()
      naturalLanguageQuery: mock.fn()
    }

  describe 'mock setup', ->
    it 'should have mock functions', ->
      assert.ok mockAxios.post.mock
      assert.ok mockAxios.get.mock
      assert.ok mockNeo4j.connect.mock

    it 'should track calls', ->
      mockAxios.post('test', { data: 'test' })
      assert.equal mockAxios.post.mock.calls.length, 1
      assert.equal mockAxios.post.mock.calls[0].arguments[0], 'test'

  describe 'basic tests', ->
    it 'should work with assertions', ->
      assert.equal 1 + 1, 2
      assert.ok true
      assert.deepEqual { a: 1 }, { a: 1 }

    it 'should handle async tests', ->
      result = await Promise.resolve('async value')
      assert.equal result, 'async value'