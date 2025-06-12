# Main Express application
express = require 'express'
http = require 'http'
socketIo = require 'socket.io'
path = require 'path'
cors = require 'cors'
helmet = require 'helmet'
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

# Import middleware
loggingMiddleware = require './middleware/logging'
errorHandler = require './middleware/error-handler'

# Import controllers
chatController = require './controllers/chat'
modelsController = require './controllers/models'
neo4jController = require './controllers/neo4j'

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
    
    # Initialize services
    @initializeServices()
    @setupMiddleware()
    @setupRoutes()
    @setupWebSockets()
    @setupErrorHandling()

  initializeServices: ->
    console.log 'Initializing services...'
    
    # Initialize Neo4j connection
    @neo4jTool = new Neo4jTool(databaseConfig)
    
    # Initialize LLM services
    @llmAlpha = new LLMAlpha(modelsConfig.alpha, ollamaConfig)
    @llmBeta = new LLMBeta(modelsConfig.beta, ollamaConfig)
    
    # Initialize corpus callosum (communication layer)
    @corpusCallosum = new CorpusCallosum(@llmAlpha, @llmBeta, modelsConfig.corpus_callosum)
    
    # Initialize message router
    @messageRouter = new MessageRouter(@corpusCallosum, @neo4jTool)

  setupMiddleware: ->
    @app.use helmet()
    @app.use cors()
    @app.use express.json({ limit: '10mb' })
    @app.use express.urlencoded({ extended: true })
    @app.use loggingMiddleware
    
    # Serve static files
    @app.use express.static(path.join(__dirname, '../public'))
    
    # Make services available to routes
    @app.locals.messageRouter = @messageRouter
    @app.locals.neo4jTool = @neo4jTool
    @app.locals.corpusCallosum = @corpusCallosum

  setupRoutes: ->
    # API routes
    @app.use '/api/chat', chatController
    @app.use '/api/models', modelsController
    @app.use '/api/neo4j', neo4jController
    
    # Serve main page
    @app.get '/', (req, res) ->
      res.sendFile path.join(__dirname, '../public/index.html')
    
    # Health check
    @app.get '/health', (req, res) ->
      res.json {
        status: 'ok'
        timestamp: new Date().toISOString()
        services:
          neo4j: 'connected'  # TODO: actual health check
          ollama: 'connected'  # TODO: actual health check
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
      
      # Process message through message router
      result = await @messageRouter.processMessage(message, mode, conversationId)
      
      # Emit responses as they come in
      if result.alphaResponse
        socket.emit 'alpha_response', {
          content: result.alphaResponse
          timestamp: new Date().toISOString()
          model: @llmAlpha.model
        }
      
      if result.betaResponse
        socket.emit 'beta_response', {
          content: result.betaResponse
          timestamp: new Date().toISOString()
          model: @llmBeta.model
        }
      
      if result.synthesis
        socket.emit 'synthesis_complete', {
          content: result.synthesis
          timestamp: new Date().toISOString()
          mode: mode
        }
      
      # Emit any corpus callosum communications
      if result.communications
        for comm in result.communications
          socket.emit 'corpus_communication', comm
          
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
      # TODO: Implement model interruption logic
      @messageRouter.interrupt()
      socket.emit 'models_interrupted'
    catch error
      console.error 'Error interrupting models:', error
      socket.emit 'error', { message: error.message }

  setupErrorHandling: ->
    @app.use errorHandler
    
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
app = new DualLLMApp()
app.start()

module.exports = app