# LLM Beta Service - Creative "Right Brain"
axios = require 'axios'

class LLMBeta
  constructor: (@config, @ollamaConfig) ->
    @model = @config.model
    @role = @config.role
    @personality = @config.personality
    @systemPrompt = @config.system_prompt
    @baseUrl = "#{@ollamaConfig.host}/api"
    @timeout = @ollamaConfig.timeout || 30000
    
    console.log "Initialized LLM Beta with model: #{@model}"

  processMessage: (message, context = null) ->
    try
      # Build the prompt with system context
      prompt = @buildPrompt(message, context)
      
      # Make request to Ollama
      response = await @makeOllamaRequest(prompt)
      
      # Parse and return response
      return @parseResponse(response)
      
    catch error
      console.error 'LLM Beta processing error:', error
      throw new Error("Beta processing failed: #{error.message}")

  buildPrompt: (message, context) ->
    promptParts = [@systemPrompt]
    
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
    # Remove internal communication markers
    cleaned = response.replace(/BETA_TO_ALPHA:\s*.+?(?=\n|$)/gi, '')
    
    # Clean up extra whitespace
    cleaned = cleaned.replace(/\n\s*\n/g, '\n').trim()
    
    return cleaned

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