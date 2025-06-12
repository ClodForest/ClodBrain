# LLM Alpha Service - Analytical "Left Brain"
axios = require 'axios'

class LLMAlpha
  constructor: (@config, @ollamaConfig) ->
    @model = @config.model
    @role = @config.role
    @personality = @config.personality
    @systemPrompt = @config.system_prompt
    @baseUrl = "#{@ollamaConfig.host}/api"
    @timeout = @ollamaConfig.timeout || 30000
    
    console.log "Initialized LLM Alpha with model: #{@model}"

  processMessage: (message, context = null) ->
    try
      # Build the prompt with system context
      prompt = @buildPrompt(message, context)
      
      # Make request to Ollama
      response = await @makeOllamaRequest(prompt)
      
      # Parse and return response
      return @parseResponse(response)
      
    catch error
      console.error 'LLM Alpha processing error:', error
      throw new Error("Alpha processing failed: #{error.message}")

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

  cleanResponse: (response) ->
    # Remove internal communication markers
    cleaned = response.replace(/ALPHA_TO_BETA:\s*.+?(?=\n|$)/gi, '')
    
    # Clean up extra whitespace
    cleaned = cleaned.replace(/\n\s*\n/g, '\n').trim()
    
    return cleaned

  communicateWithBeta: (message, intent = 'general') ->
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