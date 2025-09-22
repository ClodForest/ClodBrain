# Mode Executors - Each mode as its own class

# Base class for all mode executors
class ModeExecutor
  constructor: (@alpha, @beta, @config) ->
    @promptBuilder = new PromptBuilder()

  execute: (message, processId, recordComm) ->
    throw new Error "Subclasses must implement execute()"

  extractContent: (response) ->
    if typeof response is 'string' then response else response.content

  withTimeout: (promise, timeoutMs) ->
    Promise.race [
      promise
      new Promise (_, reject) ->
        setTimeout (-> reject(new Error('Timeout'))), timeoutMs
    ]

  delay: (ms) ->
    new Promise (resolve) -> setTimeout(resolve, ms)

# Parallel Mode - Both brains process simultaneously
class ParallelExecutor extends ModeExecutor
  execute: (message, processId, recordComm) ->
    promises = [
      @withTimeout(@alpha.processMessage(message, null), @config.timeout)
      @withTimeout(@beta.processMessage(message, null),  @config.timeout)
    ]

    results = await Promise.allSettled(promises)

    @buildResponse(results)

  buildResponse: (results) ->
    [alphaResult, betaResult] = results

    if alphaResult.status is 'rejected'
      console.error 'Alpha failed:', alphaResult.reason
    if betaResult.status is 'rejected'
      console.error 'Beta failed:', betaResult.reason

    {
      alphaResponse: if alphaResult.status is 'fulfilled' then alphaResult.value else null
      betaResponse:  if betaResult.status  is 'fulfilled' then betaResult.value  else null
    }

# Sequential Mode - One brain, then the other
class SequentialExecutor extends ModeExecutor
  constructor: (alpha, beta, config) ->
    super(alpha, beta, config)
    @defaultOrder = config.modes.sequential.default_order
    @handoffDelay = config.modes.sequential.handoff_delay

  execute: (message, processId, recordComm, order = null) ->
    order  = order || @defaultOrder
    models = { alpha: @alpha, beta: @beta }

    # First model
    firstModel    = models[order[0]]
    firstResponse = await firstModel.processMessage(message, null)

    # Delay between models
    await @delay(@handoffDelay)

    # Second model with context
    firstContent     = @extractContent(firstResponse)
    contextMessage   = @buildContextMessage(message, order[0], firstContent)
    secondModel      = models[order[1]]
    secondResponse   = await secondModel.processMessage(contextMessage, firstResponse)

    # Record handoff
    recordComm {
      from:    order[0]
      to:      order[1]
      message: firstContent
      type:    'handoff'
    }

    # Build response
    responses = {}
    responses[order[0]] = firstResponse
    responses[order[1]] = secondResponse

    {
      alphaResponse: responses.alpha
      betaResponse:  responses.beta
    }

  buildContextMessage: (originalMessage, fromModel, content) ->
    """
      #{originalMessage}

      Context from #{fromModel}: #{content}
    """

# Debate Mode - Iterative refinement through challenges
class DebateExecutor extends ModeExecutor
  constructor: (alpha, beta, config) ->
    super(alpha, beta, config)
    @maxRounds          = config.modes.debate.max_rounds
    @convergenceThreshold = config.modes.debate.convergence_threshold

  execute: (message, processId, recordComm) ->
    state = await @initializeDebate(message)

    for round in [1..@maxRounds]
      result = await @runDebateRound(message, state, round, recordComm)

      if @hasConverged(state.previousContent, result.refinedContent)
        console.log "Debate converged after #{round} rounds"
        break

      state = @updateState(state, result)

    @buildResponse(state)

  initializeDebate: (message) ->
    alphaResponse = await @alpha.processMessage(message, null)

    {
      alphaResponse:   alphaResponse
      previousContent: @extractContent(alphaResponse)
      betaResponse:    null
      round:           0
    }

  runDebateRound: (message, state, round, recordComm) ->
    # Beta challenges
    challengePrompt = @promptBuilder.buildDebateChallenge(message, state.previousContent)
    betaResponse    = await @beta.processMessage(challengePrompt, state.previousContent)
    betaContent     = @extractContent(betaResponse)

    recordComm {
      from:    'beta'
      to:      'alpha'
      message: betaContent
      type:    'challenge'
      round:   round
    }

    # Alpha refines
    refinePrompt  = @promptBuilder.buildDebateRefine(message, state.previousContent, betaContent)
    alphaRefined  = await @alpha.processMessage(refinePrompt, betaContent)
    refinedContent = @extractContent(alphaRefined)

    recordComm {
      from:    'alpha'
      to:      'beta'
      message: refinedContent
      type:    'refinement'
      round:   round
    }

    {
      betaResponse:   betaResponse
      alphaRefined:   alphaRefined
      refinedContent: refinedContent
    }

  updateState: (state, result) ->
    {
      ...state
      alphaResponse:   result.alphaRefined
      betaResponse:    result.betaResponse
      previousContent: result.refinedContent
      round:           state.round + 1
    }

  hasConverged: (previous, current) ->
    @calculateSimilarity(previous, current) > @convergenceThreshold

  calculateSimilarity: (text1, text2) ->
    str1 = String(text1).toLowerCase()
    str2 = String(text2).toLowerCase()

    words1      = str1.split(/\s+/)
    words2      = str2.split(/\s+/)
    commonWords = words1.filter (word) -> words2.includes(word)
    totalWords  = Math.max(words1.length, words2.length)

    if totalWords > 0 then commonWords.length / totalWords else 0

  buildResponse: (state) ->
    {
      alphaResponse: state.alphaResponse
      betaResponse:  state.betaResponse
      rounds:        state.round
    }

# Synthesis Mode - Parallel processing then unified response
class SynthesisExecutor extends ModeExecutor
  constructor: (alpha, beta, config) ->
    super(alpha, beta, config)
    @synthesisModel = config.modes.synthesis.synthesis_model
    @showIndividual = config.modes.synthesis.show_individual

  execute: (message, processId, recordComm) ->
    # Get both responses in parallel
    parallelExecutor = new ParallelExecutor(@alpha, @beta, @config)
    parallelResult   = await parallelExecutor.execute(message, processId, recordComm)

    # Extract contents
    contents = {
      alpha: @extractContent(parallelResult.alphaResponse)
      beta:  @extractContent(parallelResult.betaResponse)
    }

    # Synthesize
    synthesis = await @createSynthesis(message, contents, recordComm)

    # Build final response
    @buildResponse(parallelResult, synthesis)

  createSynthesis: (message, contents, recordComm) ->
    synthesizer     = if @synthesisModel is 'alpha' then @alpha else @beta
    synthesisPrompt = @promptBuilder.buildSynthesisPrompt(message, contents)
    synthesis       = await synthesizer.processMessage(synthesisPrompt, contents)

    recordComm {
      from:    'both'
      to:      'synthesis'
      message: @extractContent(synthesis)
      type:    'synthesis'
      inputs:  contents
    }

    synthesis

  buildResponse: (parallelResult, synthesis) ->
    {
      alphaResponse: if @showIndividual then parallelResult.alphaResponse else null
      betaResponse:  if @showIndividual then parallelResult.betaResponse  else null
      synthesis:     synthesis
    }

# Handoff Mode - Conditional processing based on content
class HandoffExecutor extends ModeExecutor
  constructor: (alpha, beta, config) ->
    super(alpha, beta, config)
    @triggerPhrases = config.modes.handoff.trigger_phrases
    @setupSelectionRules()

  setupSelectionRules: ->
    @modelSelectionRules =
      alpha: ['analyze', 'calculate', 'verify', 'facts', 'data', 'logical', 'step', 'method']
      beta:  ['create', 'imagine', 'design', 'alternative', 'innovative', 'brainstorm', 'idea']

  execute: (message, processId, recordComm) ->
    startModel      = @selectStartModel(message)
    primaryModel    = if startModel is 'alpha' then @alpha else @beta
    primaryResponse = await primaryModel.processMessage(message, null)
    primaryContent  = @extractContent(primaryResponse)

    if @shouldHandoff(primaryContent)
      await @executeHandoff(
        message,
        startModel,
        primaryResponse,
        primaryContent,
        recordComm
      )
    else
      @buildSingleResponse(startModel, primaryResponse)

  selectStartModel: (message) ->
    scores       = { alpha: 0, beta: 0 }
    lowerMessage = message.toLowerCase()

    for model, keywords of @modelSelectionRules
      scores[model] = keywords.filter((word) ->
        lowerMessage.includes(word)
      ).length

    if scores.alpha >= scores.beta then 'alpha' else 'beta'

  shouldHandoff: (content) ->
    lowerContent = content.toLowerCase()
    @triggerPhrases.some (phrase) ->
      lowerContent.includes(phrase.toLowerCase())

  executeHandoff: (message, startModel, primaryResponse, primaryContent, recordComm) ->
    otherModelName = if startModel is 'alpha' then 'beta' else 'alpha'
    otherModel     = if startModel is 'alpha' then @beta else @alpha

    handoffPrompt    = @promptBuilder.buildHandoffPrompt(message, startModel, primaryContent)
    secondaryResponse = await otherModel.processMessage(handoffPrompt, primaryContent)

    recordComm {
      from:    startModel
      to:      otherModelName
      message: @getHandoffReason(startModel)
      type:    'handoff'
    }

    @buildDualResponse(startModel, primaryResponse, secondaryResponse, otherModelName)

  getHandoffReason: (fromModel) ->
    reasons =
      alpha: "Handing off for creative input"
      beta:  "Handing off for analytical verification"
    reasons[fromModel]

  buildSingleResponse: (model, response) ->
    {
      alphaResponse: if model is 'alpha' then response else null
      betaResponse:  if model is 'beta'  then response else null
      primary:       model
    }

  buildDualResponse: (startModel, firstResponse, secondResponse, primaryModel) ->
    {
      alphaResponse: if startModel is 'alpha' then firstResponse  else secondResponse
      betaResponse:  if startModel is 'beta'  then firstResponse  else secondResponse
      primary:       primaryModel
    }

# Prompt builder remains the same
class PromptBuilder
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
      beta:  "Beta's creative perspective"

    continuations =
      alpha: "Please continue with a creative perspective."
      beta:  "Please provide analytical verification and structure."

    """
      #{message}

      #{perspectives[fromModel]}: #{content}

      #{continuations[fromModel]}
    """

# RolePlay Mode - Character-based collaborative storytelling
class RolePlayExecutor extends ModeExecutor
  constructor: (alpha, beta, config) ->
    super(alpha, beta, config)
    @character = null
    @scenario = null
    @worldInfo = null
    @messageHistory = []
    @maxContextMessages = 20

  setCharacter: (characterCard) ->
    @character = @parseCharacterCard(characterCard)
    @scenario = characterCard.scenario || null
    @worldInfo = characterCard.world_info || null
    @messageHistory = []

    # Add first greeting to message history if available
    if @character.first_mes
      @messageHistory.push { role: 'assistant', content: @character.first_mes, isOOC: false }

    console.log "Character loaded: #{@character.name}"

  parseCharacterCard: (card) ->
    # Support SillyTavern character card format
    {
      name: card.name || 'Character'
      description: card.description || ''
      personality: card.personality || ''
      first_mes: card.first_mes || ''
      mes_example: card.mes_example || ''
      scenario: card.scenario || ''
      creator_notes: card.creator_notes || ''
      system_prompt: card.system_prompt || ''
      alternate_greetings: card.alternate_greetings || []
      tags: card.tags || []
    }

  execute: (message, processId, recordComm, isOOC = false) ->
    unless @character
      throw new Error "No character loaded. Please load a character card first."

    # Store the user message in history
    @messageHistory.push { role: 'user', content: message, isOOC }

    if isOOC
      # Handle OOC messages - brains discuss the character/scene
      @handleOOCMessage(message, processId, recordComm)
    else
      # Handle IC messages - generate in-character response
      @handleICMessage(message, processId, recordComm)

  handleICMessage: (message, processId, recordComm) ->
    # Build context for both brains
    context = @buildCharacterContext()

    # Alpha analyzes character consistency and scene logic
    alphaPrompt = """
      #{context}

      As the analytical brain, analyze the current scene and ensure character consistency.
      Consider: personality traits, established relationships, scene continuity.
      User says: "#{message}"

      Provide brief OOC notes about how #{@character.name} should respond.
    """

    # Beta generates creative character response
    betaPrompt = """
      #{context}

      As the creative brain, embody #{@character.name} and respond naturally.
      Stay true to their voice, mannerisms, and emotional state.
      User says: "#{message}"

      Respond as #{@character.name} would, in character.
    """

    # Get both responses in parallel
    promises = [
      @alpha.processMessage(alphaPrompt, null)
      @beta.processMessage(betaPrompt, null)
    ]

    results = await Promise.allSettled(promises)
    [alphaResult, betaResult] = results

    # Extract responses
    alphaContent = if alphaResult.status is 'fulfilled'
      @extractContent(alphaResult.value)
    else
      null

    betaContent = if betaResult.status is 'fulfilled'
      @extractContent(betaResult.value)
    else
      null

    # Record Alpha's analysis as OOC communication
    if alphaContent
      recordComm {
        from: 'alpha'
        to: 'ooc'
        message: alphaContent
        type: 'character_analysis'
      }

    # Beta refines response based on Alpha's analysis
    if alphaContent and betaContent
      refinementPrompt = """
        #{context}

        Alpha's consistency notes: #{alphaContent}
        Your initial response: #{betaContent}

        Refine your response as #{@character.name}, incorporating Alpha's insights while maintaining the character's authentic voice.
      """

      refinedResponse = await @beta.processMessage(refinementPrompt, alphaContent)
      finalICResponse = @extractContent(refinedResponse)

      recordComm {
        from: 'beta'
        to: 'alpha'
        message: 'Refined character response based on consistency analysis'
        type: 'refinement'
      }
    else
      finalICResponse = betaContent

    # Store the character's response in history
    @messageHistory.push { role: 'assistant', content: finalICResponse, isOOC: false }

    # Trim history if too long
    if @messageHistory.length > @maxContextMessages * 2
      @messageHistory = @messageHistory.slice(-@maxContextMessages * 2)

    {
      alphaResponse: alphaContent  # OOC analysis
      betaResponse: betaContent    # Initial IC response
      icResponse: finalICResponse  # Final IC response
      character: @character.name
      isOOC: false
    }

  handleOOCMessage: (message, processId, recordComm) ->
    # Both brains discuss the scene/character out of character
    oocPrompt = """
      Character: #{@character.name}
      Description: #{@character.description}
      Current scenario: #{@scenario || 'Not specified'}

      OOC Discussion requested: #{message}

      Provide your perspective on the character, scene, or story development.
    """

    promises = [
      @alpha.processMessage(oocPrompt + "\nAs Alpha, provide analytical insights about story structure, consistency, and character development.", null)
      @beta.processMessage(oocPrompt + "\nAs Beta, provide creative ideas about potential plot twists, emotional depth, and character growth.", null)
    ]

    results = await Promise.allSettled(promises)
    [alphaResult, betaResult] = results

    alphaContent = if alphaResult.status is 'fulfilled'
      @extractContent(alphaResult.value)
    else
      'Alpha encountered an error'

    betaContent = if betaResult.status is 'fulfilled'
      @extractContent(betaResult.value)
    else
      'Beta encountered an error'

    recordComm {
      from: 'both'
      to: 'ooc'
      message: 'Out-of-character discussion'
      type: 'ooc_discussion'
    }

    {
      alphaResponse: alphaContent
      betaResponse: betaContent
      icResponse: null
      character: @character?.name
      isOOC: true
    }

  buildCharacterContext: ->
    return '' unless @character

    # Build character context including recent history
    characterName = @character.name
    recentHistory = @messageHistory
      .slice(-@maxContextMessages)
      .map((msg) ->
        role = if msg.role is 'user' then 'User' else characterName
        "#{role}: #{msg.content}"
      )
      .join('\n')

    """
      Character: #{@character.name}
      Description: #{@character.description}
      Personality: #{@character.personality}
      #{if @scenario then "Scenario: #{@scenario}" else ''}
      #{if @character.system_prompt then "System: #{@character.system_prompt}" else ''}

      #{if recentHistory then "Recent conversation:\n#{recentHistory}" else ''}
    """

  resetConversation: ->
    @messageHistory = []
    if @character?.first_mes
      @messageHistory.push { role: 'assistant', content: @character.first_mes, isOOC: false }
    # Return the first message for display
    @character?.first_mes

module.exports = {
  ModeExecutor
  ParallelExecutor
  SequentialExecutor
  DebateExecutor
  SynthesisExecutor
  HandoffExecutor
  RolePlayExecutor
  PromptBuilder
}