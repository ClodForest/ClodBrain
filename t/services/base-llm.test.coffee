# BaseLLM Tests (ESM)
import { describe, it, expect, beforeEach, vi } from 'vitest'
import BaseLLM from '../../src/services/base-llm.js'
import {
  createMockOllamaResponse,
  createMockNeo4jTool,
  createMockAxios,
  createTestConfig,
  createTestOllamaConfig
} from '../setup.js'

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
    vi.mock 'axios', -> mockAxios

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

      expect(mockAxios.post).toHaveBeenCalledWith(
        'http://localhost:11434/api/generate'
        expect.objectContaining({
          model: 'test-alpha'
          prompt: expect.stringContaining('Hello')
          stream: false
        })
        expect.any(Object)
      )

      expect(result).toMatchObject({
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

      expect(mockNeo4j.naturalLanguageQuery).toHaveBeenCalledWith('conversations')
      expect(mockAxios.post).toHaveBeenCalledWith(
        expect.any(String)
        expect.objectContaining({
          prompt: expect.stringContaining('Recent conversations: 2 found')
        })
        expect.any(Object)
      )

    it 'should handle errors gracefully', ->
      mockAxios.post.mockRejectedValue(new Error('Connection failed'))

      await expect(baseLLM.processMessage('Hello')).rejects.toThrow(
        'BaseLLM processing failed: Connection failed'
      )

  # ... rest of the tests remain the same, just with ESM imports