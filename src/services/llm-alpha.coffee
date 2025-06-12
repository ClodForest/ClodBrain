# LLM Alpha Service - Analytical "Left Brain"
BaseLLM = require './base-llm'

class LLMAlpha extends BaseLLM
  # Override to get Alpha-specific communication pattern
  getCommunicationPattern: ->
    /ALPHA_TO_BETA:\s*.+?(?=\n|$)/gi

  # Override to extract Alpha-specific communications
  extractCommunication: (response) ->
    # Look for ALPHA_TO_BETA: patterns
    alphaPattern = /ALPHA_TO_BETA:\s*(.+?)(?=\n|$)/gi
    matches = []
    
    match = alphaPattern.exec(response)
    while match isnt null
      matches.push {
        type: 'to_beta'
        content: match[1].trim()
        timestamp: Date.now()
      }
      match = alphaPattern.exec(response)
    
    return matches

  # Override to specify Beta as the other brain
  getOtherBrainKey: ->
    'beta'

  # Alpha-specific analytical methods
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

  # Override parseResponse to handle Alpha-specific fields
  parseResponse: (response) ->
    # Call parent parseResponse
    parsed = super(response)
    
    # Add Alpha-specific field names for compatibility
    if parsed.communication?.length > 0
      parsed.betaCommunication = parsed.communication
    
    return parsed

module.exports = LLMAlpha