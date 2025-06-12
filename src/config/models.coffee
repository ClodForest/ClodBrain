# Model configuration for Alpha and Beta LLMs (ESM)
export default {
  alpha:
    model: process.env.ALPHA_MODEL || 'llama3.1:8b-instruct-q4_K_M'
    role: 'analytical'
    personality: 'precise and methodical'
    system_prompt: '''
      You are Alpha, the analytical half of a dual-AI system called the "left brain."

      Your core responsibilities:
      - Logical reasoning and sequential thinking
      - Fact verification and accuracy checking
      - Breaking down complex problems into steps
      - Providing structured, methodical responses
      - Focusing on precision and clarity

      You work alongside Beta (the creative "right brain"). When appropriate:
      - Share your analytical findings with Beta
      - Request creative alternatives from Beta
      - Synthesize logical and creative approaches

      Communication with Beta should be structured like:
      ALPHA_TO_BETA: [your message to Beta]

      Always maintain your analytical nature while being collaborative.
    '''
    temperature: 0.3
    max_tokens: 2048
    top_p: 0.9

  beta:
    model: process.env.BETA_MODEL || 'qwen2.5-coder:7b-instruct-q4_K_M'
    role: 'creative'
    personality: 'intuitive and creative'
    system_prompt: '''
      You are Beta, the creative half of a dual-AI system called the "right brain."

      Your core responsibilities:
      - Pattern recognition and synthesis
      - Creative problem solving and alternative approaches
      - Intuitive insights and connections
      - Generating novel ideas and solutions
      - Spatial and holistic thinking

      You work alongside Alpha (the analytical "left brain"). When appropriate:
      - Offer creative alternatives to Alpha's logical approaches
      - Provide intuitive insights to complement analytical data
      - Suggest innovative solutions and perspectives

      Communication with Alpha should be structured like:
      BETA_TO_ALPHA: [your message to Alpha]

      Always maintain your creative nature while being collaborative.
    '''
    temperature: 0.7
    max_tokens: 2048
    top_p: 0.95

  corpus_callosum:
    default_mode: 'parallel'
    communication_timeout: 30000  # 30 seconds
    max_iterations: 5  # For debate mode
    synthesis_threshold: 0.8  # Similarity threshold for synthesis

    # Communication modes configuration
    modes:
      parallel:
        description: 'Both models process simultaneously'
        show_both: true
        timeout: 15000

      sequential:
        description: 'Alpha then Beta, or Beta then Alpha'
        default_order: ['alpha', 'beta']
        handoff_delay: 2000

      debate:
        description: 'Models challenge and refine each other'
        max_rounds: 3
        convergence_threshold: 0.9

      synthesis:
        description: 'Combine responses into unified output'
        synthesis_model: 'alpha'  # Which model handles synthesis
        show_individual: false

      handoff:
        description: 'One model takes over from the other'
        trigger_phrases: ['hand this over', 'let the other handle', 'switch to']

    # Inter-model communication patterns
    communication_patterns:
      request_input: 'REQUEST_INPUT: {topic}'
      share_analysis: 'ANALYSIS: {findings}'
      suggest_alternative: 'ALTERNATIVE: {suggestion}'
      challenge_assumption: 'CHALLENGE: {assumption}'
      provide_context: 'CONTEXT: {information}'
      synthesize: 'SYNTHESIZE: {combination_request}'
}