# Neo4j Tool Tests
{ describe, it, beforeEach, mock } = require 'node:test'
assert = require 'node:assert'
Neo4jTool = require '../../src/services/neo4j-tool'
{ createMockNeo4jDriver } = require '../setup'

describe 'Neo4jTool', ->
  mockDriver = null
  mockDatabaseConfig = null
  neo4jTool = null

  beforeEach ->
    mockDriver = createMockNeo4jDriver()
    mockDatabaseConfig = {
      connect: mock.fn()
      getDriver: mock.fn()
      close: mock.fn()
    }

    # Set default mock implementations
    mockDatabaseConfig.connect.mock.mockImplementation -> Promise.resolve(mockDriver)
    mockDatabaseConfig.getDriver.mock.mockImplementation -> mockDriver
    mockDatabaseConfig.close.mock.mockImplementation -> Promise.resolve(undefined)

    neo4jTool = new Neo4jTool(mockDatabaseConfig)

  describe 'constructor', ->
    it 'should initialize with database config', ->
      assert.equal neo4jTool.databaseConfig, mockDatabaseConfig
      assert.equal neo4jTool.driver, null
      assert.equal neo4jTool.session, null
      assert.deepEqual neo4jTool.schema, {}

  describe 'connect', ->
    it 'should connect and initialize schema', ->
      result = await neo4jTool.connect()

      assert.equal result, true
      assert.ok mockDatabaseConfig.connect.mock.calls.length > 0
      assert.equal neo4jTool.driver, mockDriver

      # Should create indexes
      sessions = mockDriver.getSessions()
      assert.ok sessions.length > 0

      # Check for index creation queries
      runCalls = sessions[0].run.mock.calls
      indexQueries = runCalls.filter (call) ->
        call.arguments[0].includes('CREATE INDEX')
      assert.equal indexQueries.length, 4 # 4 indexes

    it 'should handle connection errors', ->
      mockDatabaseConfig.connect.mock.mockImplementation ->
        Promise.reject(new Error('Connection failed'))

      await assert.rejects(
        neo4jTool.connect()
        { message: 'Connection failed' }
      )

  describe 'executeQuery', ->
    beforeEach ->
      await neo4jTool.connect()

    it 'should execute query and return results', ->
      mockSession = mockDriver.getSessions()[0]
      mockSession.run.mock.mockImplementation ->
        Promise.resolve {
          records: [
            {
              keys: ['name', 'age']
              get: (key) -> if key is 'name' then 'Alice' else 25
            }
            {
              keys: ['name', 'age']
              get: (key) -> if key is 'name' then 'Bob' else 30
            }
          ]
          summary: {
            counters: { nodesCreated: 2 }
            resultAvailableAfter: 5
            resultConsumedAfter: 10
          }
        }

      result = await neo4jTool.executeQuery(
        'MATCH (n:Person) RETURN n.name as name, n.age as age'
        {}
      )

      assert.deepEqual result.records, [
        { name: 'Alice', age: 25 }
        { name: 'Bob', age: 30 }
      ]
      assert.equal result.summary.counters.nodesCreated, 2
      assert.ok mockSession.close.mock.calls.length > 0

    it 'should handle query parameters', ->
      await neo4jTool.executeQuery(
        'MATCH (n:Person {name: $name}) RETURN n'
        { name: 'Alice' }
      )

      session = mockDriver.getSessions()[0]
      assert.equal session.run.mock.calls[0].arguments[0], 'MATCH (n:Person {name: $name}) RETURN n'
      assert.deepEqual session.run.mock.calls[0].arguments[1], { name: 'Alice' }

    it 'should close session even on error', ->
      mockSession = mockDriver.getSessions()[0]
      mockSession.run.mock.mockImplementation ->
        Promise.reject(new Error('Query failed'))

      await assert.rejects(
        neo4jTool.executeQuery('INVALID QUERY')
        { message: 'Query failed' }
      )

      assert.ok mockSession.close.mock.calls.length > 0

    it 'should create new session if not connected', ->
      neo4jTool.driver = null # Reset connection

      await neo4jTool.executeQuery('MATCH (n) RETURN n')

      assert.ok mockDatabaseConfig.connect.mock.calls.length > 0

  # Add more test cases as needed...