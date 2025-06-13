# Integration Tests - Full System
{ describe, it, beforeEach, afterEach, mock } = require 'node:test'
assert = require 'node:assert'
{
  createMockOllamaResponse
  createMockNeo4jDriver
  createMockSocket
  waitForPromises
} = require '../setup'
axios = require 'axios'
socketClient = require 'socket.io-client'

# Mock all external dependencies
mock.module 'axios'
mock.module 'socket.io-client'
mock.module 'neo4j-driver', ->
  {
    driver: mock.fn().mock.mockImplementation(-> createMockNeo4jDriver())
    auth: { basic: mock.fn() }
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
    axios.post.mock.mockImplementation((url, data) ->
      if url.includes('/api/generate')
        model = data.model
        content = if model.includes('alpha')
          'Analytical response: ' + data.prompt
        else
          'Creative response: ' + data.prompt

        return Promise.resolve(createMockOllamaResponse(content))

      return Promise.reject(new Error('Unknown endpoint'))
    )

    axios.get.mock.mockImplementation((url) ->
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
    socketClient.connect.mock.mockImplementation(-> mockSocket)

  afterEach ->
    # Clean up
    if app?.server?.listening
      await new Promise((resolve) -> app.server.close(resolve))

    vi.clearAllMocks()

  describe 'Application Startup', ->
    it 'should initialize and start successfully', ->
      await app.initialize()

      # Check services initialized
      assert.ok app.llmAlpha
      assert.ok app.llmBeta
      assert.ok app.corpusCallosum
      assert.ok app.neo4jTool
      assert.ok app.messageRouter

      # Start server
      await new Promise((resolve) ->
        app.start()
        setTimeout(resolve, 100)
      )

      assert.equal app.server.listening, true

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

      assert.deepEqual response.data,({
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

      assert.deepEqual response.data,({
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

      assert.deepEqual response.data,({
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

      assert.ok alphaEmission
      expect(alphaEmission.data.content).toContain('Analytical response')

      assert.ok betaEmission
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

      assert.ok synthesisEmission
      assert.equal synthesisEmission.data.mode, 'synthesis'

    it 'should handle handoff mode correctly', ->
      # Mock handoff response
      app.corpusCallosum.orchestrate = mock.fn().mockResolvedValue({
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
      assert.ok clearBetaEmission

      # Should emit completion
      completionEmission = emissions.find((e) -> e.event is 'interaction_complete')
      assert.ok completionEmission
      assert.equal completionEmission.data.primary, 'alpha'

  describe 'Communication Modes', ->
    beforeEach ->
      await app.initialize()
      app.start()
      await waitForPromises()

    it 'should switch between modes dynamically', ->
      # Test parallel mode
      result1 = await app.messageRouter.processMessage('Test parallel', 'parallel')
      assert.ok result1.alphaResponse
      assert.ok result1.betaResponse

      # Switch to sequential
      app.corpusCallosum.setMode('sequential')

      # Mock sequential behavior
      callCount = 0
      axios.post.mock.mockImplementation((url, data) ->
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
      assert.equal axios.post.mock.calls.length, 2

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
      assert.ok conversationQuery

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
      axios.post.mock.mockImplementation(-> Promise.reject(new Error('ECONNREFUSED')))

      response = await axios.post("#{baseURL}/api/chat/message", {
        message: 'Test'
      }).catch((e) -> e.response)

      assert.equal response.status, 500
      expect(response.data.error).toContain('Cannot connect to Ollama')

    it 'should handle websocket errors gracefully', ->
      connectionHandler = app.io.on.mock.calls[0]?[1]
      connectionHandler?(mockSocket)

      # Make orchestration fail
      app.corpusCallosum.orchestrate = mock.fn().mockRejectedValue(
        new Error('Orchestration failed')
      )

      messageHandler = mockSocket.on.mock.calls.find((call) ->
        call[0] is 'message_send'
      )?[1]

      await messageHandler?({ message: 'Test' })

      emissions = mockSocket.getEmitted()
      errorEmission = emissions.find((e) -> e.event is 'error')

      assert.ok errorEmission
      assert.equal errorEmission.data.message, 'Orchestration failed'

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
      assert.equal uniqueIds.size, 5

    it 'should handle rapid mode switching', ->
      modes = ['parallel', 'sequential', 'debate', 'synthesis', 'handoff']

      promises = modes.map (mode, i) ->
        app.messageRouter.processMessage("Test #{mode}", mode)

      results = await Promise.all(promises)

      # All modes should work
      expect(results).toHaveLength(5)
      results.forEach (result, i) ->
        assert.equal result.mode, modes[i]