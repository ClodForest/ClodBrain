# Corpus Callosum - Simplified orchestration using mode executors
{
  ParallelExecutor
  SequentialExecutor
  DebateExecutor
  SynthesisExecutor
  HandoffExecutor
  RolePlayExecutor
} = require './mode-executors'

class CorpusCallosum
  constructor: (@alpha, @beta, @config) ->
    @currentMode          = @config.default_mode
    @modeParameters       = {}
    @communicationHistory = []
    @activeProcesses      = new Map()
    @patterns             = new Map()

    @initializeExecutors()
    @initializeClassifiers()

  initializeExecutors: ->
    @executors =
      parallel:   new ParallelExecutor(@alpha, @beta, @config)
      sequential: new SequentialExecutor(@alpha, @beta, @config)
      debate:     new DebateExecutor(@alpha, @beta, @config)
      synthesis:  new SynthesisExecutor(@alpha, @beta, @config)
      handoff:    new HandoffExecutor(@alpha, @beta, @config)
      roleplay:   new RolePlayExecutor(@alpha, @beta, @config)

  initializeClassifiers: ->
    @messageClassifiers = [
      { pattern: /\b(how|what|why|when|where|who)\b/,             type: 'question' }
      { pattern: /\b(create|make|design|build|generate)\b/,       type: 'creation' }
      { pattern: /\b(analyze|examine|evaluate|assess|review)\b/,  type: 'analysis' }
      { pattern: /\b(help|assist|support|guide)\b/,               type: 'assistance' }
    ]

  # Main orchestration method
  orchestrate: (userMessage, conversationId, mode = null, options = {}) ->
    activeMode = mode || @currentMode
    processId  = @generateProcessId()

    process = @createProcess(processId, activeMode, userMessage, conversationId)
    @activeProcesses.set(processId, process)

    try
      executor = @executors[activeMode]
      throw new Error "Unknown mode: #{activeMode}" unless executor

      # Create communication recorder for this process
      recordComm = (communication) => @recordCommunication(processId, communication)

      # Handle role-play specific options
      if activeMode is 'roleplay'
        # Pass isOOC flag if provided
        console.log "Running roleplay mode (#{if options.isOOC then 'OOC' else 'IC'}): #{userMessage}"
        result = await executor.execute(userMessage, processId, recordComm, options.isOOC)
      else
        # Execute the mode normally
        console.log "Running #{activeMode} mode for: #{userMessage}"
        result = await executor.execute(userMessage, processId, recordComm, @modeParameters)

      # Finalize result
      result = @finalizeResult(result, activeMode, processId)

      # Store pattern for learning
      @storePattern(activeMode, userMessage, result)

      return result

    finally
      @activeProcesses.delete(processId)

  # Process management
  createProcess: (id, mode, message, conversationId) ->
    {
      id:             id
      mode:           mode
      startTime:      Date.now()
      userMessage:    message
      conversationId: conversationId
      communications: []
    }

  finalizeResult: (result, mode, processId) ->
    {
      ...result
      mode:           mode
      communications: @getProcessCommunications(processId)
      timestamp:      new Date().toISOString()
    }

  # Communication tracking
  recordCommunication: (processId, communication) ->
    process = @activeProcesses.get(processId)
    return unless process

    communication.timestamp = Date.now()
    process.communications.push(communication)

    @communicationHistory.push({
      processId,
      ...communication
    })

  getProcessCommunications: (processId) ->
    @activeProcesses.get(processId)?.communications || []

  # Pattern learning
  storePattern: (mode, message, result) ->
    pattern = {
      mode:        mode
      messageType: @classifyMessage(message)
      success:     result?
      timestamp:   Date.now()
    }

    key = "#{pattern.mode}_#{pattern.messageType}"
    @patterns.set(key, []) unless @patterns.has(key)

    patterns = @patterns.get(key)
    patterns.push(pattern)
    @patterns.set(key, patterns.slice(-100)) if patterns.length > 100

  classifyMessage: (message) ->
    lowerMessage = message.toLowerCase()

    for classifier in @messageClassifiers
      return classifier.type if classifier.pattern.test(lowerMessage)

    'general'

  # Mode management
  setMode: (mode, parameters = {}) ->
    unless @executors[mode]
      throw new Error "Invalid mode: #{mode}"

    @currentMode    = mode
    @modeParameters = parameters
    console.log "Corpus Callosum mode changed to: #{mode}"

  # Character management for roleplay mode
  loadCharacter: (characterCard) ->
    roleplayExecutor = @executors.roleplay
    unless roleplayExecutor
      throw new Error "Roleplay executor not initialized"

    roleplayExecutor.setCharacter(characterCard)
    @currentMode = 'roleplay'
    console.log "Character loaded for roleplay mode"

    # Return character info including first message
    {
      name: characterCard.name
      scenario: characterCard.scenario
      first_mes: characterCard.first_mes
    }

  resetRoleplay: ->
    roleplayExecutor = @executors.roleplay
    if roleplayExecutor
      firstMessage = roleplayExecutor.resetConversation()
      console.log "Roleplay conversation reset"
      firstMessage

  # Utilities
  generateProcessId: ->
    "proc_#{Date.now()}_#{Math.random().toString(36).substr(2, 9)}"

  interrupt: ->
    console.log "Interrupting #{@activeProcesses.size} active processes"
    @activeProcesses.clear()

  getStats: ->
    {
      currentMode:          @currentMode
      activeProcesses:      @activeProcesses.size
      totalCommunications: @communicationHistory.length
      patterns:            Object.fromEntries(@patterns)
      availableModes:      Object.keys(@executors)
    }

module.exports = CorpusCallosum