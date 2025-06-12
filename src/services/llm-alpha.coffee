# LLM Alpha Service - Analytical "Left Brain"
axios = require 'axios'

class LLMAlpha
  constructor: (@config, @ollamaConfig, @neo4jTool = null) ->
    @model = @config.model
    @role = @config.role
    @personality = @config.personality
    @systemPrompt = @config.system_prompt
    @baseUrl = "#{@ollamaConfig.host}/api"
    @timeout = @ollamaConfig.timeout || 30000
    
    console.log "Initialized LLM Alpha with model: #{@model}"

  processMessage: (message, context = null) ->
    try
      # Check if message contains graph queries
      graphContext = await @handleGraphQueries(message)
      
      # Build the prompt with system context and graph data
      prompt = @buildPrompt(message, context, graphContext)
      
      # Make request to Ollama
      response = await @makeOllamaRequest(prompt)
      
      # Parse response and handle any graph operations
      parsedResponse = @parseResponse(response)
      await @handleGraphOperations(parsedResponse, message)
      
      return parsedResponse
      
    catch error
      console.error 'LLM Alpha processing error:', error
      throw new Error("Alpha processing failed: #{error.message}")

  buildPrompt: (message, context, graphContext = null) ->
    promptParts = [@systemPrompt]
    
    # Add graph access instructions
    if @neo4jTool
      promptParts.push '''
        You have access to a knowledge graph database. You can:
        
        QUERY: Use GRAPH_QUERY: followed by a natural language question to search the graph
        Examples: 
        - GRAPH_QUERY: What conversations have we had?
        - GRAPH_QUERY: What entities have been mentioned?
        - GRAPH_QUERY: Show me concepts we've discussed
        
        STORE: Use GRAPH_STORE: followed by entities/facts to save to the graph
        Examples:
        - GRAPH_STORE: Entity: Claude, Type: AI Assistant, Confidence: 0.9
        - GRAPH_STORE: Concept: Machine Learning, Domain: Technology
        
        Use these capabilities to provide more informed, contextual responses.
      '''
    
    if graphContext
      promptParts.push "Graph Context: #{graphContext}"
    
    if context
      if typeof context is 'string'
        promptParts.push "Context: #{context}"
      else if context.alpha or context.beta
        promptParts.push "Previous Alpha: #{context.alpha || 'None'}"
        promptParts.push "Previous Beta: #{context.beta || 'None'}"
      else
        promptParts.push "Context: #{JSON.stringify(context)}"
    
    promptParts.push "User: #{message}"
    promptParts.push "Alpha:"
    
    return promptParts.join('\n\n')

  makeOllamaRequest: (prompt) ->
    requestData = {
      model: @model
      prompt: prompt
      stream: false
      options: {
        temperature: @config.temperature
        top_p: @config.top_p
        num_predict: @config.max_tokens
      }
    }
    
    try
      response = await axios.post "#{@baseUrl}/generate", requestData, {
        timeout: @timeout
        headers: {
          'Content-Type': 'application/json'
        }
      }
      
      if response.data?.response
        return response.data.response
      else
        throw new Error('Invalid response format from Ollama')
        
    catch error
      if error.code is 'ECONNREFUSED'
        throw new Error('Cannot connect to Ollama. Is it running?')
      else if error.response?.status is 404
        throw new Error("Model #{@model} not found. Please pull it first.")
      else
        throw error

  parseResponse: (response) ->
    # Look for communication patterns with Beta
    betaCommunication = @extractBetaCommunication(response)
    
    # Clean the response by removing internal communication markers
    cleanResponse = @cleanResponse(response)
    
    return {
      content: cleanResponse
      betaCommunication: betaCommunication
      model: @model
      role: @role
      timestamp: new Date().toISOString()
    }

  extractBetaCommunication: (response) ->
    # Look for ALPHA_TO_BETA: patterns
    betaPattern = /ALPHA_TO_BETA:\s*(.+?)(?=\n|$)/gi
    matches = []
    
    match = betaPattern.exec(response)
    while match isnt null
      matches.push {
        type: 'to_beta'
        content: match[1].trim()
        timestamp: Date.now()
      }
      match = betaPattern.exec(response)
    
    return matches

  # Handle graph queries in the user message
  handleGraphQueries: (message) ->
    return null unless @neo4jTool
    
    # Look for requests about previous conversations, entities, etc.
    lowerMessage = message.toLowerCase()
    graphContext = []
    
    if lowerMessage.includes('previous') or lowerMessage.includes('before') or lowerMessage.includes('earlier')
      try
        conversations = await @neo4jTool.naturalLanguageQuery('conversations')
        if conversations.records?.length > 0
          graphContext.push "Recent conversations: #{conversations.records.length} found"
      catch error
        console.error 'Graph query error:', error
    
    if lowerMessage.includes('entities') or lowerMessage.includes('mentioned')
      try
        entities = await @neo4jTool.naturalLanguageQuery('entities')
        if entities.records?.length > 0
          entityNames = entities.records.map((r) -> r.name).slice(0, 5)
          graphContext.push "Known entities: #{entityNames.join(', ')}"
      catch error
        console.error 'Graph query error:', error
    
    return if graphContext.length > 0 then graphContext.join('; ') else null

  # Handle graph operations in the response
  handleGraphOperations: (parsedResponse, originalMessage) ->
    return unless @neo4jTool and parsedResponse.content
    
    # Look for GRAPH_QUERY: patterns
    graphQueries = @extractGraphQueries(parsedResponse.content)
    for query in graphQueries
      try
        result = await @neo4jTool.naturalLanguageQuery(query)
        console.log "Alpha executed graph query: #{query}"
      catch error
        console.error "Alpha graph query failed:", error
    
    # Look for GRAPH_STORE: patterns  
    graphStores = @extractGraphStores(parsedResponse.content)
    for store in graphStores
      try
        await @storeToGraph(store)
        console.log "Alpha stored to graph: #{store}"
      catch error
        console.error "Alpha graph store failed:", error

  extractGraphQueries: (content) ->
    queryPattern = /GRAPH_QUERY:\s*(.+?)(?=\n|$)/gi
    matches = []
    match = queryPattern.exec(content)
    while match isnt null
      matches.push match[1].trim()
      match = queryPattern.exec(content)
    return matches

  extractGraphStores: (content) ->
    storePattern = /GRAPH_STORE:\s*(.+?)(?=\n|$)/gi
    matches = []
    match = storePattern.exec(content)
    while match isnt null
      matches.push match[1].trim()
      match = storePattern.exec(content)
    return matches

  storeToGraph: (storeCommand) ->
    # Parse store commands like "Entity: Claude, Type: AI Assistant, Confidence: 0.9"
    if storeCommand.toLowerCase().startsWith('entity:')
      parts = storeCommand.substring(7).split(',').map((s) -> s.trim())
      entityData = { name: parts[0] }
      
      for part in parts.slice(1)
        [key, value] = part.split(':').map((s) -> s.trim())
        if key and value
          entityData[key.toLowerCase()] = value
      
      await @neo4jTool.addKnowledge([entityData], [])
      
    else if storeCommand.toLowerCase().startsWith('concept:')
      parts = storeCommand.substring(8).split(',').map((s) -> s.trim())
      conceptData = { name: parts[0], type: 'concept' }
      
      for part in parts.slice(1)
        [key, value] = part.split(':').map((s) -> s.trim())
        if key and value
          conceptData[key.toLowerCase()] = value
      
      # Store as entity for now (could extend for proper concept storage)
      await @neo4jTool.addKnowledge([conceptData], [])

  cleanResponse: (response) ->
    # Remove internal communication markers and graph commands
    cleaned = response.replace(/ALPHA_TO_BETA:\s*.+?(?=\n|$)/gi, '')
    cleaned = cleaned.replace(/GRAPH_QUERY:\s*.+?(?=\n|$)/gi, '')
    cleaned = cleaned.replace(/GRAPH_STORE:\s*.+?(?=\n|$)/gi, '')
    
    # Clean up extra whitespace
    cleaned = cleaned.replace(/\n\s*\n/g, '\n').trim()
    
    return cleaned
    # Format communication for Beta
    communication = {
      from: 'alpha'
      to: 'beta'
      content: message
      intent: intent
      timestamp: Date.now()
    }
    
    return communication

  generateResponse: (userInput, betaInput = null) ->
    # Main entry point for generating responses
    context = if betaInput then { beta: betaInput } else null
    return await @processMessage(userInput, context)

  # Analytical processing methods
  analyzeText: (text) ->
    analysisPrompt = """
    Analyze the following text from an analytical perspective:
    - Break down key components
    - Identify logical structure
    - Fact-check claims where possible
    - Suggest areas needing verification
    
    Text: #{text}
    """
    
    return await @processMessage(analysisPrompt)

  breakDownProblem: (problem) ->
    breakdownPrompt = """
    Break down this problem into logical steps:
    - Identify the core question
    - List required information
    - Outline solution approach
    - Identify potential obstacles
    
    Problem: #{problem}
    """
    
    return await @processMessage(breakdownPrompt)

  verifyFacts: (claims) ->
    verificationPrompt = """
    Verify these claims using logical reasoning:
    - Assess plausibility
    - Identify what can be verified
    - Note areas requiring external verification
    - Suggest reliable sources
    
    Claims: #{claims}
    """
    
    return await @processMessage(verificationPrompt)

  # Health check method
  healthCheck: ->
    try
      testResponse = await @makeOllamaRequest("Respond with 'OK' if you're working properly.")
      return {
        status: 'healthy'
        model: @model
        response: testResponse
        timestamp: new Date().toISOString()
      }
    catch error
      return {
        status: 'unhealthy'
        model: @model
        error: error.message
        timestamp: new Date().toISOString()
      }

  # Get model information
  getModelInfo: ->
    try
      response = await axios.get "#{@baseUrl}/tags"
      models = response.data?.models || []
      currentModel = models.find (m) => m.name is @model
      
      return {
        model: @model
        role: @role
        personality: @personality
        available: currentModel?
        details: currentModel
        config: {
          temperature: @config.temperature
          max_tokens: @config.max_tokens
          top_p: @config.top_p
        }
      }
    catch error
      return {
        model: @model
        role: @role
        available: false
        error: error.message
      }

module.exports = LLMAlpha