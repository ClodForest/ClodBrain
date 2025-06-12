# Main Express application
express = require 'express'
http = require 'http'
socketIo = require 'socket.io'
path = require 'path'
require 'dotenv/config'

# Import our services
LLMAlpha = require './services/llm-alpha'
LLMBeta = require './services/llm-beta'
CorpusCallosum = require './services/corpus-callosum'
Neo4jTool = require './services/neo4j-tool'
MessageRouter = require './services/message-router'

# Import configurations
databaseConfig = require './config/database'
ollamaConfig = require './config/ollama'
modelsConfig = require './config/models'

class DualLLMApp
  constructor: ->
    @app = express()
    @server = http.createServer(@app)
    @io = socketIo(@server, {
      cors:
        origin: "*"
        methods: ["GET", "POST"]
    })
    @port = process.env.PORT || 3000

  initialize: ->
    # Initialize services
    await @initializeServices()
    @setupMiddleware()
    @setupRoutes()
    @setupWebSockets()
    @setupErrorHandling()

  initializeServices: ->
    console.log 'Initializing services...'

    # Initialize Neo4j connection
    @neo4jTool = new Neo4jTool(databaseConfig)
    await @neo4jTool.connect()  # Ensure connection is established

    # Initialize LLM services with Neo4j access
    @llmAlpha = new LLMAlpha(modelsConfig.alpha, ollamaConfig, @neo4jTool)
    @llmBeta = new LLMBeta(modelsConfig.beta, ollamaConfig, @neo4jTool)

    # Initialize corpus callosum (communication layer)
    @corpusCallosum = new CorpusCallosum(@llmAlpha, @llmBeta, modelsConfig.corpus_callosum)

    # Initialize message router
    @messageRouter = new MessageRouter(@corpusCallosum, @neo4jTool)

  setupMiddleware: ->
    # Basic CORS handling (replacing cors middleware)
    @app.use (req, res, next) ->
      res.header 'Access-Control-Allow-Origin', '*'
      res.header 'Access-Control-Allow-Methods', 'GET,PUT,POST,DELETE,OPTIONS'
      res.header 'Access-Control-Allow-Headers', 'Content-Type, Authorization, Content-Length, X-Requested-With'

      if req.method is 'OPTIONS'
        res.sendStatus 200
      else
        next()

    # Basic security headers (replacing helmet)
    @app.use (req, res, next) ->
      res.setHeader 'X-Content-Type-Options', 'nosniff'
      res.setHeader 'X-Frame-Options', 'DENY'
      res.setHeader 'X-XSS-Protection', '1; mode=block'
      next()

    # Request logging (replacing winston)
    @app.use (req, res, next) ->
      timestamp = new Date().toISOString()
      console.log "#{timestamp} #{req.method} #{req.url}"
      next()

    @app.use express.json({ limit: '10mb' })
    @app.use express.urlencoded({ extended: true })

    # Serve static files
    @app.use express.static(path.join(__dirname, '../public'))

    # Make services available to routes
    @app.locals.messageRouter = @messageRouter
    @app.locals.neo4jTool = @neo4jTool
    @app.locals.corpusCallosum = @corpusCallosum

  setupRoutes: ->
    # API routes (inline instead of separate controllers for now)
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
        betaInfo = await @llmBeta.getModelInfo()
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

    # Serve main page
    @app.get '/', (req, res) ->
      res.sendFile path.join(__dirname, '../public/index.html')

    # Health check
    @app.get '/health', (req, res) =>
      try
        alphaHealth = await @llmAlpha.healthCheck()
        betaHealth = await @llmBeta.healthCheck()
        res.json {
          status: 'ok'
          timestamp: new Date().toISOString()
          services:
            alpha: alphaHealth.status
            beta: betaHealth.status
            neo4j: 'connected'  # TODO: actual health check
        }
      catch error
        res.status(500).json {
          status: 'error'
          error: error.message
          timestamp: new Date().toISOString()
        }

  setupWebSockets: ->
    @io.on 'connection', (socket) =>
      console.log 'User connected:', socket.id

      # Handle user messages
      socket.on 'message_send', (data) =>
        @handleUserMessage(socket, data)

      # Handle orchestration changes
      socket.on 'orchestration_change', (data) =>
        @handleOrchestrationChange(socket, data)

      # Handle Neo4j queries
      socket.on 'neo4j_query', (data) =>
        @handleNeo4jQuery(socket, data)

      # Handle model interrupts
      socket.on 'model_interrupt', (data) =>
        @handleModelInterrupt(socket, data)

      socket.on 'disconnect', ->
        console.log 'User disconnected:', socket.id

  handleUserMessage: (socket, data) ->
    try
      { message, mode = 'parallel', conversationId } = data

      console.log "Processing message: #{message} in mode: #{mode}"

      # Process message through message router
      result = await @messageRouter.processMessage(message, mode, conversationId)

      console.log "Result from message router:", {
        hasAlpha: !!result.alphaResponse
        hasBeta: !!result.betaResponse
        hasSynthesis: !!result.synthesis
        alphaType: typeof result.alphaResponse
        betaType: typeof result.betaResponse
      }

      # For handoff mode, clear the thinking indicator for the brain that didn't respond
      if mode is 'handoff'
        if result.primary
          # In handoff mode, only one brain is primary
          if result.primary is 'alpha' and not result.betaResponse
            socket.emit 'clear_beta_thinking'
          else if result.primary is 'beta' and not result.alphaResponse
            socket.emit 'clear_alpha_thinking'

      # Emit responses as they come in
      if result.alphaResponse
        alphaContent = if typeof result.alphaResponse is 'string' then result.alphaResponse else result.alphaResponse.content
        console.log "Sending alpha response:", alphaContent?.substring(0, 100) + "..."
        socket.emit 'alpha_response', {
          content: alphaContent
          timestamp: new Date().toISOString()
          model: @llmAlpha.model
        }

      if result.betaResponse
        betaContent = if typeof result.betaResponse is 'string' then result.betaResponse else result.betaResponse.content
        console.log "Beta response object:", JSON.stringify(result.betaResponse, null, 2)
        console.log "Beta content extracted:", betaContent?.substring(0, 100) + "..."
        socket.emit 'beta_response', {
          content: betaContent
          timestamp: new Date().toISOString()
          model: @llmBeta.model
        }

      if result.synthesis
        synthesisContent = if typeof result.synthesis is 'string' then result.synthesis else result.synthesis.content
        console.log "Sending synthesis:", synthesisContent?.substring(0, 100) + "..."
        socket.emit 'synthesis_complete', {
          content: synthesisContent
          timestamp: new Date().toISOString()
          mode: mode
        }

      # Emit any corpus callosum communications
      if result.communications
        for comm in result.communications
          socket.emit 'corpus_communication', comm

      # For modes that don't have synthesis, signal completion
      if mode in ['parallel', 'handoff', 'sequential'] and not result.synthesis
        socket.emit 'interaction_complete', {
          mode: mode
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

  setupErrorHandling: ->
    # Global error handler (replacing dedicated error handler middleware)
    @app.use (error, req, res, next) ->
      console.error 'Unhandled error:', error
      res.status(500).json {
        error: 'Internal server error'
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
      Port: #{@port}
      Environment: #{process.env.NODE_ENV || 'development'}
      Alpha Model: #{@llmAlpha.model}
      Beta Model: #{@llmBeta.model}
      Neo4j: #{process.env.NEO4J_URI || 'bolt://localhost:7687'}
      Ollama: #{process.env.OLLAMA_HOST || 'localhost:11434'}
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