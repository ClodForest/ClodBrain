# Neo4j Tool Service - Knowledge Graph Integration
class Neo4jTool
  constructor: (@databaseConfig) ->
    @driver = null
    @session = null
    @schema = {}

  connect: ->
    try
      @driver = await @databaseConfig.connect()
      console.log "✅ Neo4j Tool connected"
      await @initializeSchema()
      return true
    catch error
      console.error "❌ Neo4j Tool connection failed:", error.message
      throw error

  getSession: ->
    if not @driver
      await @connect()
    return @driver.session()

  # Safe query execution with validation
  executeQuery: (cypher, parameters = {}) ->
    session = null
    try
      if not @driver
        await @connect()
      
      session = @driver.session()
      result = await session.run(cypher, parameters)
      
      records = result.records.map (record) ->
        obj = {}
        record.keys.forEach (key) ->
          obj[key] = record.get(key)
        return obj
      
      return {
        records: records
        summary: {
          counters: result.summary.counters
          resultAvailableAfter: result.summary.resultAvailableAfter
          resultConsumedAfter: result.summary.resultConsumedAfter
        }
      }
      
    catch error
      console.error 'Neo4j query error:', error
      throw error
    finally
      if session
        await session.close()

  # Initialize the graph schema
  initializeSchema: ->
    try
      # Create indexes for better performance
      queries = [
        'CREATE INDEX conversation_id IF NOT EXISTS FOR (c:Conversation) ON (c.id)'
        'CREATE INDEX message_id IF NOT EXISTS FOR (m:Message) ON (m.id)'
        'CREATE INDEX entity_name IF NOT EXISTS FOR (e:Entity) ON (e.name)'
        'CREATE INDEX concept_name IF NOT EXISTS FOR (c:Concept) ON (c.name)'
      ]
      
      for query in queries
        await @executeQuery(query)
      
      @schema = {
        nodes: ['Conversation', 'Message', 'Entity', 'Concept', 'Communication']
        relationships: ['CONTAINS', 'RESPONDS_TO', 'MENTIONS', 'DISCUSSES', 'HAS_COMMUNICATION']
      }
      
      console.log "✅ Neo4j schema initialized"
      
    catch error
      console.error 'Schema initialization error:', error

  # General graph exploration
  exploreGraph: (nodeType, limit = 50) ->
    query = "MATCH (n:#{nodeType}) RETURN n LIMIT $limit"
    return await @executeQuery(query, { limit: limit })

  # Find connections between entities
  findRelationships: (nodeA, nodeB) ->
    query = '''
      MATCH (a), (b)
      WHERE a.name = $nodeA AND b.name = $nodeB
      MATCH path = (a)-[*1..3]-(b)
      RETURN path LIMIT 10
    '''
    return await @executeQuery(query, { nodeA: nodeA, nodeB: nodeB })

  # Store new information from conversations
  addKnowledge: (entities, relationships) ->
    session = null
    try
      session = @getSession()
      
      # Store entities
      for entity in entities
        query = '''
          MERGE (e:Entity {name: $name})
          ON CREATE SET e.type = $type, e.confidence = $confidence, e.created = timestamp()
          ON MATCH SET e.confidence = (e.confidence + $confidence) / 2
          RETURN e
        '''
        await session.run(query, entity)
      
      # Store relationships
      for rel in relationships
        query = '''
          MATCH (a:Entity {name: $from}), (b:Entity {name: $to})
          MERGE (a)-[r:RELATES_TO {type: $type}]->(b)
          ON CREATE SET r.strength = $strength, r.created = timestamp()
          ON MATCH SET r.strength = (r.strength + $strength) / 2
          RETURN r
        '''
        await session.run(query, rel)
        
    catch error
      console.error 'Knowledge addition error:', error
      throw error
    finally
      if session
        await session.close()

  # LLM-friendly query interface
  naturalLanguageQuery: (question) ->
    # Simple mapping of natural language to Cypher
    # In production, this would use an LLM to generate Cypher
    
    lowerQuestion = question.toLowerCase()
    
    if lowerQuestion.includes('conversations')
      if lowerQuestion.includes('recent')
        query = '''
          MATCH (c:Conversation)
          RETURN c.id, c.startTime, c.messageCount
          ORDER BY c.startTime DESC
          LIMIT 10
        '''
      else
        query = '''
          MATCH (c:Conversation)
          RETURN count(c) as totalConversations,
                 avg(c.messageCount) as avgMessages
        '''
    
    else if lowerQuestion.includes('entities')
      query = '''
        MATCH (e:Entity)
        RETURN e.name, e.type, e.confidence
        ORDER BY e.confidence DESC
        LIMIT 20
      '''
    
    else if lowerQuestion.includes('concepts')
      query = '''
        MATCH (c:Concept)
        RETURN c.name, c.domain
        ORDER BY c.name
        LIMIT 20
      '''
    
    else
      # Default: return some general stats
      query = '''
        MATCH (n)
        RETURN labels(n)[0] as nodeType, count(n) as count
        ORDER BY count DESC
      '''
    
    return await @executeQuery(query)

  # Return current graph schema for LLM context
  generateSchema: ->
    try
      # Get node types and their properties
      nodeQuery = '''
        CALL db.labels() YIELD label
        RETURN collect(label) as nodeTypes
      '''
      
      # Get relationship types
      relQuery = '''
        CALL db.relationshipTypes() YIELD relationshipType
        RETURN collect(relationshipType) as relationshipTypes
      '''
      
      nodeResult = await @executeQuery(nodeQuery)
      relResult = await @executeQuery(relQuery)
      
      return {
        nodeTypes: nodeResult.records[0]?.nodeTypes || []
        relationshipTypes: relResult.records[0]?.relationshipTypes || []
        sampleQueries: [
          'MATCH (c:Conversation) RETURN c LIMIT 5'
          'MATCH (m:Message) RETURN m.content LIMIT 5'
          'MATCH (e:Entity) RETURN e.name, e.type LIMIT 10'
        ]
      }
      
    catch error
      console.error 'Schema generation error:', error
      return @schema

  # Get statistics about the knowledge graph
  getStats: ->
    try
      query = '''
        MATCH (n)
        OPTIONAL MATCH ()-[r]->()
        RETURN 
          labels(n)[0] as nodeType,
          count(DISTINCT n) as nodeCount,
          count(DISTINCT r) as relationshipCount
      '''
      
      result = await @executeQuery(query)
      
      stats = {
        totalNodes: 0
        totalRelationships: 0
        nodeTypes: {}
      }
      
      for record in result.records
        stats.nodeTypes[record.nodeType] = record.nodeCount
        stats.totalNodes += record.nodeCount
        stats.totalRelationships += record.relationshipCount
      
      return stats
      
    catch error
      console.error 'Stats generation error:', error
      return { error: error.message }

  # Clear all data (for development/testing)
  clearAll: ->
    try
      await @executeQuery('MATCH (n) DETACH DELETE n')
      console.log "🗑️ Neo4j database cleared"
      await @initializeSchema()
    catch error
      console.error 'Clear database error:', error
      throw error

  # Close connection
  close: ->
    if @driver
      await @driver.close()
      console.log "🔌 Neo4j Tool disconnected"

module.exports = Neo4jTool