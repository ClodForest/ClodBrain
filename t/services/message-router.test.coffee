# Message Router Tests - Simple and Real
{ describe, it, beforeEach, mock } = require 'node:test'
assert = require 'node:assert'
MessageRouter = require '../../src/services/message-router'

describe 'MessageRouter', ->
  router = null
  mockCorpus = null
  mockNeo4j = null

  beforeEach ->
    # Minimal mocks for dependencies
    mockCorpus = {
      orchestrate: mock.fn (message, convId, mode) ->
        Promise.resolve({
          alphaResponse: { content: "Alpha says: #{message}" }
          betaResponse: { content: "Beta says: #{message}" }
          timestamp: new Date().toISOString()
        })
      getStats: mock.fn -> { mode: 'parallel' }
      interrupt: mock.fn()
    }

    mockNeo4j = {
      executeQuery: mock.fn -> Promise.resolve({ records: [] })
    }

    router = new MessageRouter(mockCorpus, mockNeo4j)

  describe 'processMessage', ->
    it 'should process a message and return result', ->
      result = await router.processMessage('Hello world')

      assert.ok result
      assert.ok result.conversationId
      assert.ok result.userMessage
      assert.equal result.userMessage.content, 'Hello world'
      assert.equal result.alphaResponse.content, 'Alpha says: Hello world'
      assert.equal result.betaResponse.content, 'Beta says: Hello world'

    it 'should call corpus with message and mode', ->
      await router.processMessage('Test', 'debate')

      # Check corpus was called correctly
      calls = mockCorpus.orchestrate.mock.calls
      assert.equal calls.length, 1
      assert.equal calls[0].arguments[0], 'Test'
      assert.equal calls[0].arguments[2], 'debate'

    it 'should use provided conversation ID', ->
      result = await router.processMessage('Hi', 'parallel', 'my-conv-123')

      assert.equal result.conversationId, 'my-conv-123'
      assert.equal result.userMessage.conversationId, 'my-conv-123'

  describe 'conversation management', ->
    it 'should track active conversations', ->
      await router.processMessage('First', 'parallel', 'conv1')
      await router.processMessage('Second', 'parallel', 'conv2')

      assert.equal router.getAllConversations().length, 2

      conv1 = router.getConversation('conv1')
      assert.ok conv1
      assert.equal conv1.id, 'conv1'
      assert.ok conv1.messages.length > 0

    it 'should add messages to existing conversation', ->
      await router.processMessage('First', 'parallel', 'conv1')
      await router.processMessage('Second', 'parallel', 'conv1')

      conv = router.getConversation('conv1')
      # Should have: 2 user messages + 2 alpha + 2 beta = 6 messages
      assert.equal conv.messages.length, 6

  describe 'message history', ->
    it 'should track message history', ->
      await router.processMessage('Message 1')
      await router.processMessage('Message 2')

      history = router.getMessageHistory()
      # Each message creates 3 entries: user, alpha, beta
      assert.equal history.length, 6
      assert.equal history[0].content, 'Message 1'
      assert.equal history[0].sender, 'user'

    it 'should respect history limit', ->
      # Create many messages
      for i in [1..10]
        await router.processMessage("Message #{i}")

      limitedHistory = router.getMessageHistory(5)
      assert.equal limitedHistory.length, 5

  describe 'stats', ->
    it 'should return basic stats', ->
      await router.processMessage('Test 1')
      await router.processMessage('Test 2', 'parallel', 'conv2')

      stats = router.getStats()

      assert.equal stats.activeConversations, 2
      assert.ok stats.totalMessages > 0
      assert.equal stats.interrupted, false
      assert.ok stats.corpusStats

  describe 'interrupt', ->
    it 'should set interrupted flag and call corpus interrupt', ->
      router.interrupt()

      assert.equal router.getStats().interrupted, true
      assert.equal mockCorpus.interrupt.mock.calls.length, 1

    it 'should clear interrupt', ->
      router.interrupt()
      router.clearInterrupt()

      assert.equal router.getStats().interrupted, false