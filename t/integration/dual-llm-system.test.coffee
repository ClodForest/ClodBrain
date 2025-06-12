# Integration Tests - Full System
{ describe, it, expect, beforeEach, afterEach, vi } = require 'vitest'
DualLLMApp = require '../../src/app'
{
  createMockOllamaResponse
  createMockNeo4jDriver
  createMockSocket
  waitForPromises
} = require '../setup'
axios = require 'axios'
socketClient = require 'socket.io-client'

# Mock all external dependencies
vi.mock 'axios'
vi.mock 'socket.io-client'
vi.mock 'neo4j-driver', ->
  {
    driver: vi.fn().mockImplementation(-> createMockNeo4jDriver())
    auth: { basic: vi.fn() }
  }

describe 'Dual LLM System Integration', ->
  app = null
  mockSocket = null
  baseURL = 'http://localhost:3001'

  beforeEach ->
    # Set test environment
    process.env.PORT = '3001'
    process.env.NODE_ENV = 'test'

    # Mock Ollama responses
    axios.post.mockImplementation((url, data) ->
      if url.includes('/api/generate')
        model = data.model
        content = if model.includes('alpha')
          'Analytical response: ' + data.prompt
        else
          'Creative response: ' + data.prompt

        return Promise.resolve(createMockOllamaResponse(content))

      return Promise.reject(new Error('Unknown endpoint'))
    )

    axios.get.mockImplementation((url) ->
      if url.includes('/api/tags')
        return Promise.resolve({
          data: {
            models: [
              { name: 'llama3.1:8b-instruct-q4_K_M' }
              { name: 'qwen2.5-coder:7b-instruct-q4_K_M' }
            ]
          }
        })

      return Promise.reject(new Error('Unknown endpoint'))
    )

    # Create app instance
    app = new DualLLMApp()

    # Mock socket client
    mockSocket = createMockSocket()
    socketClient.connect.mockReturnValue(mockSocket)

  afterEach ->
    # Clean up
    if app?.server?.listening
      await new Promise((resolve) -> app.server.close(resolve))

    vi.clearAllMocks()

  describe 'Application Startup', ->
    it 'should initialize and start successfully', ->
      await app.initialize()

      # Check services initialized
      expect(app.llmAlpha).toBeTruthy()
      expect(app.llmBeta).toBeTruthy()
      expect(app.corpusCallosum).toBeTruthy()
      expect(app.neo4jTool).toBeTruthy()
      expect(app.messageRouter).toBeTruthy()

      # Start server
      await new Promise((resolve) ->
        app.start()
        setTimeout(resolve, 100)
      )

      expect(app.server.listening).toBe(true)

    it 'should handle initialization errors gracefully', ->
      # Make Neo4j connection fail
      neo4j = require('neo4j-driver')
      neo4j.driver.mockImplementationOnce(->
        throw new Error('Connection failed')
      )

      await expect(app.initialize()).rejects.toThrow('Connection failed')

  describe 'REST API Endpoints', ->
    beforeEach ->
      await app.initialize()
      app.start()
      await waitForPromises()

    it 'should process chat messages via API', ->
      response = await axios.post("#{baseURL}/api/chat/message", {
        message: 'Hello world'
        mode: 'parallel'
      })

      expect(response.data).toMatchObject({
        conversationId: expect.any(String)
        userMessage: {
          content: 'Hello world'
          sender: 'user'
        }
        alphaResponse: expect.any(Object)
        betaResponse: expect.any(Object)
      })

    it 'should get model information', ->
      response = await axios.get("#{baseURL}/api/models")

      expect(response.data).toMatchObject({
        alpha: {
          model: 'llama3.1:8b-instruct-q4_K_M'
          role: 'analytical'
          available: true
        }
        beta: {
          model: 'qwen2.5-coder:7b-instruct-q4_K_M'
          role: 'creative'
          available: true
        }
      })

    it 'should check health status', ->
      response = await axios.get("#{baseURL}/health")

      expect(response.data).toMatchObject({
        status: 'ok'
        timestamp: expect.any(String)
        services: {
          alpha: 'healthy'
          beta: 'healthy'
          neo4j: 'connected'
        }
      })

  describe 'WebSocket Communication', ->
    beforeEach ->
      await app.initialize()
      app.start()
      await waitForPromises()

    it 'should handle message flow through websockets', ->
      # Simulate connection
      connectionHandler = app.io.on.mock.calls[0]?[1]
      connectionHandler?(mockSocket)

      # Simulate message send
      messageHandler = mockSocket.on.mock.calls.find((call) ->
        call[0] is 'message_send'
      )?[1]

      await messageHandler?({
        message: 'Test websocket message'
        mode: 'parallel'
      })

      # Check emissions
      emissions = mockSocket.getEmitted()

      # Should emit both responses
      alphaEmission = emissions.find((e) -> e.event is 'alpha_response')
      betaEmission = emissions.find((e) -> e.event is 'beta_response')

      expect(alphaEmission).toBeTruthy()
      expect(alphaEmission.data.content).toContain('Analytical response')

      expect(betaEmission).toBeTruthy()
      expect(betaEmission.data.content).toContain('Creative response')

    it 'should handle synthesis mode', ->
      connectionHandler = app.io.on.mock.calls[0]?[1]
      connectionHandler?(mockSocket)

      messageHandler = mockSocket.on.mock.calls.find((call) ->
        call[0] is 'message_send'
      )?[1]

      await messageHandler?({
        message: 'Synthesize this'
        mode: 'synthesis'
      })

      emissions = mockSocket.getEmitted()
      synthesisEmission = emissions.find((e) -> e.event is 'synthesis_complete')

      expect(synthesisEmission).toBeTruthy()
      expect(synthesisEmission.data.mode).toBe('synthesis')

    it 'should handle handoff mode correctly', ->
      # Mock handoff response
      app.corpusCallosum.orchestrate = vi.fn().mockResolvedValue({
        alphaResponse: { content: 'Alpha handled this' }
        betaResponse: null
        primary: 'alpha'
        communications: []
      })

      connectionHandler = app.io.on.mock.calls[0]?[1]
      connectionHandler?(mockSocket)

      messageHandler = mockSocket.on.mock.calls.find((call) ->
        call[0] is 'message_send'
      )?[1]

      await messageHandler?({
        message: 'Analyze this data'
        mode: 'handoff'
      })

      emissions = mockSocket.getEmitted()

      # Should clear beta thinking
      clearBetaEmission = emissions.find((e) -> e.event is 'clear_beta_thinking')
      expect(clearBetaEmission).toBeTruthy()

      # Should emit completion
      completionEmission = emissions.find((e) -> e.event is 'interaction_complete')
      expect(completionEmission).toBeTruthy()
      expect(completionEmission.data.primary).toBe('alpha')

  describe 'Communication Modes', ->
    beforeEach ->
      await app.initialize()
      app.start()
      await waitForPromises()

    it 'should switch between modes dynamically', ->
      # Test parallel mode
      result1 = await app.messageRouter.processMessage('Test parallel', 'parallel')
      expect(result1.alphaResponse).toBeTruthy()
      expect(result1.betaResponse).toBeTruthy()

      # Switch to sequential
      app.corpusCallosum.setMode('sequential')

      # Mock sequential behavior
      callCount = 0
      axios.post.mockImplementation((url, data) ->
        if url.includes('/api/generate')
          callCount++
          content = if callCount is 1
            'First response'
          else
            'Second response with context'

          return Promise.resolve(createMockOllamaResponse(content))

        return Promise.reject(new Error('Unknown'))
      )

      result2 = await app.messageRouter.processMessage('Test sequential', 'sequential')
      expect(axios.post).toHaveBeenCalledTimes(2)

  describe 'Neo4j Integration', ->
    beforeEach ->
      await app.initialize()
      app.start()
      await waitForPromises()

    it 'should store conversations in Neo4j', ->
      await app.messageRouter.processMessage('Test message')

      # Check Neo4j calls
      neo4jDriver = app.neo4jTool.driver
      sessions = neo4jDriver.getSessions()

      # Should have created conversation and messages
      queries = sessions.flatMap((s) -> s.run.mock.calls)

      conversationQuery = queries.find((call) ->
        call[0].includes('CREATE (c:Conversation')
      )
      expect(conversationQuery).toBeTruthy()

      messageQueries = queries.filter((call) ->
        call[0].includes('CREATE (m:Message')
      )
      expect(messageQueries.length).toBeGreaterThan(0)

    it 'should extract and store knowledge', ->
      await app.messageRouter.processMessage(
        'Tell me about Claude and Anthropic'
      )

      sessions = app.neo4jTool.driver.getSessions()
      queries = sessions.flatMap((s) -> s.run.mock.calls)

      entityQueries = queries.filter((call) ->
        call[0].includes('MERGE (e:Entity')
      )

      # Should have extracted entities
      expect(entityQueries.length).toBeGreaterThan(0)

      # Check for specific entities
      entityNames = entityQueries.map((call) -> call[1].name)
      expect(entityNames).toContain('Claude')
      expect(entityNames).toContain('Anthropic')

  describe 'Error Handling', ->
    beforeEach ->
      await app.initialize()
      app.start()
      await waitForPromises()

    it 'should handle Ollama connection errors', ->
      axios.post.mockRejectedValue(new Error('ECONNREFUSED'))

      response = await axios.post("#{baseURL}/api/chat/message", {
        message: 'Test'
      }).catch((e) -> e.response)

      expect(response.status).toBe(500)
      expect(response.data.error).toContain('Cannot connect to Ollama')

    it 'should handle websocket errors gracefully', ->
      connectionHandler = app.io.on.mock.calls[0]?[1]
      connectionHandler?(mockSocket)

      # Make orchestration fail
      app.corpusCallosum.orchestrate = vi.fn().mockRejectedValue(
        new Error('Orchestration failed')
      )

      messageHandler = mockSocket.on.mock.calls.find((call) ->
        call[0] is 'message_send'
      )?[1]

      await messageHandler?({ message: 'Test' })

      emissions = mockSocket.getEmitted()
      errorEmission = emissions.find((e) -> e.event is 'error')

      expect(errorEmission).toBeTruthy()
      expect(errorEmission.data.message).toBe('Orchestration failed')

  describe 'Concurrent Requests', ->
    beforeEach ->
      await app.initialize()
      app.start()
      await waitForPromises()

    it 'should handle multiple simultaneous requests', ->
      # Send multiple requests concurrently
      promises = [1..5].map (i) ->
        app.messageRouter.processMessage("Message #{i}", 'parallel')

      results = await Promise.all(promises)

      # All should succeed
      expect(results).toHaveLength(5)

      # Each should have unique conversation ID
      conversationIds = results.map((r) -> r.conversationId)
      uniqueIds = new Set(conversationIds)
      expect(uniqueIds.size).toBe(5)

    it 'should handle rapid mode switching', ->
      modes = ['parallel', 'sequential', 'debate', 'synthesis', 'handoff']

      promises = modes.map (mode, i) ->
        app.messageRouter.processMessage("Test #{mode}", mode)

      results = await Promise.all(promises)

      # All modes should work
      expect(results).toHaveLength(5)
      results.forEach (result, i) ->
        expect(result.mode).toBe(modes[i])