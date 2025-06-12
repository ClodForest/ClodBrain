# Corpus Callosum - Inter-LLM Communication Service (Data-Driven Refactor)
class CorpusCallosum
  constructor: (@alpha, @beta, @config) ->
    @currentMode = @config.default_mode
    @communicationHistory = []
    @activeProcesses = new Map()
    @patterns = new Map()
    
    # Data-driven mode definitions
    @modeHandlers = 
      parallel: @createParallelHandler()
      sequential: @createSequentialHandler()
      debate: @createDebateHandler()
      synthesis: @createSynthesisHandler()
      handoff: @createHandoffHandler()
    
    # Message classification rules
    @messageClassifiers = [
      { pattern: /\b(how|what|why|when|where|who)\b/, type: 'question' }
      { pattern: /\b(create|make|design|build|generate)\b/, type: 'creation' }
      { pattern: /\b(analyze|examine|evaluate|assess|review)\b/, type: 'analysis' }
      { pattern: /\b(help|assist|support|guide)\b/, type: 'assistance' }
    ]
    
    # Keyword scoring for model selection
    @modelSelectionRules =
      alpha: ['analyze', 'calculate', 'verify', 'facts', 'data', 'logical', 'step', 'method']
      beta: ['create', 'imagine', 'design', 'alternative', 'innovative', 'brainstorm', 'idea']

  setMode: (mode, parameters = {}) ->
    unless @modeHandlers[mode]
      throw new Error "Invalid mode: #{mode}"
    
    @currentMode = mode
    @modeParameters = parameters
    console.log "Corpus Callosum mode changed to: #{mode}"

  orchestrate: (userMessage, conversationId, mode = null) ->
    activeMode = mode || @currentMode
    processId = @generateProcessId()
    
    process = {
      mode: activeMode
      startTime: Date.now()
      userMessage: userMessage
      conversationId: conversationId
      communications: []
    }
    
    @activeProcesses.set(processId, process)
    
    try
      handler = @modeHandlers[activeMode]
      unless handler
        throw new Error "Unknown mode: #{activeMode}"
      
      result = await handler(userMessage, processId)
      @storePattern(activeMode, userMessage, result)
      return result
      
    finally
      @activeProcesses.delete(processId)

  # Factory methods for mode handlers
  createParallelHandler: ->
    (message, processId) =>
      console.log "Running parallel mode for: #{message}"
      
      promises = [@alpha, @beta].map (model) => 
        @withTimeout(model.processMessage(message, null), @config.communication_timeout)
      
      results = await Promise.allSettled(promises)
      
      [alphaResult, betaResult] = results.map (result, index) =>
        if result.status is 'rejected'
          console.error "#{['Alpha', 'Beta'][index]} failed:", result.reason
          return null
        result.value
      
      return {
        mode: 'parallel'
        alphaResponse: alphaResult
        betaResponse: betaResult
        communications: @getProcessCommunications(processId)
        timestamp: new Date().toISOString()
      }

  createSequentialHandler: ->
    (message, processId) =>
      console.log "Running sequential mode for: #{message}"
      
      order = @modeParameters?.order || @config.modes.sequential.default_order
      models = { alpha: @alpha, beta: @beta }
      
      [firstKey, secondKey] = order
      firstModel = models[firstKey]
      secondModel = models[secondKey]
      
      firstResponse = await firstModel.processMessage(message, null)
      await @delay(@config.modes.sequential.handoff_delay)
      
      firstContent = @extractContent(firstResponse)
      contextMessage = "#{message}\n\nContext from #{firstKey}: #{firstContent}"
      secondResponse = await secondModel.processMessage(contextMessage, firstResponse)
      
      @recordCommunication(processId, {
        from: firstKey, to: secondKey
        message: firstContent, type: 'handoff'
      })
      
      responses = { [firstKey]: firstResponse, [secondKey]: secondResponse }
      
      return {
        mode: 'sequential'
        alphaResponse: responses.alpha
        betaResponse: responses.beta
        communications: @getProcessCommunications(processId)
        timestamp: new Date().toISOString()
      }

  createDebateHandler: ->
    (message, processId) =>
      console.log "Running debate mode for: #{message}"
      
      state = 
        alphaResponse: await @alpha.processMessage(message, null)
        betaResponse: null
        round: 0
      
      debateRound = (state) =>
        state.round++
        alphaContent = @extractContent(state.alphaResponse)
        
        # Beta challenges
        challengePrompt = @buildDebatePrompt('challenge', message, alphaContent)
        state.betaResponse = await @beta.processMessage(challengePrompt, alphaContent)
        betaContent = @extractContent(state.betaResponse)
        
        @recordCommunication(processId, {
          from: 'beta', to: 'alpha'
          message: betaContent, type: 'challenge'
          round: state.round
        })
        
        # Alpha refines
        refinePrompt = @buildDebatePrompt('refine', message, alphaContent, betaContent)
        refinedResponse = await @alpha.processMessage(refinePrompt, betaContent)
        refinedContent = @extractContent(refinedResponse)
        
        @recordCommunication(processId, {
          from: 'alpha', to: 'beta'
          message: refinedContent, type: 'refinement'
          round: state.round
        })
        
        converged = @calculateSimilarity(alphaContent, refinedContent) > 
                   @config.modes.debate.convergence_threshold
        
        if converged
          console.log "Debate converged after #{state.round} rounds"
        
        state.alphaResponse = refinedResponse
        return { converged, state }
      
      # Run debate rounds
      maxRounds = @config.modes.debate.max_rounds
      while state.round < maxRounds
        result = await debateRound(state)
        break if result.converged
      
      return {
        mode: 'debate'
        alphaResponse: state.alphaResponse
        betaResponse: state.betaResponse
        communications: @getProcessCommunications(processId)
        rounds: state.round
        timestamp: new Date().toISOString()
      }

  createSynthesisHandler: ->
    (message, processId) =>
      console.log "Running synthesis mode for: #{message}"
      
      [alphaResponse, betaResponse] = await Promise.all([
        @alpha.processMessage(message, null)
        @beta.processMessage(message, null)
      ])
      
      contents = 
        alpha: @extractContent(alphaResponse)
        beta: @extractContent(betaResponse)
      
      synthesisModel = @getSynthesisModel()
      synthesisPrompt = @buildSynthesisPrompt(message, contents)
      
      synthesisResponse = await synthesisModel.processMessage(synthesisPrompt, contents)
      
      @recordCommunication(processId, {
        from: 'both', to: 'synthesis'
        message: @extractContent(synthesisResponse)
        type: 'synthesis'
        inputs: contents
      })
      
      showIndividual = @config.modes.synthesis.show_individual
      
      return {
        mode: 'synthesis'
        alphaResponse: if showIndividual then alphaResponse else null
        betaResponse: if showIndividual then betaResponse else null
        synthesis: synthesisResponse
        communications: @getProcessCommunications(processId)
        timestamp: new Date().toISOString()
      }

  createHandoffHandler: ->
    (message, processId) =>
      console.log "Running handoff mode for: #{message}"
      
      startModel = @selectStartModel(message)
      models = { alpha: @alpha, beta: @beta }
      
      primaryResponse = await models[startModel].processMessage(message, null)
      primaryContent = @extractContent(primaryResponse)
      
      shouldHandoff = @detectHandoffTrigger(primaryContent)
      
      unless shouldHandoff
        return @buildHandoffResult(
          startModel, 
          { [startModel]: primaryResponse },
          processId
        )
      
      # Handoff needed
      otherModel = if startModel is 'alpha' then 'beta' else 'alpha'
      handoffPrompt = @buildHandoffPrompt(message, startModel, primaryContent)
      secondaryResponse = await models[otherModel].processMessage(handoffPrompt, primaryContent)
      
      @recordCommunication(processId, {
        from: startModel, to: otherModel
        message: "Handing off for #{@getHandoffReason(startModel)}"
        type: 'handoff'
      })
      
      return @buildHandoffResult(
        otherModel,
        { [startModel]: primaryResponse, [otherModel]: secondaryResponse },
        processId
      )

  # Helper methods
  extractContent: (response) ->
    if typeof response is 'string' then response else response.content

  buildDebatePrompt: (type, message, alphaContent, betaContent = null) ->
    prompts =
      challenge: """
        Original question: #{message}
        Alpha's response: #{alphaContent}
        
        Provide a creative challenge or alternative perspective to Alpha's response.
        Focus on what might be missing, alternative approaches, or creative insights.
      """
      refine: """
        Original question: #{message}
        Your previous response: #{alphaContent}
        Beta's challenge: #{betaContent}
        
        Refine your response considering Beta's creative perspective.
        Integrate valid points while maintaining analytical rigor.
      """
    prompts[type]

  buildSynthesisPrompt: (message, contents) ->
    """
    Original question: #{message}
    
    Alpha's analytical response: #{contents.alpha}
    Beta's creative response: #{contents.beta}
    
    Create a unified response that synthesizes both perspectives.
    Combine the logical rigor of Alpha with the creative insights of Beta.
    The result should be more complete than either individual response.
    """

  buildHandoffPrompt: (message, fromModel, content) ->
    perspectives =
      alpha: "Alpha's initial analysis"
      beta: "Beta's creative perspective"
    
    continuations =
      alpha: "Please continue with a creative perspective."
      beta: "Please provide analytical verification and structure."
    
    "#{message}\n\n#{perspectives[fromModel]}: #{content}\n\n#{continuations[fromModel]}"

  buildHandoffResult: (primaryModel, responses, processId) ->
    {
      mode: 'handoff'
      alphaResponse: responses.alpha || null
      betaResponse: responses.beta || null
      primary: primaryModel
      communications: @getProcessCommunications(processId)
      timestamp: new Date().toISOString()
    }

  getHandoffReason: (fromModel) ->
    reasons =
      alpha: "creative input"
      beta: "analytical verification"
    reasons[fromModel]

  getSynthesisModel: ->
    modelName = @config.modes.synthesis.synthesis_model
    if modelName is 'alpha' then @alpha else @beta

  selectStartModel: (message) ->
    scores = {}
    lowerMessage = message.toLowerCase()
    
    for model, keywords of @modelSelectionRules
      scores[model] = keywords.filter((word) -> lowerMessage.includes(word)).length
    
    if scores.alpha >= scores.beta then 'alpha' else 'beta'

  detectHandoffTrigger: (response) ->
    triggerPhrases = @config.modes.handoff.trigger_phrases
    lowerResponse = response.toLowerCase()
    triggerPhrases.some((phrase) -> lowerResponse.includes(phrase.toLowerCase()))

  classifyMessage: (message) ->
    lowerMessage = message.toLowerCase()
    
    for classifier in @messageClassifiers
      return classifier.type if classifier.pattern.test(lowerMessage)
    
    return 'general'

  # Unchanged utility methods
  generateProcessId: ->
    "proc_#{Date.now()}_#{Math.random().toString(36).substr(2, 9)}"

  recordCommunication: (processId, communication) ->
    process = @activeProcesses.get(processId)
    return unless process
    
    communication.timestamp = Date.now()
    process.communications.push(communication)
    @communicationHistory.push({ processId, ...communication })

  getProcessCommunications: (processId) ->
    @activeProcesses.get(processId)?.communications || []

  calculateSimilarity: (text1, text2) ->
    str1 = String(text1).toLowerCase()
    str2 = String(text2).toLowerCase()
    
    words1 = str1.split(/\s+/)
    words2 = str2.split(/\s+/)
    
    commonWords = words1.filter((word) -> words2.includes(word))
    totalWords = Math.max(words1.length, words2.length)
    
    if totalWords > 0 then commonWords.length / totalWords else 0

  storePattern: (mode, message, result) ->
    pattern = {
      mode: mode
      messageType: @classifyMessage(message)
      success: result?
      timestamp: Date.now()
    }
    
    key = "#{pattern.mode}_#{pattern.messageType}"
    @patterns.set(key, []) unless @patterns.has(key)
    
    patterns = @patterns.get(key)
    patterns.push(pattern)
    @patterns.set(key, patterns.slice(-100)) if patterns.length > 100

  withTimeout: (promise, timeoutMs) ->
    Promise.race([
      promise
      new Promise((_, reject) ->
        setTimeout((-> reject(new Error('Timeout'))), timeoutMs)
      )
    ])

  delay: (ms) ->
    new Promise((resolve) -> setTimeout(resolve, ms))

  interrupt: ->
    console.log "Interrupting #{@activeProcesses.size} active processes"
    @activeProcesses.clear()

  getStats: ->
    {
      currentMode: @currentMode
      activeProcesses: @activeProcesses.size
      totalCommunications: @communicationHistory.length
      patterns: Object.fromEntries(@patterns)
    }

module.exports = CorpusCallosum