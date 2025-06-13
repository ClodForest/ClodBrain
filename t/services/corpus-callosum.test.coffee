# Corpus Callosum Tests
{ describe, it, beforeEach, mock } = require 'node:test'
assert = require 'node:assert'
{ createTestConfig, isProcessId } = require '../setup'

# Create mock executors
createMockExecutor = (name) ->
  {
    execute: mock.fn().mockResolvedValue({
      alphaResponse: { content: "#{name} alpha response" }
      betaResponse: { content: "#{name} beta response" }
    })
  }

# Mock the mode-executors module
mock.module '../../src/services/mode-executors', ->
  {
    ParallelExecutor: class
      constructor: -> createMockExecutor('parallel')
    SequentialExecutor: class
      constructor: -> createMockExecutor('sequential')
    DebateExecutor: class
      constructor: -> createMockExecutor('debate')
    SynthesisExecutor: class
      constructor: -> createMockExecutor('synthesis')
    HandoffExecutor: class
      constructor: -> createMockExecutor('handoff')
  }

describe 'CorpusCallosum', ->
  mockAlpha = null
  mockBeta = null
  config = null
  corpus = null

  beforeEach ->
    mockAlpha = { processMessage: mock.fn() }
    mockBeta = { processMessage: mock.fn() }
    config = createTestConfig().corpus_callosum
    corpus = new CorpusCallosum(mockAlpha, mockBeta, config)

  describe 'constructor', ->
    it 'should initialize with default mode', ->
      assert.equal corpus.currentMode, 'parallel'
      expect(corpus.activeProcesses).toBeInstanceOf(Map)
      expect(corpus.patterns).toBeInstanceOf(Map)

    it 'should initialize all executors', ->
      expect(corpus.executors).toHaveProperty('parallel')
      expect(corpus.executors).toHaveProperty('sequential')
      expect(corpus.executors).toHaveProperty('debate')
      expect(corpus.executors).toHaveProperty('synthesis')
      expect(corpus.executors).toHaveProperty('handoff')

  describe 'orchestrate', ->
    it 'should execute in parallel mode by default', ->
      result = await corpus.orchestrate('Test message', 'conv123')

      # TODO: Check corpus.executors.parallel.execute.mock.calls[0].arguments(
        'Test message'
        expect.any(String)
        expect.any(Function)
        {}
      )

      assert.deepEqual result,({
        alphaResponse: { content: 'parallel alpha response' }
        betaResponse: { content: 'parallel beta response' }
        mode: 'parallel'
        timestamp: expect.any(String)
      })

    it 'should use specified mode', ->
      result = await corpus.orchestrate('Test message', 'conv123', 'debate')

      assert.ok corpus.executors.debate.execute.mock.calls.length > 0
      assert.equal result.mode, 'debate'

    it 'should throw error for unknown mode', ->
      await expect(
        corpus.orchestrate('Test', 'conv123', 'unknown')
      ).rejects.toThrow('Unknown mode: unknown')

    it 'should track active processes', ->
      # Start orchestration
      promise = corpus.orchestrate('Test', 'conv123')

      # Should have one active process
      assert.equal corpus.activeProcesses.size, 1

      # Wait for completion
      await promise

      # Should be cleaned up
      assert.equal corpus.activeProcesses.size, 0

    it 'should record communications', ->
      # Make executor call recordComm
      corpus.executors.parallel.execute.mock.mockImplementation(
        (msg, procId, recordComm) ->
          recordComm({ from: 'alpha', to: 'beta', message: 'test' })
          return { alphaResponse: {}, betaResponse: {} }
      )

      result = await corpus.orchestrate('Test', 'conv123')

      expect(result.communications).toHaveLength(1)
      assert.deepEqual result.communications[0],({
        from: 'alpha'
        to: 'beta'
        message: 'test'
        timestamp: expect.any(Number)
      })

    it 'should store patterns for learning', ->
      await corpus.orchestrate('How does this work?', 'conv123')

      # Should have stored a pattern
      expect(corpus.patterns.size).toBeGreaterThan(0)

      # Check pattern structure
      patterns = Array.from(corpus.patterns.values())[0]
      assert.deepEqual patterns[0],({
        mode: 'parallel'
        messageType: 'question'
        success: true
        timestamp: expect.any(Number)
      })

  describe 'message classification', ->
    it 'should classify question messages', ->
      expect(corpus.classifyMessage('What is this?')).toBe('question')
      expect(corpus.classifyMessage('How does it work?')).toBe('question')
      expect(corpus.classifyMessage('Why is that?')).toBe('question')

    it 'should classify creation messages', ->
      expect(corpus.classifyMessage('Create a new design')).toBe('creation')
      expect(corpus.classifyMessage('Build something')).toBe('creation')
      expect(corpus.classifyMessage('Generate ideas')).toBe('creation')

    it 'should classify analysis messages', ->
      expect(corpus.classifyMessage('Analyze this data')).toBe('analysis')
      expect(corpus.classifyMessage('Evaluate the options')).toBe('analysis')
      expect(corpus.classifyMessage('Review the results')).toBe('analysis')

    it 'should classify assistance messages', ->
      expect(corpus.classifyMessage('Help me understand')).toBe('assistance')
      expect(corpus.classifyMessage('Assist with this')).toBe('assistance')
      expect(corpus.classifyMessage('Guide me through')).toBe('assistance')

    it 'should default to general', ->
      expect(corpus.classifyMessage('Hello there')).toBe('general')
      expect(corpus.classifyMessage('Thanks')).toBe('general')

  describe 'mode management', ->
    it 'should change mode', ->
      corpus.setMode('synthesis', { custom: 'param' })

      assert.equal corpus.currentMode, 'synthesis'
      assert.deepEqual corpus.modeParameters, { custom: 'param' }

    it 'should reject invalid mode', ->
      expect(->
        corpus.setMode('invalid')
      ).toThrow('Invalid mode: invalid')

  describe 'communication tracking', ->
    it 'should record communication with process', ->
      processId = corpus.generateProcessId()
      process = corpus.createProcess(processId, 'parallel', 'Test', 'conv123')
      corpus.activeProcesses.set(processId, process)

      corpus.recordCommunication(processId, {
        from: 'alpha'
        to: 'beta'
        message: 'Test communication'
      })

      expect(process.communications).toHaveLength(1)
      expect(corpus.communicationHistory).toHaveLength(1)
      assert.deepEqual corpus.communicationHistory[0],({
        processId: processId
        from: 'alpha'
        to: 'beta'
        message: 'Test communication'
        timestamp: expect.any(Number)
      })

    it 'should handle missing process gracefully', ->
      corpus.recordCommunication('invalid-id', { message: 'test' })

      # Should not throw, just ignore
      expect(corpus.communicationHistory).toHaveLength(0)

  describe 'pattern storage', ->
    it 'should limit pattern history', ->
      # Store many patterns
      for i in [1..150]
        corpus.storePattern('parallel', "Message #{i}", { success: true })

      # Should only keep last 100
      patterns = corpus.patterns.get('parallel_general')
      assert.equal patterns.length, 100

  describe 'utilities', ->
    it 'should generate valid process IDs', ->
      id1 = corpus.generateProcessId()
      id2 = corpus.generateProcessId()

      expect(isProcessId(id1)).toBe(true)
      expect(isProcessId(id2)).toBe(true)
      expect(id1).not.toBe(id2)

    it 'should interrupt active processes', ->
      # Create some active processes
      corpus.activeProcesses.set('proc1', {})
      corpus.activeProcesses.set('proc2', {})

      corpus.interrupt()

      assert.equal corpus.activeProcesses.size, 0

    it 'should return statistics', ->
      # Set up some state
      corpus.currentMode = 'debate'
      corpus.activeProcesses.set('proc1', {})
      corpus.communicationHistory.push({}, {}, {})
      corpus.patterns.set('parallel_question', [{}, {}])

      stats = corpus.getStats()

      assert.deepEqual stats,({
        currentMode: 'debate'
        activeProcesses: 1
        totalCommunications: 3
        patterns: expect.any(Object)
        availableModes: ['parallel', 'sequential', 'debate', 'synthesis', 'handoff']
      })

  describe 'process management', ->
    it 'should create process with correct structure', ->
      process = corpus.createProcess('proc123', 'synthesis', 'Test msg', 'conv456')

      assert.deepEqual process,({
        id: 'proc123'
        mode: 'synthesis'
        startTime: expect.any(Number)
        userMessage: 'Test msg'
        conversationId: 'conv456'
        communications: []
      })

    it 'should finalize result correctly', ->
      corpus.activeProcesses.set('proc123', {
        communications: [
          { from: 'alpha', to: 'beta', message: 'comm1' }
          { from: 'beta', to: 'alpha', message: 'comm2' }
        ]
      })

      baseResult = { alphaResponse: 'alpha', betaResponse: 'beta' }
      finalized = corpus.finalizeResult(baseResult, 'debate', 'proc123')

      assert.deepEqual finalized,({
        alphaResponse: 'alpha'
        betaResponse: 'beta'
        mode: 'debate'
        communications: expect.arrayContaining([
          expect.objectContaining({ message: 'comm1' })
          expect.objectContaining({ message: 'comm2' })
        ])
        timestamp: expect.any(String)
      })

  describe 'error handling', ->
    it 'should clean up process on executor error', ->
      corpus.executors.parallel.execute.mockRejectedValue(
        new Error('Executor failed')
      )

      # Start orchestration
      promise = corpus.orchestrate('Test', 'conv123')

      # Should have active process
      assert.equal corpus.activeProcesses.size, 1

      # Wait for error
      await expect(promise).rejects.toThrow('Executor failed')

      # Should still clean up
      assert.equal corpus.activeProcesses.size, 0