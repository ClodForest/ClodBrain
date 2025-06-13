# Neo4j Tool Tests - Simple and Direct
{ describe, it, beforeEach, mock } = require 'node:test'
assert = require 'node:assert'
Neo4jTool = require '../../src/services/neo4j-tool'

describe 'Neo4jTool', ->
  tool = null
  mockConfig = null

  # Helper to create fresh mocks for each test
  createMocks = ->
    mockResult = {
      records: []
      summary: {
        counters: {}
        resultAvailableAfter: 0
        resultConsumedAfter: 0
      }
    }

    mockSession = {
      run: mock.fn -> Promise.resolve(mockResult)
      close: mock.fn -> Promise.resolve()
    }

    mockDriver = {
      session: mock.fn -> mockSession
      close: mock.fn -> Promise.resolve()
    }

    mockConfig = {
      connect: mock.fn -> Promise.resolve(mockDriver)
    }

    return { mockDriver, mockSession, mockResult, mockConfig }

  beforeEach ->
    mocks = createMocks()
    mockConfig = mocks.mockConfig
    tool = new Neo4jTool(mockConfig)

  describe 'connection', ->
    it 'should connect to database', ->
      result = await tool.connect()

      assert.equal result, true
      assert.ok tool.driver
      assert.equal mockConfig.connect.mock.calls.length, 1

    it 'should handle connection errors', ->
      mockConfig.connect = mock.fn -> Promise.reject(new Error('Connection failed'))

      try
        await tool.connect()
        assert.fail('Should have thrown')
      catch error
        assert.equal error.message, 'Connection failed'

  describe 'executeQuery', ->
    it 'should execute cypher query with parameters', ->
      result = await tool.executeQuery('MATCH (n) RETURN n', { limit: 10 })

      # Check the query we care about was called
      calls = tool.driver.session().run.mock.calls
      queryCalls = calls.filter (call) ->
        call.arguments[0] == 'MATCH (n) RETURN n'

      assert.equal queryCalls.length, 1
      assert.deepEqual queryCalls[0].arguments[1], { limit: 10 }

      # Check result format
      assert.ok result.records
      assert.ok result.summary

    it 'should auto-connect if not connected', ->
      result = await tool.executeQuery('RETURN 1')

      assert.equal mockConfig.connect.mock.calls.length, 1

    it 'should handle query errors', ->
      mocks = createMocks()
      mocks.mockSession.run = mock.fn -> Promise.reject(new Error('Query failed'))
      tool = new Neo4jTool(mocks.mockConfig)

      try
        await tool.executeQuery('BAD QUERY')
        assert.fail('Should have thrown')
      catch error
        assert.equal error.message, 'Query failed'

  describe 'schema operations', ->
    it 'should initialize schema during connect', ->
      await tool.connect()

      # Should have schema set
      assert.ok tool.schema.nodes
      assert.ok tool.schema.relationships
      assert.ok Array.isArray(tool.schema.nodes)
      assert.ok Array.isArray(tool.schema.relationships)

  describe 'graph exploration', ->
    it 'should explore nodes by type', ->
      result = await tool.exploreGraph('Entity', 25)

      # Find the explore query
      calls = tool.driver.session().run.mock.calls
      exploreCall = calls.find (call) ->
        call.arguments[0].includes('MATCH (n:Entity)')

      assert.ok exploreCall
      assert.equal exploreCall.arguments[1].limit, 25

  describe 'natural language queries', ->
    it 'should handle conversation queries', ->
      await tool.naturalLanguageQuery('show me recent conversations')

      calls = tool.driver.session().run.mock.calls
      queryCall = calls.find (call) ->
        call.arguments[0].includes('MATCH (c:Conversation)') and
        call.arguments[0].includes('ORDER BY c.startTime DESC')

      assert.ok queryCall

    it 'should handle entity queries', ->
      await tool.naturalLanguageQuery('what entities do we have?')

      calls = tool.driver.session().run.mock.calls
      queryCall = calls.find (call) ->
        call.arguments[0].includes('MATCH (e:Entity)')

      assert.ok queryCall

    it 'should have default query for unknown questions', ->
      await tool.naturalLanguageQuery('random question')

      calls = tool.driver.session().run.mock.calls
      queryCall = calls.find (call) ->
        call.arguments[0].includes('MATCH (n)') and
        call.arguments[0].includes('count(n)')

      assert.ok queryCall

  describe 'knowledge management', ->
    it 'should add entities and relationships', ->
      # Create fresh tool with session that supports getSession
      mocks = createMocks()
      tool = new Neo4jTool(mocks.mockConfig)
      tool.getSession = mock.fn -> mocks.mockSession

      entities = [
        { name: 'Alice', type: 'person', confidence: 0.9 }
        { name: 'Bob', type: 'person', confidence: 0.8 }
      ]

      relationships = [
        { from: 'Alice', to: 'Bob', type: 'knows', strength: 0.7 }
      ]

      await tool.addKnowledge(entities, relationships)

      # Should have run queries for entities and relationships
      calls = mocks.mockSession.run.mock.calls
      assert.ok calls.length >= 3  # 2 entities + 1 relationship

  describe 'utilities', ->
    it 'should clear database', ->
      await tool.clearAll()

      calls = tool.driver.session().run.mock.calls
      deleteCall = calls.find (call) ->
        call.arguments[0].includes('DETACH DELETE')

      assert.ok deleteCall

    it 'should close driver connection', ->
      await tool.connect()
      await tool.close()

      assert.equal tool.driver.close.mock.calls.length, 1

    it 'should generate schema info', ->
      schema = await tool.generateSchema()

      # Just verify the structure exists
      assert.ok schema
      assert.ok schema.sampleQueries
      assert.ok Array.isArray(schema.sampleQueries)
      assert.ok schema.sampleQueries.length > 0

      # The actual content doesn't matter for this test