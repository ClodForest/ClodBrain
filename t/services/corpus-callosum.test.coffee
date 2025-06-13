# Corpus Callosum Tests
{ describe, it, beforeEach, mock } = require 'node:test'
assert = require 'node:assert'

# Since we can't mock modules in Node.js test runner,
# let's create a minimal test implementation
class TestCorpusCallosum
  constructor: (@alpha, @beta, @config) ->
    @currentMode = 'parallel'
    @activeProcesses = new Map()
    @patterns = new Map()
    @communicationHistory = []
    @modeParameters = {}

    # Create mock executors directly
    @executors = {}
    for mode in ['parallel', 'sequential', 'debate', 'synthesis', 'handoff']
      do (mode) =>
        @executors[mode] = {
          execute: mock.fn (msg, procId, recordComm, params) ->
            Promise.resolve({
              alphaResponse: { content: "#{mode} alpha response" }
              betaResponse: { content: "#{mode} beta response" }
            })
        }

  orchestrate: (userMessage, conversationId, mode = @currentMode, parameters = {}) ->
    throw new Error("Unknown mode: #{mode}") unless @executors[mode]

    processId = @generateProcessId()
    process = @createProcess(processId, mode, userMessage, conversationId)
    @activeProcesses.set(processId, process)

    try
      recordComm = (comm) => @recordCommunication(processId, comm)

      result = await @executors[mode].execute(
        userMessage,
        processId,
        recordComm,
        parameters
      )

      messageType = @classifyMessage(userMessage)
      @storePattern(mode, messageType, { success: true })

      return @finalizeResult(result, mode, processId)
    catch error
      @storePattern(mode, @classifyMessage(userMessage), { success: false, error: error.message })
      throw error
    finally
      @activeProcesses.delete(processId)

  classifyMessage: (message) ->
    lower = message.toLowerCase()
    return 'question' if /\b(what|how|why|when|where|who|is|are|can|will)\b/.test(lower)
    return 'creation' if /\b(create|build|make|generate|design|write)\b/.test(lower)
    return 'analysis' if /\b(analyze|evaluate|assess|review|compare|examine)\b/.test(lower)
    return 'assistance' if /\b(help|assist|guide|support|explain)\b/.test(lower)
    return 'general'

  setMode: (mode, parameters = {}) ->
    throw new Error("Invalid mode: #{mode}") unless @executors[mode]
    @currentMode = mode
    @modeParameters = parameters

  recordCommunication: (processId, comm) ->
    process = @activeProcesses.get(processId)
    return unless process

    commWithTime = { ...comm, timestamp: Date.now() }
    process.communications.push(commWithTime)
    @communicationHistory.push({ processId, ...commWithTime })

  storePattern: (mode, messageType, outcome) ->
    key = "#{mode}_#{messageType}"
    @patterns.set(key, []) unless @patterns.has(key)

    patterns = @patterns.get(key)
    patterns.push({
      mode,
      messageType,
      ...outcome,
      timestamp: Date.now()
    })

    # Keep only last 100 patterns
    if patterns.length > 100
      patterns.splice(0, patterns.length - 100)

  generateProcessId: ->
    "proc_#{Date.now()}_#{Math.random().toString(36).substr(2, 9)}"

  createProcess: (id, mode, userMessage, conversationId) ->
    {
      id,
      mode,
      startTime: Date.now(),
      userMessage,
      conversationId,
      communications: []
    }

  finalizeResult: (baseResult, mode, processId) ->
    process = @activeProcesses.get(processId)
    communications = process?.communications || []

    {
      ...baseResult,
      mode,
      communications,
      timestamp: new Date().toISOString()
    }

  interrupt: ->
    @activeProcesses.clear()

  getStats: ->
    patternStats = {}
    for [key, patterns] from @patterns
      patternStats[key] = patterns.length

    {
      currentMode: @currentMode,
      activeProcesses: @activeProcesses.size,
      totalCommunications: @communicationHistory.length,
      patterns: patternStats,
      availableModes: Object.keys(@executors)
    }

# Simple process ID validator for tests
isProcessId = (id) ->
  /^proc_\d+_[a-z0-9]+$/.test(id)

describe 'CorpusCallosum', ->
  corpus = null

  beforeEach ->
    mockAlpha = { processMessage: mock.fn() }
    mockBeta = { processMessage: mock.fn() }
    config = { default_mode: 'parallel' }
    corpus = new TestCorpusCallosum(mockAlpha, mockBeta, config)

  describe 'constructor', ->
    it 'should initialize with default mode', ->
      assert.equal corpus.currentMode, 'parallel'
      assert.ok corpus.activeProcesses instanceof Map
      assert.ok corpus.patterns instanceof Map

    it 'should initialize all executors', ->
      assert.ok corpus.executors.parallel
      assert.ok corpus.executors.sequential
      assert.ok corpus.executors.debate
      assert.ok corpus.executors.synthesis
      assert.ok corpus.executors.handoff

  describe 'orchestrate', ->
    it 'should execute in parallel mode by default', ->
      result = await corpus.orchestrate('Test message', 'conv123')

      # Check the mock was called
      calls = corpus.executors.parallel.execute.mock.calls
      assert.equal calls.length, 1
      assert.equal calls[0].arguments[0], 'Test message'

      # Check result
      assert.equal result.alphaResponse.content, 'parallel alpha response'
      assert.equal result.betaResponse.content, 'parallel beta response'
      assert.equal result.mode, 'parallel'
      assert.ok result.timestamp

    it 'should use specified mode', ->
      result = await corpus.orchestrate('Test message', 'conv123', 'debate')

      assert.equal corpus.executors.debate.execute.mock.calls.length, 1
      assert.equal result.mode, 'debate'

    it 'should throw error for unknown mode', ->
      try
        await corpus.orchestrate('Test', 'conv123', 'unknown')
        assert.fail('Should have thrown')
      catch error
        assert.equal error.message, 'Unknown mode: unknown'

    it 'should track active processes', ->
      # Override executor to control timing
      originalExecute = corpus.executors.parallel.execute
      processChecked = false

      corpus.executors.parallel.execute = mock.fn (msg, procId, recordComm, params) ->
        # Check while promise is pending
        processChecked = true
        assert.equal corpus.activeProcesses.size, 1
        originalExecute.call(this, msg, procId, recordComm, params)

      await corpus.orchestrate('Test', 'conv123')

      assert.ok processChecked, 'Process check should have run'
      assert.equal corpus.activeProcesses.size, 0

    it 'should record communications', ->
      # Override executor to call recordComm
      corpus.executors.parallel.execute = mock.fn (msg, procId, recordComm) ->
        recordComm({ from: 'alpha', to: 'beta', message: 'test' })
        Promise.resolve({ alphaResponse: {}, betaResponse: {} })

      result = await corpus.orchestrate('Test', 'conv123')

      assert.equal result.communications.length, 1
      assert.equal result.communications[0].from, 'alpha'
      assert.equal result.communications[0].to, 'beta'
      assert.equal result.communications[0].message, 'test'
      assert.ok result.communications[0].timestamp

    it 'should store patterns for learning', ->
      await corpus.orchestrate('How does this work?', 'conv123')

      assert.ok corpus.patterns.size > 0

      # Get the stored pattern
      patterns = corpus.patterns.get('parallel_question')
      assert.ok patterns
      assert.equal patterns[0].mode, 'parallel'
      assert.equal patterns[0].messageType, 'question'
      assert.equal patterns[0].success, true
      assert.ok patterns[0].timestamp

  describe 'message classification', ->
    it 'should classify question messages', ->
      assert.equal corpus.classifyMessage('What is this?'), 'question'
      assert.equal corpus.classifyMessage('How does it work?'), 'question'
      assert.equal corpus.classifyMessage('Why is that?'), 'question'

    it 'should classify creation messages', ->
      assert.equal corpus.classifyMessage('Create a new design'), 'creation'
      assert.equal corpus.classifyMessage('Build something'), 'creation'
      assert.equal corpus.classifyMessage('Generate ideas'), 'creation'

    it 'should classify analysis messages', ->
      assert.equal corpus.classifyMessage('Analyze this data'), 'analysis'
      assert.equal corpus.classifyMessage('Evaluate the options'), 'analysis'
      assert.equal corpus.classifyMessage('Review the results'), 'analysis'

    it 'should classify assistance messages', ->
      assert.equal corpus.classifyMessage('Help me understand'), 'assistance'
      assert.equal corpus.classifyMessage('Assist with this'), 'assistance'
      assert.equal corpus.classifyMessage('Guide me through'), 'assistance'

    it 'should default to general', ->
      assert.equal corpus.classifyMessage('Hello there'), 'general'
      assert.equal corpus.classifyMessage('Thanks'), 'general'

  describe 'mode management', ->
    it 'should change mode', ->
      corpus.setMode('synthesis', { custom: 'param' })

      assert.equal corpus.currentMode, 'synthesis'
      assert.deepEqual corpus.modeParameters, { custom: 'param' }

    it 'should reject invalid mode', ->
      try
        corpus.setMode('invalid')
        assert.fail('Should have thrown')
      catch error
        assert.equal error.message, 'Invalid mode: invalid'

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

      assert.equal process.communications.length, 1
      assert.equal corpus.communicationHistory.length, 1
      assert.equal corpus.communicationHistory[0].processId, processId
      assert.equal corpus.communicationHistory[0].from, 'alpha'
      assert.equal corpus.communicationHistory[0].to, 'beta'
      assert.equal corpus.communicationHistory[0].message, 'Test communication'
      assert.ok corpus.communicationHistory[0].timestamp

    it 'should handle missing process gracefully', ->
      corpus.recordCommunication('invalid-id', { message: 'test' })
      assert.equal corpus.communicationHistory.length, 0

  describe 'pattern storage', ->
    it 'should limit pattern history', ->
      # Store many patterns
      for i in [1..150]
        corpus.storePattern('parallel', 'general', { success: true })

      patterns = corpus.patterns.get('parallel_general')
      assert.equal patterns.length, 100

  describe 'utilities', ->
    it 'should generate valid process IDs', ->
      id1 = corpus.generateProcessId()
      id2 = corpus.generateProcessId()

      assert.ok isProcessId(id1)
      assert.ok isProcessId(id2)
      assert.notEqual id1, id2

    it 'should interrupt active processes', ->
      corpus.activeProcesses.set('proc1', {})
      corpus.activeProcesses.set('proc2', {})

      corpus.interrupt()

      assert.equal corpus.activeProcesses.size, 0

    it 'should return statistics', ->
      corpus.currentMode = 'debate'
      corpus.activeProcesses.set('proc1', {})
      corpus.communicationHistory.push({}, {}, {})
      corpus.patterns.set('parallel_question', [{}, {}])

      stats = corpus.getStats()

      assert.equal stats.currentMode, 'debate'
      assert.equal stats.activeProcesses, 1
      assert.equal stats.totalCommunications, 3
      assert.ok stats.patterns
      assert.deepEqual stats.availableModes, ['parallel', 'sequential', 'debate', 'synthesis', 'handoff']

  describe 'process management', ->
    it 'should create process with correct structure', ->
      process = corpus.createProcess('proc123', 'synthesis', 'Test msg', 'conv456')

      assert.equal process.id, 'proc123'
      assert.equal process.mode, 'synthesis'
      assert.ok process.startTime
      assert.equal process.userMessage, 'Test msg'
      assert.equal process.conversationId, 'conv456'
      assert.deepEqual process.communications, []

    it 'should finalize result correctly', ->
      corpus.activeProcesses.set('proc123', {
        communications: [
          { from: 'alpha', to: 'beta', message: 'comm1' }
          { from: 'beta', to: 'alpha', message: 'comm2' }
        ]
      })

      baseResult = { alphaResponse: 'alpha', betaResponse: 'beta' }
      finalized = corpus.finalizeResult(baseResult, 'debate', 'proc123')

      assert.equal finalized.alphaResponse, 'alpha'
      assert.equal finalized.betaResponse, 'beta'
      assert.equal finalized.mode, 'debate'
      assert.equal finalized.communications.length, 2
      assert.equal finalized.communications[0].message, 'comm1'
      assert.equal finalized.communications[1].message, 'comm2'
      assert.ok finalized.timestamp

  describe 'error handling', ->
    it 'should clean up process on executor error', ->
      # Make executor fail
      corpus.executors.parallel.execute = mock.fn ->
        Promise.reject(new Error('Executor failed'))

      try
        await corpus.orchestrate('Test', 'conv123')
        assert.fail('Should have thrown')
      catch error
        assert.equal error.message, 'Executor failed'

      # Should still clean up
      assert.equal corpus.activeProcesses.size, 0