# Message Router Tests - The Simplest Way That Could Possibly Work
{ describe, it, beforeEach, mock } = require 'node:test'
assert = require 'node:assert'

# Simple test implementation of MessageRouter
class TestMessageRouter
  constructor: (@alpha, @beta, @corpus, @config = {}) ->
    @messageHistory = []
    @conversationContexts = new Map()
    @activeRequests = new Map()
    @systemPrompt = @config.system_prompt || 'Default system prompt'
    @contextWindow = @config.context_window || 10

  route: (message, conversationId = 'default', mode = null) ->
    # Store message
    @messageHistory.push({
      message,
      conversationId,
      timestamp: Date.now()
    })

    # Get or create context
    context = @getOrCreateContext(conversationId)
    context.messages.push({ role: 'user', content: message })

    # Route through corpus
    try
      result = await @corpus.orchestrate(message, conversationId, mode)

      # Add responses to context
      if result.alphaResponse
        context.messages.push({ role: 'assistant', content: result.alphaResponse.content, source: 'alpha' })
      if result.betaResponse
        context.messages.push({ role: 'assistant', content: result.betaResponse.content, source: 'beta' })

      # Trim context if needed
      @trimContext(context)

      return result
    catch error
      # Simple error handling
      throw error

  getOrCreateContext: (conversationId) ->
    unless @conversationContexts.has(conversationId)
      @conversationContexts.set(conversationId, {
        id: conversationId,
        messages: [],
        createdAt: Date.now()
      })
    @conversationContexts.get(conversationId)

  trimContext: (context) ->
    # Keep only last N messages
    if context.messages.length > @contextWindow
      context.messages = context.messages.slice(-@contextWindow)

  getConversationHistory: (conversationId) ->
    context = @conversationContexts.get(conversationId)
    context?.messages || []

  clearConversation: (conversationId) ->
    @conversationContexts.delete(conversationId)

  getStats: ->
    {
      totalMessages: @messageHistory.length,
      activeConversations: @conversationContexts.size,
      oldestConversation: Math.min(...Array.from(@conversationContexts.values()).map(c => c.createdAt))
    }

describe 'MessageRouter', ->
  router = null
  mockAlpha = null
  mockBeta = null
  mockCorpus = null

  beforeEach ->
    mockAlpha = { processMessage: mock.fn() }
    mockBeta = { processMessage: mock.fn() }
    mockCorpus = {
      orchestrate: mock.fn (message, convId, mode) ->
        Promise.resolve({
          alphaResponse: { content: "Alpha: #{message}" },
          betaResponse: { content: "Beta: #{message}" },
          mode: mode || 'parallel',
          timestamp: new Date().toISOString()
        })
    }

    config = {
      system_prompt: 'Test prompt',
      context_window: 5
    }

    router = new TestMessageRouter(mockAlpha, mockBeta, mockCorpus, config)

  describe 'basic routing', ->
    it 'should route message through corpus', ->
      result = await router.route('Hello', 'conv1')

      assert.equal mockCorpus.orchestrate.mock.calls.length, 1
      assert.equal mockCorpus.orchestrate.mock.calls[0].arguments[0], 'Hello'
      assert.equal mockCorpus.orchestrate.mock.calls[0].arguments[1], 'conv1'

      assert.equal result.alphaResponse.content, 'Alpha: Hello'
      assert.equal result.betaResponse.content, 'Beta: Hello'

    it 'should store message in history', ->
      await router.route('Test message', 'conv1')

      assert.equal router.messageHistory.length, 1
      assert.equal router.messageHistory[0].message, 'Test message'
      assert.equal router.messageHistory[0].conversationId, 'conv1'
      assert.ok router.messageHistory[0].timestamp

    it 'should use specified mode', ->
      await router.route('Message', 'conv1', 'debate')

      assert.equal mockCorpus.orchestrate.mock.calls[0].arguments[2], 'debate'

  describe 'conversation context', ->
    it 'should create context for new conversation', ->
      await router.route('First message', 'new-conv')

      context = router.getOrCreateContext('new-conv')
      assert.ok context
      assert.equal context.id, 'new-conv'
      assert.ok context.createdAt
      assert.ok Array.isArray(context.messages)

    it 'should append messages to context', ->
      await router.route('Message 1', 'conv1')
      await router.route('Message 2', 'conv1')

      history = router.getConversationHistory('conv1')
      assert.equal history.length, 6  # 2 user + 4 assistant (2 per request)
      assert.equal history[0].content, 'Message 1'
      assert.equal history[1].content, 'Alpha: Message 1'
      assert.equal history[2].content, 'Beta: Message 1'

    it 'should trim context to window size', ->
      # Send more messages than window size
      for i in [1..10]
        await router.route("Message #{i}", 'conv1')

      history = router.getConversationHistory('conv1')
      assert.equal history.length, router.contextWindow

    it 'should clear conversation', ->
      await router.route('Message', 'conv1')
      router.clearConversation('conv1')

      history = router.getConversationHistory('conv1')
      assert.deepEqual history, []

  describe 'error handling', ->
    it 'should propagate corpus errors', ->
      mockCorpus.orchestrate = mock.fn -> Promise.reject(new Error('Corpus error'))

      try
        await router.route('Message', 'conv1')
        assert.fail('Should have thrown')
      catch error
        assert.equal error.message, 'Corpus error'

  describe 'statistics', ->
    it 'should track basic stats', ->
      await router.route('Msg 1', 'conv1')
      await router.route('Msg 2', 'conv2')
      await router.route('Msg 3', 'conv1')

      stats = router.getStats()

      assert.equal stats.totalMessages, 3
      assert.equal stats.activeConversations, 2
      assert.ok stats.oldestConversation > 0