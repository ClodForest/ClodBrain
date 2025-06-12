# LLM Beta Service - Creative "Right Brain"
BaseLLM = require './base-llm'

class LLMBeta extends BaseLLM
  # Override to get Beta-specific communication pattern
  getCommunicationPattern: ->
    /BETA_TO_ALPHA:\s*.+?(?=\n|$)/gi

  # Override to extract Beta-specific communications
  extractCommunication: (response) ->
    # Look for BETA_TO_ALPHA: patterns
    betaPattern = /BETA_TO_ALPHA:\s*(.+?)(?=\n|$)/gi
    matches = []
    
    match = betaPattern.exec(response)
    while match isnt null
      matches.push {
        type: 'to_alpha'
        content: match[1].trim()
        timestamp: Date.now()
      }
      match = betaPattern.exec(response)
    
    return matches

  # Override to specify Alpha as the other brain
  getOtherBrainKey: ->
    'alpha'

  # Beta-specific creative methods
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

  # Override parseResponse to handle Beta-specific fields
  parseResponse: (response) ->
    # Call parent parseResponse
    parsed = super(response)
    
    # Add Beta-specific field names for compatibility
    if parsed.communication?.length > 0
      parsed.alphaCommunication = parsed.communication
    
    return parsed

  # Override healthCheck to return Beta-specific response
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

module.exports = LLMBeta