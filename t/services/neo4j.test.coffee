# Neo4j Tool Tests
{ describe, it, expect, beforeEach, vi } = require 'vitest'
Neo4jTool = require '../../src/services/neo4j-tool'
{ createMockNeo4jDriver } = require '../setup'

describe 'Neo4jTool', ->
  mockDriver = null
  mockDatabaseConfig = null
  neo4jTool = null

  beforeEach ->
    mockDriver = createMockNeo4jDriver()
    mockDatabaseConfig = {
      connect: vi.fn().mockResolvedValue(mockDriver)
      getDriver: vi.fn().mockReturnValue(mockDriver)
      close: vi.fn().mockResolvedValue(undefined)
    }
    neo4jTool = new Neo4jTool(mockDatabaseConfig)

  describe 'constructor', ->
    it 'should initialize with database config', ->
      expect(neo4jTool.databaseConfig).toBe(mockDatabaseConfig)
      expect(neo4jTool.driver).toBe(null)
      expect(neo4jTool.session).toBe(null)
      expect(neo4jTool.schema).toEqual({})

  describe 'connect', ->
    it 'should connect and initialize schema', ->
      result = await neo4jTool.connect()

      expect(result).toBe(true)
      expect(mockDatabaseConfig.connect).toHaveBeenCalled()
      expect(neo4jTool.driver).toBe(mockDriver)

      # Should create indexes
      sessions = mockDriver.getSessions()
      expect(sessions.length).toBeGreaterThan(0)

      # Check for index creation queries
      runCalls = sessions[0].run.mock.calls
      indexQueries = runCalls.filter((call) ->
        call[0].includes('CREATE INDEX')
      )
      expect(indexQueries.length).toBe(4) # 4 indexes

    it 'should handle connection errors', ->
      mockDatabaseConfig.connect.mockRejectedValue(new Error('Connection failed'))

      await expect(neo4jTool.connect()).rejects.toThrow('Connection failed')

  describe 'executeQuery', ->
    beforeEach ->
      await neo4jTool.connect()

    it 'should execute query and return results', ->
      mockSession = mockDriver.getSessions()[0]
      mockSession.run.mockResolvedValue({
        records: [
          { keys: ['name', 'age'], get: (key) -> if key is 'name' then 'Alice' else 25 }
          { keys: ['name', 'age'], get: (key) -> if key is 'name' then 'Bob' else 30 }
        ]
        summary: {
          counters: { nodesCreated: 2 }
          resultAvailableAfter: 5
          resultConsumedAfter: 10
        }
      })

      result = await neo4jTool.executeQuery(
        'MATCH (n:Person) RETURN n.name as name, n.age as age'
        {}
      )

      expect(result.records).toEqual([
        { name: 'Alice', age: 25 }
        { name: 'Bob', age: 30 }
      ])
      expect(result.summary.counters.nodesCreated).toBe(2)
      expect(mockSession.close).toHaveBeenCalled()

    it 'should handle query parameters', ->
      await neo4jTool.executeQuery(
        'MATCH (n:Person {name: $name}) RETURN n'
        { name: 'Alice' }
      )

      session = mockDriver.getSessions()[0]
      expect(session.run).toHaveBeenCalledWith(
        'MATCH (n:Person {name: $name}) RETURN n'
        { name: 'Alice' }
      )

    it 'should close session even on error', ->
      mockSession = mockDriver.getSessions()[0]
      mockSession.run.mockRejectedValue(new Error('Query failed'))

      await expect(
        neo4jTool.executeQuery('INVALID QUERY')
      ).rejects.toThrow('Query failed')

      expect(mockSession.close).toHaveBeenCalled()

    it 'should create new session if not connected', ->
      neo4jTool.driver = null # Reset connection

      await neo4jTool.executeQuery('MATCH (n) RETURN n')

      expect(mockDatabaseConfig.connect).toHaveBeenCalled()

  describe 'exploreGraph', ->
    beforeEach ->
      await neo4jTool.connect()

    it 'should explore nodes of given type', ->
      await neo4jTool.exploreGraph('Entity', 25)

      session = mockDriver.getSessions()[0]
      expect(session.run).toHaveBeenCalledWith(
        'MATCH (n:Entity) RETURN n LIMIT $limit'
        { limit: 25 }
      )

    it 'should use default limit', ->
      await neo4jTool.exploreGraph('Concept')

      session = mockDriver.getSessions()[0]
      expect(session.run).toHaveBeenCalledWith(
        'MATCH (n:Concept) RETURN n LIMIT $limit'
        { limit: 50 }
      )

  describe 'findRelationships', ->
    beforeEach ->
      await neo4jTool.connect()

    it 'should find paths between nodes', ->
      await neo4jTool.findRelationships('NodeA', 'NodeB')

      session = mockDriver.getSessions()[0]
      expect(session.run).toHaveBeenCalledWith(
        expect.stringContaining('MATCH path = (a)-[*1..3]-(b)')
        { nodeA: 'NodeA', nodeB: 'NodeB' }
      )

  describe 'addKnowledge', ->
    beforeEach ->
      await neo4jTool.connect()

    it 'should add entities and relationships', ->
      entities = [
        { name: 'Claude', type: 'AI', confidence: 0.9 }
        { name: 'Anthropic', type: 'Company', confidence: 1.0 }
      ]

      relationships = [
        { from: 'Claude', to: 'Anthropic', type: 'created_by', strength: 1.0 }
      ]

      await neo4jTool.addKnowledge(entities, relationships)

      sessions = mockDriver.getSessions()
      lastSession = sessions[sessions.length - 1]

      # Check entity creation
      entityCalls = lastSession.run.mock.calls.filter((call) ->
        call[0].includes('MERGE (e:Entity')
      )
      expect(entityCalls).toHaveLength(2)

      # Check relationship creation
      relCalls = lastSession.run.mock.calls.filter((call) ->
        call[0].includes('MERGE (a)-[r:RELATES_TO')
      )
      expect(relCalls).toHaveLength(1)

      expect(lastSession.close).toHaveBeenCalled()

    it 'should handle errors gracefully', ->
      mockSession = mockDriver.session()
      mockSession.run.mockRejectedValue(new Error('DB error'))

      await expect(
        neo4jTool.addKnowledge([{ name: 'Test' }], [])
      ).rejects.toThrow('DB error')

  describe 'naturalLanguageQuery', ->
    beforeEach ->
      await neo4jTool.connect()

    it 'should handle conversation queries', ->
      await neo4jTool.naturalLanguageQuery('show me recent conversations')

      session = mockDriver.getSessions()[0]
      expect(session.run).toHaveBeenCalledWith(
        expect.stringContaining('MATCH (c:Conversation)')
        expect.any(Object)
      )

    it 'should handle entity queries', ->
      await neo4jTool.naturalLanguageQuery('what entities have been mentioned')

      session = mockDriver.getSessions()[0]
      expect(session.run).toHaveBeenCalledWith(
        expect.stringContaining('MATCH (e:Entity)')
        expect.any(Object)
      )

    it 'should handle concept queries', ->
      await neo4jTool.naturalLanguageQuery('list all concepts')

      session = mockDriver.getSessions()[0]
      expect(session.run).toHaveBeenCalledWith(
        expect.stringContaining('MATCH (c:Concept)')
        expect.any(Object)
      )

    it 'should default to general stats', ->
      await neo4jTool.naturalLanguageQuery('something else')

      session = mockDriver.getSessions()[0]
      expect(session.run).toHaveBeenCalledWith(
        expect.stringContaining('MATCH (n)')
        expect.any(Object)
      )

  describe 'generateSchema', ->
    beforeEach ->
      await neo4jTool.connect()

    it 'should return schema information', ->
      # Mock schema queries
      mockSession = mockDriver.session()
      mockSession.run
        .mockResolvedValueOnce({
          records: [{ nodeTypes: ['Entity', 'Concept', 'Conversation'] }]
        })
        .mockResolvedValueOnce({
          records: [{ relationshipTypes: ['RELATES_TO', 'CONTAINS'] }]
        })

      schema = await neo4jTool.generateSchema()

      expect(schema).toMatchObject({
        nodeTypes: ['Entity', 'Concept', 'Conversation']
        relationshipTypes: ['RELATES_TO', 'CONTAINS']
        sampleQueries: expect.arrayContaining([
          expect.stringContaining('MATCH (c:Conversation)')
        ])
      })

    it 'should handle schema query errors', ->
      mockSession = mockDriver.session()
      mockSession.run.mockRejectedValue(new Error('Schema error'))

      schema = await neo4jTool.generateSchema()

      # Should return default schema
      expect(schema).toEqual({
        nodes: ['Conversation', 'Message', 'Entity', 'Concept', 'Communication']
        relationships: ['CONTAINS', 'RESPONDS_TO', 'MENTIONS', 'DISCUSSES', 'HAS_COMMUNICATION']
      })

  describe 'getStats', ->
    beforeEach ->
      await neo4jTool.connect()

    it 'should return graph statistics', ->
      mockSession = mockDriver.session()
      mockSession.run.mockResolvedValue({
        records: [
          { nodeType: 'Entity', nodeCount: 10, relationshipCount: 5 }
          { nodeType: 'Concept', nodeCount: 8, relationshipCount: 3 }
        ]
      })

      stats = await neo4jTool.getStats()

      expect(stats).toEqual({
        totalNodes: 18
        totalRelationships: 8
        nodeTypes: {
          Entity: 10
          Concept: 8
        }
      })

    it 'should handle stats errors', ->
      mockSession = mockDriver.session()
      mockSession.run.mockRejectedValue(new Error('Stats error'))

      stats = await neo4jTool.getStats()

      expect(stats).toEqual({ error: 'Stats error' })

  describe 'clearAll', ->
    beforeEach ->
      await neo4jTool.connect()

    it 'should clear database and reinitialize schema', ->
      await neo4jTool.clearAll()

      sessions = mockDriver.getSessions()

      # Find delete query
      deleteCall = sessions.find((session) ->
        session.run.mock.calls.some((call) ->
          call[0].includes('MATCH (n) DETACH DELETE n')
        )
      )

      expect(deleteCall).toBeTruthy()

      # Should recreate indexes
      lastSession = sessions[sessions.length - 1]
      indexCalls = lastSession.run.mock.calls.filter((call) ->
        call[0].includes('CREATE INDEX')
      )
      expect(indexCalls.length).toBeGreaterThan(0)

  describe 'close', ->
    it 'should close driver connection', ->
      await neo4jTool.connect()
      await neo4jTool.close()

      expect(mockDriver.close).toHaveBeenCalled()

    it 'should handle missing driver', ->
      # Should not throw
      await expect(neo4jTool.close()).resolves.toBeUndefined()

  describe 'getSession', ->
    it 'should create session from existing driver', ->
      await neo4jTool.connect()

      session = neo4jTool.getSession()

      expect(session).toBeTruthy()
      expect(mockDriver.session).toHaveBeenCalled()

    it 'should connect if no driver', ->
      session = await neo4jTool.getSession()

      expect(mockDatabaseConfig.connect).toHaveBeenCalled()
      expect(session).toBeTruthy()