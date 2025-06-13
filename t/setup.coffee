# Test setup and utilities (CommonJS)
{ mock } = require 'node:test'

# Helper to add mockResolvedValue to mock functions
exports.createMockFn = (name = 'mockFn') ->
  fn = mock.fn()

  # Add helper methods that mimic Vitest/Jest
  fn.mockResolvedValue = (value) ->
    fn.mock.mockImplementation -> Promise.resolve(value)
    fn

  fn.mockRejectedValue = (error) ->
    fn.mock.mockImplementation -> Promise.reject(error)
    fn

  fn.mockReturnValue = (value) ->
    fn.mock.mockImplementation -> value
    fn

  fn.mockImplementation = (impl) ->
    fn.mock.mockImplementation impl
    fn

  fn.mockReset = ->
    fn.mock.resetCalls()
    fn

  fn

# Create mock Ollama response
exports.createMockOllamaResponse = (content) ->
  {
    data: {
      response: content
      model: 'test-model'
      created_at: new Date().toISOString()
      done: true
    }
  }

# Create mock Neo4j driver
exports.createMockNeo4jDriver = ->
  sessions = []

  mockSession = {
    run: mock.fn()
    close: mock.fn()
  }

  # Set up default resolved values
  mockSession.run.mock.mockImplementation ->
    Promise.resolve {
      records: []
      summary: {
        counters: {}
        resultAvailableAfter: 1
        resultConsumedAfter: 2
      }
    }

  mockSession.close.mock.mockImplementation ->
    Promise.resolve undefined

  driver = {
    session: mock.fn()
    close: mock.fn()
    getSessions: -> sessions
  }

  driver.session.mock.mockImplementation ->
    sessions.push(mockSession)
    mockSession

  driver

# Create mock Neo4j tool
exports.createMockNeo4jTool = ->
  tool = {
    connect: mock.fn()
    executeQuery: mock.fn()
    naturalLanguageQuery: mock.fn()
    addKnowledge: mock.fn()
    generateSchema: mock.fn()
    getStats: mock.fn()
  }

  # Set default implementations
  tool.connect.mock.mockImplementation -> Promise.resolve(true)
  tool.executeQuery.mock.mockImplementation -> Promise.resolve({ records: [], summary: {} })
  tool.naturalLanguageQuery.mock.mockImplementation -> Promise.resolve({ records: [] })
  tool.addKnowledge.mock.mockImplementation -> Promise.resolve(undefined)
  tool.generateSchema.mock.mockImplementation -> Promise.resolve({ nodeTypes: [], relationshipTypes: [] })
  tool.getStats.mock.mockImplementation -> Promise.resolve({ totalNodes: 0, totalRelationships: 0, nodeTypes: {} })

  tool

# Create mock Axios
exports.createMockAxios = ->
  axios = {
    post: mock.fn()
    get: mock.fn()
    _reset: ->
      @post.mock.resetCalls()
      @get.mock.resetCalls()
  }
  axios

# Wait for promises
exports.waitForPromises = (timeout = 100) ->
  new Promise (resolve) ->
    setTimeout resolve, timeout

# Test configuration
exports.createTestConfig = (overrides = {}) ->
  {
    alpha: {
      model: 'test-alpha'
      role: 'analytical'
      personality: 'test-analytical'
      system_prompt: 'Test alpha prompt'
      temperature: 0.3
      max_tokens: 100
      top_p: 0.9
      ...(overrides.alpha || {})
    }
    beta: {
      model: 'test-beta'
      role: 'creative'
      personality: 'test-creative'
      system_prompt: 'Test beta prompt'
      temperature: 0.7
      max_tokens: 100
      top_p: 0.95
      ...(overrides.beta || {})
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
      ...(overrides.corpus_callosum || {})
    }
  }