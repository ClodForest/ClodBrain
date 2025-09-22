# Message Router - Orchestrates message flow through the dual-brain system
class MessageRouter
  constructor: (@corpusCallosum, @neo4jTool) ->
    @activeConversations = new Map()
    @messageHistory = []
    @interrupted = false

  processMessage: (message, mode = 'parallel', conversationId = null, options = {}) ->
    try
      # Generate conversation ID if not provided
      if not conversationId
        conversationId = @generateConversationId()

      # Initialize conversation if new
      if not @activeConversations.has(conversationId)
        @initializeConversation(conversationId)

      conversation = @activeConversations.get(conversationId)

      # Add user message to conversation
      userMessage = {
        id: @generateMessageId()
        content: message
        sender: 'user'
        timestamp: new Date().toISOString()
        conversationId: conversationId
        isOOC: options.isOOC || false  # Track if message is OOC
      }

      conversation.messages.push(userMessage)
      @messageHistory.push(userMessage)

      # Store message in Neo4j
      await @storeMessageInNeo4j(userMessage, conversation)

      # Process through corpus callosum
      result = await @corpusCallosum.orchestrate(message, conversationId, mode, options)

      # Store AI responses in conversation and Neo4j
      if result.alphaResponse
        alphaContent = if typeof result.alphaResponse is 'string' then result.alphaResponse else result.alphaResponse.content
        alphaMessage = {
          id: @generateMessageId()
          content: alphaContent
          sender: 'alpha'
          model: 'alpha'
          timestamp: result.timestamp
          conversationId: conversationId
        }
        conversation.messages.push(alphaMessage)
        @messageHistory.push(alphaMessage)
        await @storeMessageInNeo4j(alphaMessage, conversation)

      if result.betaResponse
        betaContent = if typeof result.betaResponse is 'string' then result.betaResponse else result.betaResponse.content
        betaMessage = {
          id: @generateMessageId()
          content: betaContent
          sender: 'beta'
          model: 'beta'
          timestamp: result.timestamp
          conversationId: conversationId
        }
        conversation.messages.push(betaMessage)
        @messageHistory.push(betaMessage)
        await @storeMessageInNeo4j(betaMessage, conversation)

      if result.synthesis
        synthesisContent = if typeof result.synthesis is 'string' then result.synthesis else result.synthesis.content
        synthesisMessage = {
          id: @generateMessageId()
          content: synthesisContent
          sender: 'synthesis'
          model: 'synthesis'
          timestamp: result.timestamp
          conversationId: conversationId
        }
        conversation.messages.push(synthesisMessage)
        @messageHistory.push(synthesisMessage)
        await @storeMessageInNeo4j(synthesisMessage, conversation)

      # Handle roleplay IC responses
      if result.icResponse
        icMessage = {
          id: @generateMessageId()
          content: result.icResponse
          sender: 'character'
          character: result.character
          model: 'roleplay'
          timestamp: result.timestamp
          conversationId: conversationId
          isOOC: false
        }
        conversation.messages.push(icMessage)
        @messageHistory.push(icMessage)
        await @storeMessageInNeo4j(icMessage, conversation)

      # Update conversation metadata
      conversation.lastActivity = new Date().toISOString()
      conversation.mode = mode
      conversation.messageCount = conversation.messages.length

      # Store communications in Neo4j
      if result.communications
        for comm in result.communications
          await @storeCommunicationInNeo4j(comm, conversationId)

      # Extract and store knowledge from the conversation
      await @extractAndStoreKnowledge(message, result, conversationId)

      return {
        conversationId: conversationId
        userMessage: userMessage
        ...result
      }

    catch error
      console.error 'Message processing error:', error
      throw error

  initializeConversation: (conversationId) ->
    conversation = {
      id: conversationId
      startTime: new Date().toISOString()
      lastActivity: new Date().toISOString()
      messages: []
      mode: 'parallel'
      messageCount: 0
      participants: ['user', 'alpha', 'beta']
    }
    
    @activeConversations.set(conversationId, conversation)
    
    # Store conversation in Neo4j
    @storeConversationInNeo4j(conversation)
    
    return conversation

  storeConversationInNeo4j: (conversation) ->
    try
      query = '''
        CREATE (c:Conversation {
          id: $id,
          startTime: $startTime,
          lastActivity: $lastActivity,
          mode: $mode,
          messageCount: $messageCount,
          participants: $participants
        })
        RETURN c
      '''
      
      await @neo4jTool.executeQuery(query, {
        id: conversation.id
        startTime: conversation.startTime
        lastActivity: conversation.lastActivity
        mode: conversation.mode
        messageCount: conversation.messageCount
        participants: conversation.participants
      })
      
    catch error
      console.error 'Failed to store conversation in Neo4j:', error

  storeMessageInNeo4j: (message, conversation) ->
    try
      query = '''
        MATCH (c:Conversation {id: $conversationId})
        CREATE (m:Message {
          id: $id,
          content: $content,
          sender: $sender,
          model: $model,
          timestamp: $timestamp,
          conversationId: $conversationId
        })
        CREATE (c)-[:CONTAINS]->(m)
        RETURN m
      '''
      
      await @neo4jTool.executeQuery(query, {
        id: message.id
        content: message.content
        sender: message.sender
        model: message.model || message.sender  # Ensure it's a string
        timestamp: message.timestamp
        conversationId: message.conversationId
      })
      
    catch error
      console.error 'Failed to store message in Neo4j:', error

  storeCommunicationInNeo4j: (communication, conversationId) ->
    try
      # Flatten the communication object to primitive values only
      query = '''
        MATCH (c:Conversation {id: $conversationId})
        CREATE (comm:Communication {
          id: $id,
          fromBrain: $fromBrain,
          toBrain: $toBrain,
          content: $content,
          type: $type,
          timestamp: $timestamp,
          conversationId: $conversationId
        })
        CREATE (c)-[:HAS_COMMUNICATION]->(comm)
        RETURN comm
      '''
      
      await @neo4jTool.executeQuery(query, {
        id: @generateMessageId()
        fromBrain: String(communication.from || 'unknown')
        toBrain: String(communication.to || 'unknown')
        content: String(communication.message || communication.content || '')
        type: String(communication.type || 'general')
        timestamp: new Date(communication.timestamp || Date.now()).toISOString()
        conversationId: String(conversationId)
      })
      
    catch error
      console.error 'Failed to store communication in Neo4j:', error

  extractAndStoreKnowledge: (userMessage, result, conversationId) ->
    try
      # Extract entities and concepts from the conversation
      entities = @extractEntities(userMessage, result)
      concepts = @extractConcepts(userMessage, result)
      
      # Store entities
      for entity in entities
        await @storeEntityInNeo4j(entity, conversationId)
      
      # Store concepts
      for concept in concepts
        await @storeConceptInNeo4j(concept, conversationId)
        
    catch error
      console.error 'Failed to extract and store knowledge:', error

  extractEntities: (userMessage, result) ->
    entities = []
    
    # Simple entity extraction (in production, use proper NLP)
    content = "#{userMessage} #{result.alphaResponse || ''} #{result.betaResponse || ''}"
    
    # Extract capitalized words as potential entities
    matches = content.match(/\b[A-Z][a-z]+(?:\s+[A-Z][a-z]+)*\b/g) || []
    
    for match in matches
      if match.length > 2 and not @isCommonWord(match)
        entities.push {
          name: match
          type: 'entity'
          confidence: 0.7
          extractedFrom: 'conversation'
        }
    
    return entities

  extractConcepts: (userMessage, result) ->
    concepts = []
    
    # Extract potential concepts (simplified approach)
    content = "#{userMessage} #{result.alphaResponse || ''} #{result.betaResponse || ''}"
    
    # Look for conceptual terms
    conceptPatterns = [
      /\b(\w+ing)\b/g,  # gerunds
      /\b(\w+tion)\b/g, # action nouns
      /\b(\w+ment)\b/g, # state nouns
      /\b(\w+ness)\b/g  # quality nouns
    ]
    
    for pattern in conceptPatterns
      matches = content.match(pattern) || []
      for match in matches
        if match.length > 4 and not @isCommonWord(match)
          concepts.push {
            name: match
            type: 'concept'
            domain: 'general'
            extractedFrom: 'conversation'
          }
    
    return concepts

  storeEntityInNeo4j: (entity, conversationId) ->
    try
      query = '''
        MERGE (e:Entity {name: $name})
        ON CREATE SET e.type = $type, e.confidence = $confidence, e.created = timestamp()
        ON MATCH SET e.confidence = (e.confidence + $confidence) / 2
        
        WITH e
        MATCH (c:Conversation {id: $conversationId})
        MERGE (c)-[:MENTIONS]->(e)
        RETURN e
      '''
      
      await @neo4jTool.executeQuery(query, {
        name: entity.name
        type: entity.type
        confidence: entity.confidence
        conversationId: conversationId
      })
      
    catch error
      console.error 'Failed to store entity in Neo4j:', error

  storeConceptInNeo4j: (concept, conversationId) ->
    try
      query = '''
        MERGE (c:Concept {name: $name})
        ON CREATE SET c.type = $type, c.domain = $domain, c.created = timestamp()
        
        WITH c
        MATCH (conv:Conversation {id: $conversationId})
        MERGE (conv)-[:DISCUSSES]->(c)
        RETURN c
      '''
      
      await @neo4jTool.executeQuery(query, {
        name: concept.name
        type: concept.type
        domain: concept.domain
        conversationId: conversationId
      })
      
    catch error
      console.error 'Failed to store concept in Neo4j:', error

  isCommonWord: (word) ->
    commonWords = [
      'The', 'This', 'That', 'These', 'Those', 'When', 'Where', 'Who', 'What', 'Why',
      'How', 'Yes', 'No', 'Can', 'Will', 'Should', 'Could', 'Would', 'But', 'And',
      'Or', 'So', 'Because', 'Since', 'While', 'During', 'Before', 'After'
    ]
    return commonWords.includes(word)

  getConversation: (conversationId) ->
    return @activeConversations.get(conversationId)

  getAllConversations: ->
    return Array.from(@activeConversations.values())

  getMessageHistory: (limit = 100) ->
    return @messageHistory.slice(-limit)

  interrupt: ->
    @interrupted = true
    @corpusCallosum.interrupt()
    console.log 'Message router interrupted'

  clearInterrupt: ->
    @interrupted = false

  generateConversationId: ->
    "conv_#{Date.now()}_#{Math.random().toString(36).substr(2, 9)}"

  generateMessageId: ->
    "msg_#{Date.now()}_#{Math.random().toString(36).substr(2, 9)}"

  getStats: ->
    return {
      activeConversations: @activeConversations.size
      totalMessages: @messageHistory.length
      interrupted: @interrupted
      corpusStats: @corpusCallosum.getStats()
    }

  # Character management methods for roleplay
  loadCharacter: (characterCard) ->
    # Returns character info including first message
    @corpusCallosum.loadCharacter(characterCard)

  resetRoleplay: ->
    # Returns the first message if available
    @corpusCallosum.resetRoleplay()

module.exports = MessageRouter