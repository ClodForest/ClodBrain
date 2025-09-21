# Integration Test: MessageRouter + Neo4jTool
{ describe, it, beforeEach, mock } = require 'node:test'
assert = require 'node:assert'

MessageRouter = require '../../src/services/message-router'
Neo4jTool = require '../../src/services/neo4j-tool'

describe 'MessageRouter + Neo4jTool Integration', ->
  router = null
  neo4j = null
  mockCorpus = null
  mockDriver = null
  mockSession = null
  executedQueries = null

  beforeEach ->
    # Track all executed queries
    executedQueries = []

    # Mock Neo4j driver and session
    mockSession = {
      run: mock.fn (query, params) ->
        executedQueries.push({ query, params })
        Promise.resolve({
          records: []
          summary: { counters: {} }
        })
      close: mock.fn -> Promise.resolve()
    }

    mockDriver = {
      session: mock.fn -> mockSession
      close: mock.fn -> Promise.resolve()
    }

    mockDatabaseConfig = {
      connect: mock.fn -> Promise.resolve(mockDriver)
    }

    # Mock corpus for router
    mockCorpus = {
      orchestrate: mock.fn (message, convId, mode) ->
        Promise.resolve({
          alphaResponse: { content: "Alpha: #{message}" }
          betaResponse: { content: "Beta: #{message}" }
          mode: mode || 'parallel'
          timestamp: new Date().toISOString()
        })
      getStats: mock.fn -> { mode: 'parallel' }
      interrupt: mock.fn()
    }

    # Create real components
    neo4j = new Neo4jTool(mockDatabaseConfig)
    router = new MessageRouter(mockCorpus, neo4j)

  describe 'conversation storage', ->
    it 'should create conversation in Neo4j', ->
      await router.processMessage('Hello world')

      # Find conversation creation query
      convQuery = executedQueries.find (q) ->
        q.query.includes('CREATE (c:Conversation')

      assert.ok convQuery
      assert.ok convQuery.params.id
      assert.ok convQuery.params.startTime
      assert.ok convQuery.params.participants
      assert.deepEqual convQuery.params.participants, ['user', 'alpha', 'beta']

    it 'should not create duplicate conversations', ->
      await router.processMessage('First message', 'parallel', 'conv123')
      await router.processMessage('Second message', 'parallel', 'conv123')

      # Should only create conversation once
      convCreations = executedQueries.filter (q) ->
        q.query.includes('CREATE (c:Conversation')

      assert.equal convCreations.length, 1

  describe 'message storage', ->
    it 'should store user messages with relationships', ->
      result = await router.processMessage('Test message', 'parallel', 'conv123')

      # Find message creation queries
      messageQueries = executedQueries.filter (q) ->
        q.query.includes('CREATE (m:Message')

      # Should have 3 messages: user, alpha, beta
      assert.equal messageQueries.length, 3

      # Check user message
      userMsgQuery = messageQueries.find (q) ->
        q.params.sender == 'user'

      assert.ok userMsgQuery
      assert.equal userMsgQuery.params.content, 'Test message'
      assert.equal userMsgQuery.params.conversationId, 'conv123'
      assert.ok userMsgQuery.params.timestamp

      # Should link to conversation
      assert.ok userMsgQuery.query.includes('CREATE (c)-[:CONTAINS]->(m)')

    it 'should store LLM responses', ->
      await router.processMessage('Hello', 'parallel', 'conv123')

      # Find alpha and beta message queries
      alphaMsgQuery = executedQueries.find (q) ->
        q.params?.sender == 'alpha'

      betaMsgQuery = executedQueries.find (q) ->
        q.params?.sender == 'beta'

      assert.ok alphaMsgQuery
      assert.ok betaMsgQuery
      assert.equal alphaMsgQuery.params.content, 'Alpha: Hello'
      assert.equal betaMsgQuery.params.content, 'Beta: Hello'

    it 'should handle synthesis responses', ->
      mockCorpus.orchestrate = mock.fn ->
        Promise.resolve({
          alphaResponse: { content: 'Alpha view' }
          betaResponse: { content: 'Beta view' }
          synthesis: { content: 'Combined view' }
          timestamp: new Date().toISOString()
        })

      await router.processMessage('Synthesize', 'synthesis', 'conv123')

      synthQuery = executedQueries.find (q) ->
        q.params?.sender == 'synthesis'

      assert.ok synthQuery
      assert.equal synthQuery.params.content, 'Combined view'

  describe 'knowledge extraction', ->
    it 'should extract and store entities', ->
      await router.processMessage('Alice and Bob are working on Project X')

      # Should extract capitalized words as entities
      entityQueries = executedQueries.filter (q) ->
        q.query.includes('MERGE (e:Entity')

      # Should find Alice, Bob, Project X
      assert.ok entityQueries.length >= 2

      # Check entity structure
      entityNames = entityQueries.map (q) -> q.params.name
      assert.ok entityNames.some (name) -> name == 'Alice'
      assert.ok entityNames.some (name) -> name == 'Bob'

    it 'should extract and store concepts', ->
      await router.processMessage('We need better testing and documentation')

      # Should extract concept words (gerunds, -tion words)
      conceptQueries = executedQueries.filter (q) ->
        q.query.includes('MERGE (c:Concept')

      assert.ok conceptQueries.length >= 2

      # Check for expected concepts
      conceptNames = conceptQueries.map (q) -> q.params.name
      assert.ok conceptNames.some (name) -> name == 'testing'
      assert.ok conceptNames.some (name) -> name == 'documentation'

    it 'should link entities to conversations', ->
      await router.processMessage('Alice is here', 'parallel', 'conv123')

      # Find entity linking query
      linkQuery = executedQueries.find (q) ->
        q.query.includes('MERGE (c)-[:MENTIONS]->(e)')

      assert.ok linkQuery
      assert.equal linkQuery.params.conversationId, 'conv123'

  describe 'communication storage', ->
    it 'should store inter-brain communications', ->
      # Make corpus return communications
      mockCorpus.orchestrate = mock.fn ->
        Promise.resolve({
          alphaResponse: { content: 'Alpha' }
          betaResponse: { content: 'Beta' }
          communications: [
            { from: 'alpha', to: 'beta', message: 'Handoff', type: 'handoff' }
          ]
          timestamp: new Date().toISOString()
        })

      await router.processMessage('Test', 'sequential', 'conv123')

      # Find communication query
      commQuery = executedQueries.find (q) ->
        q.query.includes('CREATE (comm:Communication')

      assert.ok commQuery
      assert.equal commQuery.params.fromBrain, 'alpha'
      assert.equal commQuery.params.toBrain, 'beta'
      assert.equal commQuery.params.content, 'Handoff'
      assert.equal commQuery.params.type, 'handoff'

  describe 'error handling', ->
    it 'should continue working if Neo4j fails', ->
      # Make Neo4j fail
      mockSession.run = mock.fn -> Promise.reject(new Error('DB error'))

      # Should not throw
      result = await router.processMessage('Test message')

      # Should still get corpus response
      assert.ok result
      assert.ok result.alphaResponse
      assert.ok result.betaResponse

      # Router should still track conversation in memory
      conv = router.getConversation(result.conversationId)
      assert.ok conv
      assert.ok conv.messages.length > 0

    it 'should log but not crash on storage errors', ->
      # Fail only on entity storage
      callCount = 0
      mockSession.run = mock.fn (query) ->
        callCount++
        if query.includes('Entity')
          Promise.reject(new Error('Entity storage failed'))
        else
          Promise.resolve({ records: [], summary: { counters: {} } })

      # Should complete successfully
      result = await router.processMessage('Alice and Bob')
      assert.ok result

  describe 'retrieval operations', ->
    it 'should be able to query stored data', ->
      # Store some data
      await router.processMessage('Hello', 'parallel', 'conv123')

      # Reset queries
      executedQueries.length = 0

      # Query for conversations
      result = await neo4j.naturalLanguageQuery('show recent conversations')

      query = executedQueries.find (q) ->
        q.query.includes('MATCH (c:Conversation)')

      assert.ok query
      assert.ok query.query.includes('ORDER BY c.startTime DESC')

    it 'should track statistics', ->
      await router.processMessage('Message 1')
      await router.processMessage('Message 2')

      stats = router.getStats()

      assert.equal stats.activeConversations, 2
      assert.ok stats.totalMessages >= 4  # At least 2 user + 2 responses

  describe 'cleanup operations', ->
    it 'should close connections properly', ->
      await neo4j.connect()
      await neo4j.close()

      assert.equal mockDriver.close.mock.calls.length, 1