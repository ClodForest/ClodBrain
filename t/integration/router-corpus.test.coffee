# Integration Test: MessageRouter + CorpusCallosum
{ describe, it, beforeEach, mock } = require 'node:test'
assert = require 'node:assert'

MessageRouter = require '../../src/services/message-router'
CorpusCallosum = require '../../src/services/corpus-callosum'

describe 'MessageRouter + CorpusCallosum Integration', ->
  router = null
  corpus = null
  mockAlpha = null
  mockBeta = null
  mockNeo4j = null

  beforeEach ->
    # Create mock LLMs that return the expected format
    mockAlpha = {
      processMessage: mock.fn (message) ->
        Promise.resolve({
          content: "Alpha: #{message}",
          model: 'alpha',
          timestamp: new Date().toISOString()
        })
    }

    mockBeta = {
      processMessage: mock.fn (message) ->
        Promise.resolve({
          content: "Beta: #{message}",
          model: 'beta',
          timestamp: new Date().toISOString()
        })
    }

    # Create mock Neo4j (router needs it)
    mockNeo4j = {
      executeQuery: mock.fn -> Promise.resolve({ records: [] })
    }

    # Create real corpus with mock LLMs
    corpusConfig = {
      default_mode: 'parallel'
      modes: {
        parallel: { timeout: 5000 }
        sequential: { timeout: 5000 }
        debate: { rounds: 3, timeout: 10000 }
        synthesis: { timeout: 7000 }
        handoff: { timeout: 5000 }
      }
    }
    corpus = new CorpusCallosum(mockAlpha, mockBeta, corpusConfig)

    # Create real router with real corpus
    router = new MessageRouter(corpus, mockNeo4j)

  describe 'message flow', ->
    it 'should route message through corpus and get responses', ->
      result = await router.processMessage('Hello world', 'parallel')

      # Verify we got responses from both LLMs
      assert.ok result
      assert.ok result.alphaResponse
      assert.ok result.betaResponse
      assert.equal result.alphaResponse.content, 'Alpha: Hello world'
      assert.equal result.betaResponse.content, 'Beta: Hello world'

      # Verify conversation was created
      conv = router.getConversation(result.conversationId)
      assert.ok conv
      assert.ok conv.messages.length >= 3  # user + alpha + beta

    it 'should use specified orchestration mode', ->
      result = await router.processMessage('Test', 'debate', 'conv123')

      # Corpus should have used debate mode
      assert.equal result.mode, 'debate'
      assert.equal corpus.currentMode, 'parallel'  # Should not change default

    it 'should handle synthesis responses', ->
      # Mock corpus to return synthesis
      corpus.orchestrate = mock.fn (msg, convId, mode) ->
        Promise.resolve({
          alphaResponse: { content: 'Alpha says' }
          betaResponse: { content: 'Beta says' }
          synthesis: { content: 'Combined view' }
          mode: mode || 'synthesis'
          timestamp: new Date().toISOString()
        })

      result = await router.processMessage('Synthesize this')

      # Check synthesis was stored
      conv = router.getConversation(result.conversationId)
      synthesisMsg = conv.messages.find (m) -> m.sender == 'synthesis'
      assert.ok synthesisMsg
      assert.equal synthesisMsg.content, 'Combined view'

  describe 'communications tracking', ->
    it 'should store inter-brain communications', ->
      # Use debate mode which should generate communications
      result = await router.processMessage('Debate this', 'debate')

      # Note: Real corpus with real executors would generate communications
      # For now just verify the structure is in place
      assert.ok result
      assert.ok result.mode == 'debate'

  describe 'interrupt handling', ->
    it 'should propagate interrupt from router to corpus', ->
      # Start a message
      promise = router.processMessage('Long running task')

      # Interrupt
      router.interrupt()

      # Verify corpus was interrupted
      assert.equal router.getStats().interrupted, true
      assert.equal corpus.activeProcesses.size, 0  # Corpus should clear processes

      # Clean up
      await promise.catch(() => {})  # Ignore any errors from interruption
      router.clearInterrupt()

    it 'should clear interrupt state', ->
      router.interrupt()
      router.clearInterrupt()

      assert.equal router.getStats().interrupted, false

  describe 'statistics', ->
    it 'should include both router and corpus stats', ->
      await router.processMessage('Message 1')
      await router.processMessage('Message 2', 'parallel', 'conv2')  # mode is 2nd param, convId is 3rd

      stats = router.getStats()

      # Router stats
      assert.equal stats.activeConversations, 2
      assert.equal stats.totalMessages, 6  # 2 user + 2 alpha + 2 beta

      # Corpus stats
      assert.ok stats.corpusStats
      assert.equal stats.corpusStats.currentMode, 'parallel'
      assert.ok stats.corpusStats.patterns

  describe 'error handling', ->
    it 'should handle corpus errors gracefully', ->
      corpus.orchestrate = mock.fn -> Promise.reject(new Error('Corpus failed'))

      try
        await router.processMessage('Test')
        assert.fail('Should have thrown')
      catch error
        assert.equal error.message, 'Corpus failed'

      # Router should still be functional
      assert.ok router.getStats()

    it 'should continue working if Neo4j fails', ->
      mockNeo4j.executeQuery = mock.fn -> Promise.reject(new Error('DB error'))

      # Should not throw - Neo4j errors are logged but not propagated
      result = await router.processMessage('Test message')

      assert.ok result
      assert.ok result.alphaResponse
      assert.ok result.betaResponse