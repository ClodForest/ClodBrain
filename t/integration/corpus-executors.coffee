# Integration Test: CorpusCallosum + ModeExecutors
{ describe, it, beforeEach, mock } = require 'node:test'
assert = require 'node:assert'

CorpusCallosum = require '../../src/services/corpus-callosum'

describe 'CorpusCallosum + ModeExecutors Integration', ->
  corpus = null
  mockAlpha = null
  mockBeta = null
  config = null

  beforeEach ->
    # Create mock LLMs with realistic behavior
    mockAlpha = {
      processMessage: mock.fn (message, context) ->
        Promise.resolve({
          content: "Alpha analysis: #{message}",
          model: 'alpha',
          timestamp: new Date().toISOString()
        })
    }

    mockBeta = {
      processMessage: mock.fn (message, context) ->
        Promise.resolve({
          content: "Beta creative: #{message}",
          model: 'beta',
          timestamp: new Date().toISOString()
        })
    }

    # Full config for all modes
    config = {
      default_mode: 'parallel'
      timeout: 5000
      modes: {
        parallel: {
          timeout: 5000
        }
        sequential: {
          timeout: 5000,
          default_order: ['alpha', 'beta'],
          handoff_delay: 100
        }
        debate: {
          timeout: 10000,
          max_rounds: 3,
          convergence_threshold: 0.8
        }
        synthesis: {
          timeout: 7000,
          synthesis_model: 'alpha',
          show_individual: true
        }
        handoff: {
          timeout: 5000,
          trigger_phrases: ['need help', 'not sure', 'perhaps']
        }
      }
    }

    corpus = new CorpusCallosum(mockAlpha, mockBeta, config)

  describe 'parallel mode', ->
    it 'should call both LLMs simultaneously', ->
      result = await corpus.orchestrate('test message', 'conv1', 'parallel')

      # Both should be called
      assert.equal mockAlpha.processMessage.mock.calls.length, 1
      assert.equal mockBeta.processMessage.mock.calls.length, 1

      # Check responses
      assert.ok result.alphaResponse
      assert.ok result.betaResponse
      assert.equal result.mode, 'parallel'
      assert.equal result.alphaResponse.content, 'Alpha analysis: test message'
      assert.equal result.betaResponse.content, 'Beta creative: test message'

    it 'should handle one LLM failing', ->
      mockBeta.processMessage = mock.fn -> Promise.reject(new Error('Beta failed'))

      result = await corpus.orchestrate('test', 'conv1', 'parallel')

      # Should still get alpha response
      assert.ok result.alphaResponse
      assert.equal result.betaResponse, null

  describe 'sequential mode', ->
    it 'should process in order with context passing', ->
      result = await corpus.orchestrate('test message', 'conv1', 'sequential')

      # Both called, but in sequence
      assert.equal mockAlpha.processMessage.mock.calls.length, 1
      assert.equal mockBeta.processMessage.mock.calls.length, 1

      # Beta should receive context from alpha
      betaCall = mockBeta.processMessage.mock.calls[0]
      assert.ok betaCall.arguments[0].includes('Context from alpha:')
      assert.ok betaCall.arguments[1]  # Should have context

      # Should record handoff communication
      assert.ok result.communications.length > 0
      handoff = result.communications.find (c) -> c.type == 'handoff'
      assert.ok handoff
      assert.equal handoff.from, 'alpha'
      assert.equal handoff.to, 'beta'

  describe 'debate mode', ->
    it 'should run multiple rounds of debate', ->
      result = await corpus.orchestrate('controversial topic', 'conv1', 'debate')

      # Should have multiple calls (initial + rounds)
      assert.ok mockAlpha.processMessage.mock.calls.length >= 2
      assert.ok mockBeta.processMessage.mock.calls.length >= 1

      # Should have debate communications
      challenges = result.communications.filter (c) -> c.type == 'challenge'
      refinements = result.communications.filter (c) -> c.type == 'refinement'

      assert.ok challenges.length > 0
      assert.ok refinements.length > 0

      # Should have round numbers
      assert.ok result.communications.some (c) -> c.round?

    it 'should converge when responses become similar', ->
      # Make alpha converge quickly
      callCount = 0
      mockAlpha.processMessage = mock.fn ->
        callCount++
        content = if callCount == 1
          "Initial position"
        else
          "Refined position with minor changes"

        Promise.resolve({ content, model: 'alpha' })

      result = await corpus.orchestrate('topic', 'conv1', 'debate')

      # Should not run all rounds if converged
      assert.ok mockAlpha.processMessage.mock.calls.length < config.modes.debate.max_rounds + 1

  describe 'synthesis mode', ->
    it 'should create synthesis from both responses', ->
      result = await corpus.orchestrate('complex question', 'conv1', 'synthesis')

      # Initial parallel calls
      assert.equal mockAlpha.processMessage.mock.calls.length, 2  # initial + synthesis
      assert.equal mockBeta.processMessage.mock.calls.length, 1   # just initial

      # Should have all three responses
      assert.ok result.alphaResponse
      assert.ok result.betaResponse
      assert.ok result.synthesis

      # Synthesis should be created by alpha (per config)
      synthCall = mockAlpha.processMessage.mock.calls[1]
      assert.ok synthCall.arguments[0].includes('Create a unified response')

      # Should record synthesis communication
      synthComm = result.communications.find (c) -> c.type == 'synthesis'
      assert.ok synthComm
      assert.equal synthComm.from, 'both'
      assert.equal synthComm.to, 'synthesis'

  describe 'handoff mode', ->
    it 'should select starting model based on content', ->
      # Analytical content should start with alpha
      result = await corpus.orchestrate('analyze this data', 'conv1', 'handoff')

      firstCall = mockAlpha.processMessage.mock.calls[0]
      assert.equal firstCall.arguments[0], 'analyze this data'
      assert.ok result.primary  # Should indicate primary model

    it 'should handoff when trigger phrase detected', ->
      # Make alpha response include trigger phrase
      mockAlpha.processMessage = mock.fn ->
        Promise.resolve({
          content: "I'm not sure about this aspect",
          model: 'alpha'
        })

      result = await corpus.orchestrate('question', 'conv1', 'handoff')

      # Both should be called
      assert.equal mockAlpha.processMessage.mock.calls.length, 1
      assert.equal mockBeta.processMessage.mock.calls.length, 1

      # Should have handoff communication
      handoff = result.communications.find (c) -> c.type == 'handoff'
      assert.ok handoff
      assert.equal handoff.from, 'alpha'
      assert.equal handoff.to, 'beta'

  describe 'communication tracking', ->
    it 'should track all communications with process IDs', ->
      result = await corpus.orchestrate('test', 'conv1', 'sequential')

      # All communications should have timestamps
      for comm in result.communications
        assert.ok comm.timestamp

      # Corpus should track in history
      assert.ok corpus.communicationHistory.length > 0

      # History items should have process IDs
      for histItem in corpus.communicationHistory
        assert.ok histItem.processId
        assert.ok histItem.processId.startsWith('proc_')

  describe 'error handling', ->
    it 'should handle executor errors gracefully', ->
      mockAlpha.processMessage = mock.fn -> Promise.reject(new Error('Alpha error'))
      mockBeta.processMessage = mock.fn -> Promise.reject(new Error('Beta error'))

      # Parallel mode should handle both failing
      result = await corpus.orchestrate('test', 'conv1', 'parallel')

      assert.equal result.alphaResponse, null
      assert.equal result.betaResponse, null
      assert.equal result.mode, 'parallel'

    it 'should clean up process on error', ->
      corpus.executors.debate.execute = mock.fn ->
        Promise.reject(new Error('Debate failed'))

      try
        await corpus.orchestrate('test', 'conv1', 'debate')
        assert.fail('Should have thrown')
      catch error
        assert.equal error.message, 'Debate failed'

      # Process should be cleaned up
      assert.equal corpus.activeProcesses.size, 0

  describe 'mode switching', ->
    it 'should switch modes without affecting executors', ->
      # Use different modes in sequence
      result1 = await corpus.orchestrate('test 1', 'conv1', 'parallel')
      result2 = await corpus.orchestrate('test 2', 'conv2', 'sequential')
      result3 = await corpus.orchestrate('test 3', 'conv3', 'synthesis')

      assert.equal result1.mode, 'parallel'
      assert.equal result2.mode, 'sequential'
      assert.equal result3.mode, 'synthesis'

      # Default mode should not change
      assert.equal corpus.currentMode, 'parallel'