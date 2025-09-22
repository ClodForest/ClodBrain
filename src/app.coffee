express           = require 'express'
http              = require 'http'
{ Server }        = require 'socket.io'
path              = require 'path'

require 'dotenv/config'

LLMAlpha       = require './services/llm-alpha'
LLMBeta        = require './services/llm-beta'
CorpusCallosum = require './services/corpus-callosum'
Neo4jTool      = require './services/neo4j-tool'
MessageRouter  = require './services/message-router'

databaseConfig = require './config/database'
ollamaConfig   = require './config/ollama'
modelsConfig   = require './config/models'

isoDateString  = -> new Date().toISOString()

class DualLLMApp
  constructor: ->
    @app    = express()
    @server = http.createServer(@app)
    @io = new Server(@server, {
      cors:
        origin:  "*"
        methods: ["GET", "POST"]
    })
    @port = process.env.PORT || 3000

  initialize: ->
    await @initializeServices()
    @setupMiddleware()
    @setupRoutes()
    @setupWebSockets()
    @setupErrorHandling()

  initializeServices: ->
    console.log 'Initializing services...'

    @neo4jTool = new Neo4jTool(databaseConfig)
    await @neo4jTool.connect()

    @llmAlpha = new LLMAlpha(modelsConfig.alpha, ollamaConfig, @neo4jTool)
    @llmBeta  = new LLMBeta(modelsConfig.beta, ollamaConfig, @neo4jTool)

    @corpusCallosum = new CorpusCallosum(@llmAlpha, @llmBeta, modelsConfig.corpus_callosum)
    @messageRouter  = new MessageRouter(@corpusCallosum, @neo4jTool)

  setupMiddleware: ->
    # CORS handling
    @app.use (req, res, next) ->
      res.header 'Access-Control-Allow-Origin',      '*'
      res.header 'Access-Control-Allow-Methods',     'GET,PUT,POST,DELETE,OPTIONS'
      res.header 'Access-Control-Allow-Headers',     'Content-Type, Authorization, Content-Length, X-Requested-With'

      if req.method is 'OPTIONS'
        res.sendStatus 200
      else
        next()

    # Security headers
    @app.use (req, res, next) ->
      res.setHeader 'X-Content-Type-Options', 'nosniff'
      res.setHeader 'X-Frame-Options',        'DENY'
      res.setHeader 'X-XSS-Protection',       '1; mode=block'
      next()

    # Request logging
    @app.use (req, res, next) ->
      console.log "#{isoDateString()} #{req.method} #{req.url}"
      next()

    @app.use express.json({ limit: '10mb' })
    @app.use express.urlencoded({ extended: true })
    @app.use express.static(path.join(__dirname, '../public'))

    # Make services available to routes
    @app.locals.messageRouter  = @messageRouter
    @app.locals.neo4jTool      = @neo4jTool
    @app.locals.corpusCallosum = @corpusCallosum

  setupRoutes: ->
    @app.post '/api/chat/message', (req, res) =>
      try
        { message, mode = 'parallel', conversationId } = req.body
        result = await @messageRouter.processMessage(message, mode, conversationId)
        res.json(result)
      catch error
        console.error 'Chat API error:', error
        res.status(500).json({ error: error.message })

    @app.get '/api/chat/history/:id', (req, res) =>
      try
        conversation = @messageRouter.getConversation(req.params.id)
        res.json(conversation || { error: 'Conversation not found' })
      catch error
        console.error 'History API error:', error
        res.status(500).json({ error: error.message })

    @app.get '/api/models', (req, res) =>
      try
        alphaInfo = await @llmAlpha.getModelInfo()
        betaInfo  = await @llmBeta.getModelInfo()
        res.json({ alpha: alphaInfo, beta: betaInfo })
      catch error
        console.error 'Models API error:', error
        res.status(500).json({ error: error.message })

    @app.post '/api/neo4j/query', (req, res) =>
      try
        { query, parameters = {} } = req.body
        result = await @neo4jTool.executeQuery(query, parameters)
        res.json(result)
      catch error
        console.error 'Neo4j API error:', error
        res.status(500).json({ error: error.message })

    @app.get '/', (req, res) ->
      res.sendFile path.join(__dirname, '../public/index.html')

    @app.get '/health', (req, res) =>
      try
        alphaHealth = await @llmAlpha.healthCheck()
        betaHealth  = await @llmBeta.healthCheck()

        res.json {
          status:    'ok'
          timestamp: isoDateString()
          services:
            alpha: alphaHealth.status
            beta:  betaHealth.status
            neo4j: 'connected'  # TODO: actual health check
        }
      catch error
        res.status(500).json {
          status:    'error'
          error:     error.message
          timestamp: isoDateString()
        }

  setupWebSockets: ->
    @io.on 'connection', (socket) =>
      console.log 'User connected:', socket.id

      socket.on 'message_send',         (data) => @handleUserMessage         socket, data
      socket.on 'orchestration_change', (data) => @handleOrchestrationChange socket, data
      socket.on 'neo4j_query',          (data) => @handleNeo4jQuery          socket, data
      socket.on 'model_interrupt',      (data) => @handleModelInterrupt      socket, data
      socket.on 'load_character',       (data) => @handleLoadCharacter       socket, data
      socket.on 'reset_roleplay',       (data) => @handleResetRoleplay       socket, data
      socket.on 'disconnect',                  -> console.log 'User disconnected:', socket.id

  handleUserMessage: (socket, data) ->
    try
      { message, mode = 'parallel', conversationId, isOOC } = data

      console.log "Processing message: #{message} in mode: #{mode}#{if isOOC then ' (OOC)' else ''}"

      options = {}
      options.isOOC = isOOC if mode is 'roleplay'

      result = await @messageRouter.processMessage(message, mode, conversationId, options)

      console.log "Result from message router:", {
        hasAlpha:     !!result.alphaResponse
        hasBeta:      !!result.betaResponse
        hasSynthesis: !!result.synthesis
        alphaType:    typeof result.alphaResponse
        betaType:     typeof result.betaResponse
      }

      # Clear thinking indicators for non-responding brains in handoff mode
      if mode is 'handoff'
        socket.emit 'clear_alpha_thinking' unless result.alphaResponse
        socket.emit 'clear_beta_thinking'  unless result.betaResponse

      # Emit Alpha response
      if result.alphaResponse
        alphaContent = @extractContent(result.alphaResponse)
        console.log "Sending alpha response:", alphaContent?.substring(0, 100) + "..."

        socket.emit 'alpha_response', {
          content:   alphaContent
          timestamp: isoDateString()
          model:     @llmAlpha.model
        }

      # Emit Beta response
      if result.betaResponse
        betaContent = @extractContent(result.betaResponse)
        console.log "Beta response object:", JSON.stringify(result.betaResponse, null, 2)
        console.log "Beta content extracted:", betaContent?.substring(0, 100) + "..."

        socket.emit 'beta_response', {
          content:   betaContent
          timestamp: isoDateString()
          model:     @llmBeta.model
        }

      # Emit synthesis if present
      if result.synthesis
        synthesisContent = @extractContent(result.synthesis)
        console.log "Sending synthesis:", synthesisContent?.substring(0, 100) + "..."

        socket.emit 'synthesis_complete', {
          content:   synthesisContent
          timestamp: isoDateString()
          mode:      mode
        }

      # Emit IC response for roleplay mode
      if result.icResponse
        console.log "Sending IC response from #{result.character}: #{result.icResponse?.substring(0, 100)}..."
        socket.emit 'ic_response', {
          content:   result.icResponse
          character: result.character
          timestamp: isoDateString()
          isOOC:     result.isOOC
        }

      # Emit corpus callosum communications
      if result.communications
        for comm in result.communications
          socket.emit 'corpus_communication', comm

      # Signal completion for non-synthesis modes
      if mode in ['parallel', 'handoff', 'sequential'] and not result.synthesis
        socket.emit 'interaction_complete', {
          mode:    mode
          primary: result.primary  # For handoff mode
        }

    catch error
      console.error 'Error handling user message:', error
      socket.emit 'error', { message: error.message }

  handleOrchestrationChange: (socket, data) ->
    try
      { mode, parameters } = data
      @corpusCallosum.setMode(mode, parameters)
      socket.emit 'orchestration_changed', { mode, parameters }
    catch error
      console.error 'Error changing orchestration:', error
      socket.emit 'error', { message: error.message }

  handleNeo4jQuery: (socket, data) ->
    try
      { query, parameters = {} } = data
      result = await @neo4jTool.executeQuery(query, parameters)
      socket.emit 'neo4j_result', result
    catch error
      console.error 'Error executing Neo4j query:', error
      socket.emit 'error', { message: error.message }

  handleModelInterrupt: (socket, data) ->
    try
      @messageRouter.interrupt()
      socket.emit 'models_interrupted'
    catch error
      console.error 'Error interrupting models:', error
      socket.emit 'error', { message: error.message }

  handleLoadCharacter: (socket, characterCard) ->
    try
      characterInfo = @messageRouter.loadCharacter(characterCard)
      socket.emit 'character_loaded', characterInfo
      console.log "Character loaded: #{characterInfo.name}"
    catch error
      console.error 'Error loading character:', error
      socket.emit 'error', { message: error.message }

  handleResetRoleplay: (socket, data) ->
    try
      firstMessage = @messageRouter.resetRoleplay()
      socket.emit 'roleplay_reset', { first_mes: firstMessage }
      console.log "Roleplay conversation reset"
    catch error
      console.error 'Error resetting roleplay:', error
      socket.emit 'error', { message: error.message }

  extractContent: (response) ->
    if typeof response is 'string' then response else response.content

  setupErrorHandling: ->
    @app.use (error, req, res, next) ->
      console.error 'Unhandled error:', error

      res.status(500).json {
        error:   'Internal server error'
        message: if process.env.NODE_ENV is 'development' then error.message else 'Something went wrong'
      }

    process.on 'uncaughtException', (error) ->
      console.error 'Uncaught Exception:', error
      process.exit 1

    process.on 'unhandledRejection', (reason, promise) ->
      console.error 'Unhandled Rejection at:', promise, 'reason:', reason
      process.exit 1

  start: ->
    @server.listen @port, =>
      console.log """
        🧠 Dual-LLM Chat System Started 🧠
        Port:        #{@port}
        Environment: #{process.env.NODE_ENV || 'development'}
        Alpha Model: #{@llmAlpha.model}
        Beta Model:  #{@llmBeta.model}
        Neo4j:       #{process.env.NEO4J_URI || 'bolt://localhost:7687'}
        Ollama:      #{process.env.OLLAMA_HOST || 'localhost:11434'}
      """

# Start the application
startApp = ->
  app = new DualLLMApp()
  await app.initialize()
  app.start()

startApp().catch (error) ->
  console.error 'Failed to start ClodBrain:', error
  process.exit 1

module.exports = DualLLMApp
