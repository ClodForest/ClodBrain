# Message Router Tests
{ describe, it, expect, beforeEach, vi } = require 'vitest'
MessageRouter = require '../../src/services/message-router'
{
  createMockNeo4jTool
  isConversationId
  isMessageId
} = require '../setup'

# Mock Corpus Callosum
createMockCorpusCallosum = ->
  {
    orchestrate: vi.fn().mockResolvedValue({
      alphaResponse: { content: 'Alpha response' }
      betaResponse: { content: 'Beta response' }
      communications: []
      timestamp: new Date().toISOString()
    })
    interrupt: vi.fn()
    getStats: vi.fn().mockReturnValue({
      currentMode: 'parallel'
      activeProcesses: 0
    })
  }

describe 'MessageRouter', ->
  mockCorpus = null
  mockNeo4j = null
  router = null

  beforeEach ->
    mockCorpus = createMockCorpusCallosum()
    mockNeo4j = createMockNeo4jTool()
    router = new MessageRouter(mockCorpus, mockNeo4j)

  describe 'constructor', ->
    it 'should initialize with empty state', ->
      expect(router.activeConversations).toBeInstanceOf(Map)
      expect(router.messageHistory).toEqual([])
      expect(router.interrupted).toBe(false)

  describe 'processMessage', ->
    it 'should process message with new conversation', ->
      result = await router.processMessage('Hello world', 'parallel')

      expect(result).toMatchObject({
        conversationId: expect.any(String)
        userMessage: {
          content: 'Hello world'
          sender: 'user'
          timestamp: expect.any(String)
        }
        alphaResponse: { content: 'Alpha response' }
        betaResponse: { content: 'Beta response' }
      })

      expect(isConversationId(result.conversationId)).toBe(true)
      expect(mockCorpus.orchestrate).toHaveBeenCalledWith(
        'Hello world'
        result.conversationId
        'parallel'
      )

    it 'should use existing conversation', ->
      result1 = await router.processMessage('First message')
      convId = result1.conversationId

      result2 = await router.processMessage('Second message', 'parallel', convId)

      expect(result2.conversationId).toBe(convId)

      conversation = router.getConversation(convId)
      expect(conversation.messages).toHaveLength(4) # 2 user + 2 AI

    it 'should store messages in Neo4j', ->
      await router.processMessage('Test message')

      # Should store conversation
      expect(mockNeo4j.executeQuery).toHaveBeenCalledWith(
        expect.stringContaining('CREATE (c:Conversation')
        expect.objectContaining({
          id: expect.any(String)
          startTime: expect.any(String)
        })
      )

      # Should store messages (user + alpha + beta)
      calls = mockNeo4j.executeQuery.mock.calls
      messageCalls = calls.filter((call) ->
        call[0].includes('CREATE (m:Message')
      )
      expect(messageCalls).toHaveLength(3)

    it 'should handle synthesis responses', ->
      mockCorpus.orchestrate.mockResolvedValue({
        alphaResponse: { content: 'Alpha' }
        betaResponse: { content: 'Beta' }
        synthesis: { content: 'Synthesized response' }
        communications: []
      })

      result = await router.processMessage('Synthesize this', 'synthesis')

      expect(result.synthesis).toMatchObject({ content: 'Synthesized response' })

      conversation = router.getConversation(result.conversationId)
      synthesisMessage = conversation.messages.find((m) -> m.sender is 'synthesis')
      expect(synthesisMessage).toBeTruthy()

    it 'should handle handoff mode with primary', ->
      mockCorpus.orchestrate.mockResolvedValue({
        alphaResponse: { content: 'Alpha only' }
        betaResponse: null
        primary: 'alpha'
        communications: []
      })

      result = await router.processMessage('Analyze this', 'handoff')

      expect(result.primary).toBe('alpha')
      expect(result.alphaResponse).toBeTruthy()
      expect(result.betaResponse).toBe(null)

    it 'should store communications in Neo4j', ->
      mockCorpus.orchestrate.mockResolvedValue({
        alphaResponse: { content: 'Alpha' }
        betaResponse: { content: 'Beta' }
        communications: [
          { from: 'alpha', to: 'beta', message: 'Handoff', type: 'handoff' }
        ]
      })

      await router.processMessage('Test')

      commCall = mockNeo4j.executeQuery.mock.calls.find((call) ->
        call[0].includes('CREATE (comm:Communication')
      )

      expect(commCall).toBeTruthy()
      expect(commCall[1]).toMatchObject({
        fromBrain: 'alpha'
        toBrain: 'beta'
        content: 'Handoff'
        type: 'handoff'
      })

    it 'should extract and store knowledge', ->
      mockCorpus.orchestrate.mockResolvedValue({
        alphaResponse: { content: 'Analyzing Claude and Anthropic data' }
        betaResponse: { content: 'Creating innovative solutions' }
        communications: []
      })

      await router.processMessage('Tell me about Claude')

      # Should extract entities
      entityCalls = mockNeo4j.executeQuery.mock.calls.filter((call) ->
        call[0].includes('MERGE (e:Entity')
      )

      expect(entityCalls.length).toBeGreaterThan(0)

      # Check for extracted entities
      entityNames = entityCalls.map((call) -> call[1].name)
      expect(entityNames).toContain('Claude')
      expect(entityNames).toContain('Anthropic')

  describe 'conversation management', ->
    it 'should initialize conversation correctly', ->
      conversation = router.initializeConversation('conv123')

      expect(conversation).toMatchObject({
        id: 'conv123'
        startTime: expect.any(String)
        lastActivity: expect.any(String)
        messages: []
        mode: 'parallel'
        messageCount: 0
        participants: ['user', 'alpha', 'beta']
      })

      expect(router.activeConversations.has('conv123')).toBe(true)

    it 'should update conversation metadata', ->
      result = await router.processMessage('First', 'parallel')
      convId = result.conversationId

      conversation1 = router.getConversation(convId)
      lastActivity1 = conversation1.lastActivity

      # Wait a bit and send another message
      await new Promise((resolve) -> setTimeout(resolve, 10))

      await router.processMessage('Second', 'debate', convId)

      conversation2 = router.getConversation(convId)
      expect(conversation2.mode).toBe('debate')
      expect(conversation2.messageCount).toBe(4) # 2 user + 2 AI
      expect(conversation2.lastActivity).not.toBe(lastActivity1)

  describe 'knowledge extraction', ->
    it 'should extract entities from capitalized words', ->
      entities = router.extractEntities(
        'Tell me about Machine Learning'
        { alphaResponse: 'Claude is an AI by Anthropic' }
      )

      entityNames = entities.map((e) -> e.name)
      expect(entityNames).toContain('Machine Learning')
      expect(entityNames).toContain('Claude')
      expect(entityNames).toContain('Anthropic')

    it 'should filter common words', ->
      entities = router.extractEntities(
        'The quick Brown Fox'
        {}
      )

      entityNames = entities.map((e) -> e.name)
      expect(entityNames).not.toContain('The')
      expect(entityNames).toContain('Brown Fox')

    it 'should extract concepts', ->
      concepts = router.extractConcepts(
        'Understanding programming'
        { alphaResponse: 'Implementation requires planning' }
      )

      conceptNames = concepts.map((c) -> c.name)
      expect(conceptNames).toContain('Understanding')
      expect(conceptNames).toContain('programming')
      expect(conceptNames).toContain('Implementation')
      expect(conceptNames).toContain('planning')

  describe 'utilities', ->
    it 'should generate unique conversation IDs', ->
      id1 = router.generateConversationId()
      id2 = router.generateConversationId()

      expect(isConversationId(id1)).toBe(true)
      expect(isConversationId(id2)).toBe(true)
      expect(id1).not.toBe(id2)

    it 'should generate unique message IDs', ->
      id1 = router.generateMessageId()
      id2 = router.generateMessageId()

      expect(isMessageId(id1)).toBe(true)
      expect(isMessageId(id2)).toBe(true)
      expect(id1).not.toBe(id2)

    it 'should get conversation by ID', ->
      result = await router.processMessage('Test')
      conversation = router.getConversation(result.conversationId)

      expect(conversation).toBeTruthy()
      expect(conversation.id).toBe(result.conversationId)

    it 'should get all conversations', ->
      await router.processMessage('Test 1')
      await router.processMessage('Test 2')

      conversations = router.getAllConversations()
      expect(conversations).toHaveLength(2)

    it 'should get message history with limit', ->
      # Add many messages
      for i in [1..10]
        await router.processMessage("Message #{i}")

      history = router.getMessageHistory(5)
      expect(history).toHaveLength(5)

      # Should be the last 5 messages
      expect(history[4].content).toContain('Message 10')

  describe 'interruption', ->
    it 'should interrupt processing', ->
      router.interrupt()

      expect(router.interrupted).toBe(true)
      expect(mockCorpus.interrupt).toHaveBeenCalled()

    it 'should clear interrupt', ->
      router.interrupt()
      router.clearInterrupt()

      expect(router.interrupted).toBe(false)

  describe 'stats', ->
    it 'should return router statistics', ->
      await router.processMessage('Test 1')
      await router.processMessage('Test 2')
      router.interrupt()

      stats = router.getStats()

      expect(stats).toMatchObject({
        activeConversations: 2
        totalMessages: expect.any(Number)
        interrupted: true
        corpusStats: {
          currentMode: 'parallel'
          activeProcesses: 0
        }
      })

  describe 'error handling', ->
    it 'should handle corpus orchestration errors', ->
      mockCorpus.orchestrate.mockRejectedValue(new Error('Orchestration failed'))

      await expect(
        router.processMessage('Test')
      ).rejects.toThrow('Orchestration failed')

    it 'should handle Neo4j storage errors gracefully', ->
      mockNeo4j.executeQuery.mockRejectedValue(new Error('DB error'))

      # Should not throw, just log errors
      await expect(
        router.processMessage('Test')
      ).resolves.toBeTruthy()

    it 'should handle missing response content', ->
      mockCorpus.orchestrate.mockResolvedValue({
        alphaResponse: 'Plain string response'
        betaResponse: null
        communications: []
      })

      result = await router.processMessage('Test')

      conversation = router.getConversation(result.conversationId)
      alphaMessage = conversation.messages.find((m) -> m.sender is 'alpha')

      expect(alphaMessage.content).toBe('Plain string response')

  describe 'Neo4j storage edge cases', ->
    it 'should flatten objects for Neo4j', ->
      mockCorpus.orchestrate.mockResolvedValue({
        alphaResponse: { content: 'Alpha' }
        betaResponse: { content: 'Beta' }
        communications: [{
          from: { name: 'alpha' }  # Object instead of string
          to: { name: 'beta' }
          message: 123  # Number instead of string
          type: null
          timestamp: new Date()
        }]
      })

      await router.processMessage('Test')

      commCall = mockNeo4j.executeQuery.mock.calls.find((call) ->
        call[0].includes('CREATE (comm:Communication')
      )

      # Should convert to strings
      expect(commCall[1].fromBrain).toBe('[object Object]')
      expect(commCall[1].content).toBe('123')
      expect(commCall[1].type).toBe('null')