# LLM Beta Service - Creative "Right Brain"
axios = require 'axios'

class LLMBeta
  constructor: (@config, @ollamaConfig, @neo4jTool = null) ->
    @model = @config.model
    @role = @config.role
    @personality = @config.personality
    @systemPrompt = @config.system_prompt
    @baseUrl = "#{@ollamaConfig.host}/api"
    @timeout = @ollamaConfig.timeout || 30000
    
    console.log "Initialized LLM Beta with model: #{@model}"

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
      console.error 'LLM Beta processing error:', error
      throw new Error("Beta processing failed: #{error.message}")

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
        
        Use these capabilities creatively to provide more insightful, connected responses.
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
    promptParts.push "Beta:"
    
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
    # Look for communication patterns with Alpha
    alphaCommunication = @extractAlphaCommunication(response)
    
    # Clean the response by removing internal communication markers
    cleanResponse = @cleanResponse(response)
    
    return {
      content: cleanResponse
      alphaCommunication: alphaCommunication
      model: @model
      role: @role
      timestamp: new Date().toISOString()
    }

  extractAlphaCommunication: (response) ->
    # Look for BETA_TO_ALPHA: patterns
    alphaPattern = /BETA_TO_ALPHA:\s*(.+?)(?=\n|$)/gi
    matches = []
    
    match = alphaPattern.exec(response)
    while match isnt null
      matches.push {
        type: 'to_alpha'
        content: match[1].trim()
        timestamp: Date.now()
      }
      match = alphaPattern.exec(response)
    
    return matches

  cleanResponse: (response) ->
    # Remove internal communication markers and graph commands
    cleaned = response.replace(/BETA_TO_ALPHA:\s*.+?(?=\n|$)/gi, '')
    cleaned = cleaned.replace(/GRAPH_QUERY:\s*.+?(?=\n|$)/gi, '')
    cleaned = cleaned.replace(/GRAPH_STORE:\s*.+?(?=\n|$)/gi, '')
    
    # Clean up extra whitespace
    cleaned = cleaned.replace(/\n\s*\n/g, '\n').trim()
    
    return cleaned

  # Copy the graph handling methods from Alpha (same implementation)
  handleGraphQueries: (message) ->
    return null unless @neo4jTool
    
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

  handleGraphOperations: (parsedResponse, originalMessage) ->
    return unless @neo4jTool and parsedResponse.content
    
    graphQueries = @extractGraphQueries(parsedResponse.content)
    for query in graphQueries
      try
        result = await @neo4jTool.naturalLanguageQuery(query)
        console.log "Beta executed graph query: #{query}"
      catch error
        console.error "Beta graph query failed:", error
    
    graphStores = @extractGraphStores(parsedResponse.content)
    for store in graphStores
      try
        await @storeToGraph(store)
        console.log "Beta stored to graph: #{store}"
      catch error
        console.error "Beta graph store failed:", error

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
      
      await @neo4jTool.addKnowledge([conceptData], [])

  communicateWithAlpha: (message, intent = 'general') ->
    # Format communication for Alpha
    communication = {
      from: 'beta'
      to: 'alpha'
      content: message
      intent: intent
      timestamp: Date.now()
    }
    
    return communication

  generateResponse: (userInput, alphaInput = null) ->
    # Main entry point for generating responses
    context = if alphaInput then { alpha: alphaInput } else null
    return await @processMessage(userInput, context)

  # Creative processing methods
  brainstormIdeas: (topic) ->
    brainstormPrompt = """
    Brainstorm creative ideas for: #{topic}
    - Think outside the box
    - Consider unconventional approaches
    - Generate multiple perspectives
    - Focus on innovation and creativity
    """
    
    return await @processMessage(brainstormPrompt)

  findPatterns: (data) ->
    patternPrompt = """
    Analyze this data for creative patterns and insights:
    - Look for hidden connections
    - Identify unusual correlations
    - Suggest creative interpretations
    - Think about implications
    
    Data: #{data}
    """
    
    return await @processMessage(patternPrompt)

  generateAlternatives: (problem, currentSolution) ->
    alternativePrompt = """
    Given this problem and current solution, generate creative alternatives:
    
    Problem: #{problem}
    Current Solution: #{currentSolution}
    
    - Think of completely different approaches
    - Consider what others might miss
    - Explore unconventional methods
    - Focus on innovative solutions
    """
    
    return await @processMessage(alternativePrompt)

  synthesizeIdeas: (ideas) ->
    synthesisPrompt = """
    Synthesize these ideas into novel combinations:
    #{if Array.isArray(ideas) then ideas.join('\n') else ideas}
    
    - Find unexpected connections
    - Create hybrid approaches
    - Generate emergent concepts
    - Think about synergies
    """
    
    return await @processMessage(synthesisPrompt)

  # Health check method
  healthCheck: ->
    try
      testResponse = await @makeOllamaRequest("Respond with 'CREATIVE' if you're working properly.")
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

module.exports = LLMBeta