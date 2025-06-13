# BaseLLM Tests
{ describe, it, beforeEach, mock } = require 'node:test'
assert = require 'node:assert'
{
  createMockOllamaResponse
  createMockNeo4jTool
  createMockAxios
  createTestConfig
  createTestOllamaConfig
} = require '../setup'

describe 'BaseLLM', ->
  mockAxios = null
  mockNeo4j = null
  baseLLM = null
  config = null

  beforeEach ->
    mockAxios = createMockAxios()
    mockNeo4j = createMockNeo4jTool()
    config = createTestConfig()

    # Mock axios globally
    mock.module 'axios', -> mockAxios

    baseLLM = new BaseLLM(
      config.alpha
      createTestOllamaConfig()
      mockNeo4j
    )

  describe 'constructor', ->
    it 'should initialize with correct properties', ->
      expect(baseLLM.model).toBe 'test-alpha'
      expect(baseLLM.role).toBe 'analytical'
      expect(baseLLM.personality).toBe 'test-analytical'
      expect(baseLLM.systemPrompt).toBe 'Test alpha prompt'
      expect(baseLLM.neo4jTool).toBe mockNeo4j

    it 'should work without Neo4j tool', ->
      llmWithoutNeo4j = new BaseLLM(
        config.alpha
        createTestOllamaConfig()
        null
      )
      expect(llmWithoutNeo4j.neo4jTool).toBe null

  describe 'processMessage', ->
    it 'should process a simple message', ->
      mockAxios.post.mockResolvedValue(
        createMockOllamaResponse('Test response')
      )

      result = await baseLLM.processMessage('Hello')

      # TODO: Check mockAxios.post.mock.calls[0].arguments(
        'http://localhost:11434/api/generate'
        expect.objectContaining({
          model: 'test-alpha'
          prompt: expect.stringContaining('Hello')
          stream: false
        })
        expect.any(Object)
      )

      assert.deepEqual result,({
        content: 'Test response'
        model: 'test-alpha'
        role: 'analytical'
        timestamp: expect.any(String)
      })

    it 'should handle graph queries in message', ->
      mockAxios.post.mockResolvedValue(
        createMockOllamaResponse('Based on previous conversations...')
      )
      mockNeo4j.naturalLanguageQuery.mockResolvedValue({
        records: [{ id: 'conv1' }, { id: 'conv2' }]
      })

      result = await baseLLM.processMessage('What did we talk about before?')

      # TODO: Check mockNeo4j.naturalLanguageQuery.mock.calls[0].arguments('conversations')
      # TODO: Check mockAxios.post.mock.calls[0].arguments(
        expect.any(String)
        expect.objectContaining({
          prompt: expect.stringContaining('Recent conversations: 2 found')
        })
        expect.any(Object)
      )

    it 'should handle errors gracefully', ->
      mockAxios.post.mock.mockImplementation(-> Promise.reject(new Error('Connection failed')))

      await expect(baseLLM.processMessage('Hello')).rejects.toThrow(
        'BaseLLM processing failed: Connection failed'
      )

  describe 'buildPrompt', ->
    it 'should build prompt with all components', ->
      prompt = baseLLM.buildPrompt(
        'User message'
        { alpha: 'Alpha context', beta: 'Beta context' }
        'Graph context'
      )

      expect(prompt).toContain 'Test alpha prompt'
      expect(prompt).toContain 'Graph Context: Graph context'
      expect(prompt).toContain 'Previous Alpha: Alpha context'
      expect(prompt).toContain 'Previous Beta: Beta context'
      expect(prompt).toContain 'User: User message'
      expect(prompt).toContain 'Analytical:'

    it 'should handle string context', ->
      prompt = baseLLM.buildPrompt('Message', 'String context')

      expect(prompt).toContain 'Context: String context'

  describe 'makeOllamaRequest', ->
    it 'should make correct request to Ollama', ->
      mockAxios.post.mockResolvedValue(
        createMockOllamaResponse('Response')
      )

      result = await baseLLM.makeOllamaRequest('Test prompt')

      # TODO: Check mockAxios.post.mock.calls[0].arguments(
        'http://localhost:11434/api/generate'
        {
          model: 'test-alpha'
          prompt: 'Test prompt'
          stream: false
          options: {
            temperature: 0.3
            top_p: 0.9
            num_predict: 100
          }
        }
        expect.objectContaining({
          timeout: 1000
        })
      )

      expect(result).toBe 'Response'

    it 'should handle connection errors', ->
      error = new Error('Connection error')
      error.code = 'ECONNREFUSED'
      mockAxios.post.mock.mockImplementation(-> Promise.reject(error))

      await expect(baseLLM.makeOllamaRequest('Test')).rejects.toThrow(
        'Cannot connect to Ollama. Is it running?'
      )

    it 'should handle model not found', ->
      error = new Error('Not found')
      error.response = { status: 404 }
      mockAxios.post.mock.mockImplementation(-> Promise.reject(error))

      await expect(baseLLM.makeOllamaRequest('Test')).rejects.toThrow(
        'Model test-alpha not found. Please pull it first.'
      )

  describe 'parseResponse', ->
    it 'should parse response and extract communications', ->
      # Override extractCommunication for testing
      baseLLM.extractCommunication = mock.fn().mockReturnValue([
        { type: 'test', content: 'Test comm' }
      ])

      result = baseLLM.parseResponse('Full response with COMMUNICATION: test')

      assert.deepEqual result,({
        content: expect.stringContaining('Full response')
        communication: [{ type: 'test', content: 'Test comm' }]
        model: 'test-alpha'
        role: 'analytical'
        timestamp: expect.any(String)
      })

  describe 'graph operations', ->
    it 'should extract and execute graph queries', ->
      mockNeo4j.naturalLanguageQuery.mock.mockImplementation(-> Promise.resolve({ records: [] }))

      parsed = {
        content: 'GRAPH_QUERY: What entities exist?\nSome other content'
      }

      await baseLLM.handleGraphOperations(parsed, 'Original message')

      # TODO: Check mockNeo4j.naturalLanguageQuery.mock.calls[0].arguments(
        'What entities exist?'
      )

    it 'should extract and execute graph stores', ->
      parsed = {
        content: 'GRAPH_STORE: Entity: TestEntity, Type: Person, Confidence: 0.9'
      }

      await baseLLM.handleGraphOperations(parsed, 'Original message')

      # TODO: Check mockNeo4j.addKnowledge.mock.calls[0].arguments(
        [expect.objectContaining({
          name: 'TestEntity'
          type: 'Person'
          confidence: '0.9'
        })]
        []
      )

    it 'should handle concept stores', ->
      parsed = {
        content: 'GRAPH_STORE: Concept: MachineLearning, Domain: Technology'
      }

      await baseLLM.handleGraphOperations(parsed, 'Original message')

      # TODO: Check mockNeo4j.addKnowledge.mock.calls[0].arguments(
        [expect.objectContaining({
          name: 'MachineLearning'
          type: 'concept'
          domain: 'Technology'
        })]
        []
      )

  describe 'healthCheck', ->
    it 'should return healthy status', ->
      mockAxios.post.mockResolvedValue(
        createMockOllamaResponse('OK')
      )

      result = await baseLLM.healthCheck()

      assert.deepEqual result,({
        status: 'healthy'
        model: 'test-alpha'
        response: 'OK'
        timestamp: expect.any(String)
      })

    it 'should return unhealthy status on error', ->
      mockAxios.post.mock.mockImplementation(-> Promise.reject(new Error('Connection failed')))

      result = await baseLLM.healthCheck()

      assert.deepEqual result,({
        status: 'unhealthy'
        model: 'test-alpha'
        error: 'Connection failed'
        timestamp: expect.any(String)
      })

  describe 'getModelInfo', ->
    it 'should return model information', ->
      mockAxios.get.mockResolvedValue({
        data: {
          models: [
            { name: 'test-alpha', size: 1000, digest: 'abc123' }
          ]
        }
      })

      result = await baseLLM.getModelInfo()

      assert.deepEqual result,({
        model: 'test-alpha'
        role: 'analytical'
        personality: 'test-analytical'
        available: true
        details: { name: 'test-alpha', size: 1000, digest: 'abc123' }
        config: {
          temperature: 0.3
          max_tokens: 100
          top_p: 0.9
        }
      })

    it 'should handle missing model', ->
      mockAxios.get.mockResolvedValue({
        data: { models: [] }
      })

      result = await baseLLM.getModelInfo()

      expect(result.available).toBe false
      assert.equal result.details, undefined
}