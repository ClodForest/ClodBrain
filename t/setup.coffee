# Test setup and utilities
{ vi } = require 'vitest'

# Common test utilities
module.exports = {
  # Create mock Ollama response
  createMockOllamaResponse: (content) ->
    {
      data: {
        response: content
        model: 'test-model'
        created_at: new Date().toISOString()
        done: true
      }
    }

  # Create mock Neo4j driver
  createMockNeo4jDriver: ->
    sessions = []

    mockSession = {
      run: vi.fn().mockResolvedValue({
        records: []
        summary: {
          counters: {}
          resultAvailableAfter: 1
          resultConsumedAfter: 2
        }
      })
      close: vi.fn().mockResolvedValue(undefined)
    }

    driver = {
      session: vi.fn().mockImplementation(->
        sessions.push(mockSession)
        mockSession
      )
      close: vi.fn().mockResolvedValue(undefined)
      getSessions: -> sessions
    }

    driver

  # Create mock Neo4j tool
  createMockNeo4jTool: ->
    {
      connect: vi.fn().mockResolvedValue(true)
      executeQuery: vi.fn().mockResolvedValue({
        records: []
        summary: {}
      })
      naturalLanguageQuery: vi.fn().mockResolvedValue({
        records: []
      })
      addKnowledge: vi.fn().mockResolvedValue(undefined)
      generateSchema: vi.fn().mockResolvedValue({
        nodeTypes: []
        relationshipTypes: []
      })
      getStats: vi.fn().mockResolvedValue({
        totalNodes: 0
        totalRelationships: 0
        nodeTypes: {}
      })
    }

  # Create mock Axios for Ollama
  createMockAxios: ->
    axios = {
      post: vi.fn()
      get: vi.fn()
      _reset: ->
        @post.mockReset()
        @get.mockReset()
    }
    axios

  # Wait for promises with timeout
  waitForPromises: (timeout = 100) ->
    new Promise (resolve) ->
      setTimeout resolve, timeout

  # Create test message
  createTestMessage: (content = 'Test message', extras = {}) ->
    {
      content: content
      timestamp: new Date().toISOString()
      sender: 'user'
      ...extras
    }

  # Assert communication structure
  assertCommunication: (comm, expected) ->
    expect(comm).toMatchObject({
      type: expected.type
      timestamp: expect.any(Number)
      content: expect.any(String)
    })

    if expected.from
      expect(comm.from).toBe(expected.from)
    if expected.to
      expect(comm.to).toBe(expected.to)

  # Create test config
  createTestConfig: (overrides = {}) ->
    {
      alpha: {
        model: 'test-alpha'
        role: 'analytical'
        personality: 'test-analytical'
        system_prompt: 'Test alpha prompt'
        temperature: 0.3
        max_tokens: 100
        top_p: 0.9
        ...overrides.alpha
      }
      beta: {
        model: 'test-beta'
        role: 'creative'
        personality: 'test-creative'
        system_prompt: 'Test beta prompt'
        temperature: 0.7
        max_tokens: 100
        top_p: 0.95
        ...overrides.beta
      }
      corpus_callosum: {
        default_mode: 'parallel'
        communication_timeout: 1000
        max_iterations: 3
        synthesis_threshold: 0.8
        timeout: 1000
        modes: {
          parallel: { timeout: 500 }
          sequential: { default_order: ['alpha', 'beta'], handoff_delay: 100 }
          debate: { max_rounds: 2, convergence_threshold: 0.9 }
          synthesis: { synthesis_model: 'alpha', show_individual: false }
          handoff: { trigger_phrases: ['hand this over'] }
        }
        ...overrides.corpus_callosum
      }
    }

  # Create test Ollama config
  createTestOllamaConfig: ->
    {
      host: 'http://localhost:11434'
      timeout: 1000
      defaultConfig: {
        timeout: 1000
        headers: { 'Content-Type': 'application/json' }
      }
    }

  # Pattern matchers
  isUUID: (str) ->
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(str)

  isProcessId: (str) ->
    str.startsWith('proc_') and str.length > 15

  isMessageId: (str) ->
    str.startsWith('msg_') and str.length > 14

  isConversationId: (str) ->
    str.startsWith('conv_') and str.length > 15

  # Socket.io mock
  createMockSocket: ->
    emittedEvents = []

    socket = {
      id: 'test-socket-123'
      emit: vi.fn().mockImplementation((event, data) ->
        emittedEvents.push({ event, data })
      )
      on: vi.fn()
      getEmitted: (eventName = null) ->
        if eventName
          emittedEvents.filter((e) -> e.event is eventName)
        else
          emittedEvents
      clearEmitted: ->
        emittedEvents = []
    }

    socket
}