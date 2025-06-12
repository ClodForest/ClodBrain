# Corpus Callosum - Inter-LLM Communication Service (With Mode Abstraction)
class CorpusCallosum
  constructor: (@alpha, @beta, @config) ->
    @currentMode = @config.default_mode
    @communicationHistory = []
    @activeProcesses = new Map()
    @patterns = new Map()

    # Base mode configuration with common patterns
    @modeConfigs =
      parallel:
        executor: 'parallel'
        models: ['alpha', 'beta']
        waitForAll: true

      sequential:
        executor: 'sequence'
        models: ['alpha', 'beta']
        passContext: true
        delay: => @config.modes.sequential.handoff_delay

      debate:
        executor: 'iterative'
        models: ['alpha', 'beta']
        maxIterations: => @config.modes.debate.max_rounds
        convergenceCheck: (prev, current) =>
          @calculateSimilarity(prev, current) > @config.modes.debate.convergence_threshold
        templates:
          challenge: @buildDebateChallenge
          refine: @buildDebateRefine

      synthesis:
        executor: 'parallel-then-process'
        models: ['alpha', 'beta']
        processor: => @getSynthesisModel()
        template: @buildSynthesisPrompt
        showOriginals: => @config.modes.synthesis.show_individual

      handoff:
        executor: 'conditional-sequence'
        modelSelector: (message) => @selectStartModel(message)
        handoffDetector: (content) => @detectHandoffTrigger(content)
        templates:
          handoff: @buildHandoffPrompt

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
    unless @modeConfigs[mode]
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
      config = @modeConfigs[activeMode]
      unless config
        throw new Error "Unknown mode: #{activeMode}"

      # Execute using the appropriate executor pattern
      result = await @executeMode(config, userMessage, processId)

      # Add common fields
      result.mode = activeMode
      result.communications = @getProcessCommunications(processId)
      result.timestamp = new Date().toISOString()

      @storePattern(activeMode, userMessage, result)
      return result

    finally
      @activeProcesses.delete(processId)

  # Generic mode executor
  executeMode: (config, message, processId) ->
    console.log "Running #{@currentMode} mode for: #{message}"

    executors =
      'parallel': => @executeParallel(config, message, processId)
      'sequence': => @executeSequence(config, message, processId)
      'iterative': => @executeIterative(config, message, processId)
      'parallel-then-process': => @executeParallelThenProcess(config, message, processId)
      'conditional-sequence': => @executeConditionalSequence(config, message, processId)

    executor = executors[config.executor]
    unless executor
      throw new Error "Unknown executor: #{config.executor}"

    return await executor()

  # Parallel execution pattern (used by parallel mode)
  executeParallel: (config, message, processId) ->
    models = @getModels(config.models)

    promises = models.map ([name, model]) =>
      @withTimeout(model.processMessage(message, null), @config.communication_timeout)

    results = await Promise.allSettled(promises)

    responses = {}
    results.forEach (result, index) =>
      [name, _] = models[index]
      if result.status is 'rejected'
        console.error "#{name} failed:", result.reason
        responses[name] = null
      else
        responses[name] = result.value

    return {
      alphaResponse: responses.alpha
      betaResponse: responses.beta
    }

  # Sequential execution pattern (used by sequential mode)
  executeSequence: (config, message, processId) ->
    order = @modeParameters?.order || config.models
    models = @getModelsMap()
    responses = {}

    currentMessage = message
    currentContext = null

    for modelName, index in order
      model = models[modelName]

      # Add delay between models if configured
      if index > 0 and config.delay
        await @delay(config.delay())

      response = await model.processMessage(currentMessage, currentContext)
      responses[modelName] = response

      # Pass context to next model if configured
      if config.passContext and index < order.length - 1
        content = @extractContent(response)
        currentContext = response
        currentMessage = "#{message}\n\nContext from #{modelName}: #{content}"

        @recordCommunication(processId, {
          from: modelName
          to: order[index + 1]
          message: content
          type: 'handoff'
        })

    return {
      alphaResponse: responses.alpha
      betaResponse: responses.beta
    }

  # Iterative execution pattern (used by debate mode)
  executeIterative: (config, message, processId) ->
    [firstModel, secondModel] = config.models
    models = @getModelsMap()

    # Initial response from first model
    currentResponse = await models[firstModel].processMessage(message, null)
    previousContent = @extractContent(currentResponse)
    secondResponse = null

    maxIterations = config.maxIterations()

    for round in [1..maxIterations]
      # Second model challenges/responds
      challengePrompt = config.templates.challenge.call(this, message, previousContent)
      secondResponse = await models[secondModel].processMessage(challengePrompt, previousContent)
      secondContent = @extractContent(secondResponse)

      @recordCommunication(processId, {
        from: secondModel, to: firstModel
        message: secondContent, type: 'challenge'
        round: round
      })

      # First model refines
      refinePrompt = config.templates.refine.call(this, message, previousContent, secondContent)
      refinedResponse = await models[firstModel].processMessage(refinePrompt, secondContent)
      refinedContent = @extractContent(refinedResponse)

      @recordCommunication(processId, {
        from: firstModel, to: secondModel
        message: refinedContent, type: 'refinement'
        round: round
      })

      # Check for convergence
      if config.convergenceCheck(previousContent, refinedContent)
        console.log "Converged after #{round} rounds"
        currentResponse = refinedResponse
        break

      previousContent = refinedContent
      currentResponse = refinedResponse

    return {
      alphaResponse: if firstModel is 'alpha' then currentResponse else secondResponse
      betaResponse: if firstModel is 'beta' then currentResponse else secondResponse
      rounds: round
    }

  # Parallel then process pattern (used by synthesis mode)
  executeParallelThenProcess: (config, message, processId) ->
    # Get initial responses in parallel
    parallelResult = await @executeParallel(config, message, processId)

    contents =
      alpha: @extractContent(parallelResult.alphaResponse)
      beta: @extractContent(parallelResult.betaResponse)

    # Process with designated processor
    processor = config.processor()
    synthesisPrompt = config.template.call(this, message, contents)
    synthesisResponse = await processor.processMessage(synthesisPrompt, contents)

    @recordCommunication(processId, {
      from: 'both', to: 'synthesis'
      message: @extractContent(synthesisResponse)
      type: 'synthesis'
      inputs: contents
    })

    showOriginals = config.showOriginals()

    return {
      alphaResponse: if showOriginals then parallelResult.alphaResponse else null
      betaResponse: if showOriginals then parallelResult.betaResponse else null
      synthesis: synthesisResponse
    }

  # Conditional sequence pattern (used by handoff mode)
  executeConditionalSequence: (config, message, processId) ->
    startModel = config.modelSelector(message)
    models = @getModelsMap()

    primaryResponse = await models[startModel].processMessage(message, null)
    primaryContent = @extractContent(primaryResponse)

    shouldHandoff = config.handoffDetector(primaryContent)

    unless shouldHandoff
      return {
        alphaResponse: if startModel is 'alpha' then primaryResponse else null
        betaResponse: if startModel is 'beta' then primaryResponse else null
        primary: startModel
      }

    # Handoff needed
    otherModel = if startModel is 'alpha' then 'beta' else 'alpha'
    handoffPrompt = config.templates.handoff.call(this, message, startModel, primaryContent)
    secondaryResponse = await models[otherModel].processMessage(handoffPrompt, primaryContent)

    @recordCommunication(processId, {
      from: startModel, to: otherModel
      message: "Handing off for #{@getHandoffReason(startModel)}"
      type: 'handoff'
    })

    return {
      alphaResponse: if startModel is 'alpha' then primaryResponse else secondaryResponse
      betaResponse: if startModel is 'beta' then primaryResponse else secondaryResponse
      primary: otherModel
    }

  # Model access helpers
  getModels: (names) ->
    models = { alpha: @alpha, beta: @beta }
    names.map (name) -> [name, models[name]]

  getModelsMap: ->
    { alpha: @alpha, beta: @beta }

  # Template methods
  buildDebateChallenge: (message, alphaContent) ->
    """
    Original question: #{message}
    Alpha's response: #{alphaContent}

    Provide a creative challenge or alternative perspective to Alpha's response.
    Focus on what might be missing, alternative approaches, or creative insights.
    """

  buildDebateRefine: (message, alphaContent, betaContent) ->
    """
    Original question: #{message}
    Your previous response: #{alphaContent}
    Beta's challenge: #{betaContent}

    Refine your response considering Beta's creative perspective.
    Integrate valid points while maintaining analytical rigor.
    """

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

  # Helper methods
  extractContent: (response) ->
    if typeof response is 'string' then response else response.content

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
