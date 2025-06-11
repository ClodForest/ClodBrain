# Corpus Callosum - Inter-LLM Communication Service
class CorpusCallosum
  constructor: (@alpha, @beta, @config) ->
    @currentMode = @config.default_mode
    @communicationHistory = []
    @activeProcesses = new Map()
    @patterns = new Map()  # Learn communication patterns over time
    
    # Communication modes
    @MODES =
      PARALLEL: 'parallel'
      SEQUENTIAL: 'sequential'
      DEBATE: 'debate'
      SYNTHESIS: 'synthesis'
      HANDOFF: 'handoff'

  setMode: (mode, parameters = {}) ->
    unless mode in Object.values(@MODES)
      throw new Error "Invalid mode: #{mode}"
    
    @currentMode = mode
    @modeParameters = parameters
    console.log "Corpus Callosum mode changed to: #{mode}"

  orchestrate: (userMessage, conversationId, mode = null) ->
    activeMode = mode || @currentMode
    processId = @generateProcessId()
    
    @activeProcesses.set processId, {
      mode: activeMode
      startTime: Date.now()
      userMessage: userMessage
      conversationId: conversationId
      communications: []
    }
    
    try
      result = switch activeMode
        when @MODES.PARALLEL
          await @runParallel(userMessage, processId)
        when @MODES.SEQUENTIAL
          await @runSequential(userMessage, processId)
        when @MODES.DEBATE
          await @runDebate(userMessage, processId)
        when @MODES.SYNTHESIS
          await @runSynthesis(userMessage, processId)
        when @MODES.HANDOFF
          await @runHandoff(userMessage, processId)
        else
          throw new Error "Unknown mode: #{activeMode}"
      
      # Store successful communication pattern
      @storePattern(activeMode, userMessage, result)
      
      return result
      
    finally
      @activeProcesses.delete processId

  runParallel: (message, processId) ->
    console.log "Running parallel mode for: #{message}"
    
    # Both models process simultaneously
    [alphaPromise, betaPromise] = [
      @alpha.processMessage(message, null)
      @beta.processMessage(message, null)
    ]
    
    # Wait for both with timeout
    try
      results = await Promise.allSettled([
        @withTimeout(alphaPromise, @config.communication_timeout)
        @withTimeout(betaPromise, @config.communication_timeout)
      ])
      
      alphaResponse = if results[0].status is 'fulfilled' then results[0].value else null
      betaResponse = if results[1].status is 'fulfilled' then results[1].value else null
      
      # Log any failures
      if results[0].status is 'rejected'
        console.error 'Alpha failed:', results[0].reason
      if results[1].status is 'rejected'
        console.error 'Beta failed:', results[1].reason
      
      return {
        mode: 'parallel'
        alphaResponse: alphaResponse
        betaResponse: betaResponse
        communications: @getProcessCommunications(processId)
        timestamp: new Date().toISOString()
      }
      
    catch error
      console.error 'Parallel processing error:', error
      throw error

  runSequential: (message, processId) ->
    console.log "Running sequential mode for: #{message}"
    
    order = @modeParameters?.order || @config.modes.sequential.default_order
    
    firstModel = if order[0] is 'alpha' then @alpha else @beta
    secondModel = if order[0] is 'alpha' then @beta else @alpha
    
    # First model processes
    firstResponse = await firstModel.processMessage(message, null)
    
    # Add handoff delay
    await @delay(@config.modes.sequential.handoff_delay)
    
    # Second model processes with context from first
    contextMessage = "#{message}\n\nContext from #{order[0]}: #{firstResponse}"
    secondResponse = await secondModel.processMessage(contextMessage, firstResponse)
    
    @recordCommunication(processId, {
      from: order[0]
      to: order[1]
      message: firstResponse
      type: 'handoff'
    })
    
    return {
      mode: 'sequential'
      alphaResponse: if order[0] is 'alpha' then firstResponse else secondResponse
      betaResponse: if order[0] is 'beta' then firstResponse else secondResponse
      communications: @getProcessCommunications(processId)
      timestamp: new Date().toISOString()
    }

  runDebate: (message, processId) ->
    console.log "Running debate mode for: #{message}"
    
    maxRounds = @config.modes.debate.max_rounds
    alphaResponse = await @alpha.processMessage(message, null)
    
    for round in [1..maxRounds]
      # Beta challenges Alpha's response
      challengePrompt = """
      Original question: #{message}
      Alpha's response: #{alphaResponse}
      
      Provide a creative challenge or alternative perspective to Alpha's response.
      Focus on what might be missing, alternative approaches, or creative insights.
      """
      
      betaChallenge = await @beta.processMessage(challengePrompt, alphaResponse)
      
      @recordCommunication(processId, {
        from: 'beta'
        to: 'alpha'
        message: betaChallenge
        type: 'challenge'
        round: round
      })
      
      # Alpha refines based on Beta's challenge
      refinePrompt = """
      Original question: #{message}
      Your previous response: #{alphaResponse}
      Beta's challenge: #{betaChallenge}
      
      Refine your response considering Beta's creative perspective.
      Integrate valid points while maintaining analytical rigor.
      """
      
      refinedResponse = await @alpha.processMessage(refinePrompt, betaChallenge)
      
      @recordCommunication(processId, {
        from: 'alpha'
        to: 'beta'
        message: refinedResponse
        type: 'refinement'
        round: round
      })
      
      # Check for convergence
      if @calculateSimilarity(alphaResponse, refinedResponse) > @config.modes.debate.convergence_threshold
        console.log "Debate converged after #{round} rounds"
        break
        
      alphaResponse = refinedResponse
    
    return {
      mode: 'debate'
      alphaResponse: alphaResponse
      betaResponse: betaChallenge
      communications: @getProcessCommunications(processId)
      rounds: round
      timestamp: new Date().toISOString()
    }

  runSynthesis: (message, processId) ->
    console.log "Running synthesis mode for: #{message}"
    
    # Get both responses
    [alphaResponse, betaResponse] = await Promise.all([
      @alpha.processMessage(message, null)
      @beta.processMessage(message, null)
    ])
    
    # Determine which model handles synthesis
    synthesisModel = if @config.modes.synthesis.synthesis_model is 'alpha' then @alpha else @beta
    
    synthesisPrompt = """
    Original question: #{message}
    
    Alpha's analytical response: #{alphaResponse}
    Beta's creative response: #{betaResponse}
    
    Create a unified response that synthesizes both perspectives.
    Combine the logical rigor of Alpha with the creative insights of Beta.
    The result should be more complete than either individual response.
    """
    
    synthesis = await synthesisModel.processMessage(synthesisPrompt, {
      alpha: alphaResponse
      beta: betaResponse
    })
    
    @recordCommunication(processId, {
      from: 'both'
      to: 'synthesis'
      message: synthesis
      type: 'synthesis'
      inputs: { alpha: alphaResponse, beta: betaResponse }
    })
    
    return {
      mode: 'synthesis'
      alphaResponse: unless @config.modes.synthesis.show_individual then null else alphaResponse
      betaResponse: unless @config.modes.synthesis.show_individual then null else betaResponse
      synthesis: synthesis
      communications: @getProcessCommunications(processId)
      timestamp: new Date().toISOString()
    }

  runHandoff: (message, processId) ->
    console.log "Running handoff mode for: #{message}"
    
    # Determine which model should start based on message content
    startsWithAlpha = @shouldStartWithAlpha(message)
    
    if startsWithAlpha
      alphaResponse = await @alpha.processMessage(message, null)
      
      # Check if Alpha wants to hand off to Beta
      if @detectHandoffTrigger(alphaResponse)
        handoffPrompt = "#{message}\n\nAlpha's initial analysis: #{alphaResponse}\n\nPlease continue with a creative perspective."
        betaResponse = await @beta.processMessage(handoffPrompt, alphaResponse)
        
        @recordCommunication(processId, {
          from: 'alpha'
          to: 'beta'
          message: 'Handing off for creative input'
          type: 'handoff'
        })
        
        return {
          mode: 'handoff'
          alphaResponse: alphaResponse
          betaResponse: betaResponse
          primary: 'beta'  # Beta took over
          communications: @getProcessCommunications(processId)
          timestamp: new Date().toISOString()
        }
      else
        return {
          mode: 'handoff'
          alphaResponse: alphaResponse
          betaResponse: null
          primary: 'alpha'  # Alpha handled it
          communications: @getProcessCommunications(processId)
          timestamp: new Date().toISOString()
        }
    else
      betaResponse = await @beta.processMessage(message, null)
      
      if @detectHandoffTrigger(betaResponse)
        handoffPrompt = "#{message}\n\nBeta's creative perspective: #{betaResponse}\n\nPlease provide analytical verification and structure."
        alphaResponse = await @alpha.processMessage(handoffPrompt, betaResponse)
        
        @recordCommunication(processId, {
          from: 'beta'
          to: 'alpha'
          message: 'Handing off for analytical verification'
          type: 'handoff'
        })
        
        return {
          mode: 'handoff'
          alphaResponse: alphaResponse
          betaResponse: betaResponse
          primary: 'alpha'  # Alpha took over
          communications: @getProcessCommunications(processId)
          timestamp: new Date().toISOString()
        }
      else
        return {
          mode: 'handoff'
          alphaResponse: null
          betaResponse: betaResponse
          primary: 'beta'  # Beta handled it
          communications: @getProcessCommunications(processId)
          timestamp: new Date().toISOString()
        }

  # Utility methods
  generateProcessId: ->
    "proc_#{Date.now()}_#{Math.random().toString(36).substr(2, 9)}"

  recordCommunication: (processId, communication) ->
    process = @activeProcesses.get(processId)
    if process
      communication.timestamp = Date.now()
      process.communications.push communication
      @communicationHistory.push {
        processId: processId
        ...communication
      }

  getProcessCommunications: (processId) ->
    process = @activeProcesses.get(processId)
    if process then process.communications else []

  shouldStartWithAlpha: (message) ->
    # Heuristics to determine which model should start
    analyticalKeywords = ['analyze', 'calculate', 'verify', 'facts', 'data', 'logical', 'step', 'method']
    creativeKeywords = ['create', 'imagine', 'design', 'alternative', 'innovative', 'brainstorm', 'idea']
    
    lowerMessage = message.toLowerCase()
    analyticalScore = analyticalKeywords.filter((word) -> lowerMessage.includes(word)).length
    creativeScore = creativeKeywords.filter((word) -> lowerMessage.includes(word)).length
    
    return analyticalScore >= creativeScore

  detectHandoffTrigger: (response) ->
    triggerPhrases = @config.modes.handoff.trigger_phrases
    lowerResponse = response.toLowerCase()
    return triggerPhrases.some((phrase) -> lowerResponse.includes(phrase.toLowerCase()))

  calculateSimilarity: (text1, text2) ->
    # Simple similarity calculation - in production, use proper NLP
    words1 = text1.toLowerCase().split(/\s+/)
    words2 = text2.toLowerCase().split(/\s+/)
    
    commonWords = words1.filter((word) -> words2.includes(word))
    totalWords = Math.max(words1.length, words2.length)
    
    return if totalWords > 0 then commonWords.length / totalWords else 0

  storePattern: (mode, message, result) ->
    pattern = {
      mode: mode
      messageType: @classifyMessage(message)
      success: result?
      timestamp: Date.now()
    }
    
    key = "#{pattern.mode}_#{pattern.messageType}"
    if not @patterns.has(key)
      @patterns.set(key, [])
    
    @patterns.get(key).push(pattern)
    
    # Keep only last 100 patterns per type
    patterns = @patterns.get(key)
    if patterns.length > 100
      @patterns.set(key, patterns.slice(-100))

  classifyMessage: (message) ->
    # Simple message classification
    lowerMessage = message.toLowerCase()
    
    if /\b(how|what|why|when|where|who)\b/.test(lowerMessage)
      return 'question'
    else if /\b(create|make|design|build|generate)\b/.test(lowerMessage)
      return 'creation'
    else if /\b(analyze|examine|evaluate|assess|review)\b/.test(lowerMessage)
      return 'analysis'
    else if /\b(help|assist|support|guide)\b/.test(lowerMessage)
      return 'assistance'
    else
      return 'general'

  withTimeout: (promise, timeoutMs) ->
    return Promise.race([
      promise
      new Promise((_, reject) ->
        setTimeout((-> reject(new Error('Timeout'))), timeoutMs)
      )
    ])

  delay: (ms) ->
    new Promise((resolve) -> setTimeout(resolve, ms))

  interrupt: ->
    # Cancel all active processes
    console.log "Interrupting #{@activeProcesses.size} active processes"
    @activeProcesses.clear()

  getStats: ->
    return {
      currentMode: @currentMode
      activeProcesses: @activeProcesses.size
      totalCommunications: @communicationHistory.length
      patterns: Object.fromEntries(@patterns)
    }

module.exports = CorpusCallosum