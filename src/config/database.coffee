# Neo4j Database Configuration
neo4j = require 'neo4j-driver'

class DatabaseConfig
  constructor: ->
    @uri = process.env.NEO4J_URI || 'bolt://localhost:7687'
    @user = process.env.NEO4J_USER || 'neo4j'
    @password = process.env.NEO4J_PASSWORD || 'password'
    @driver = null

  connect: ->
    try
      @driver = neo4j.driver(@uri, neo4j.auth.basic(@user, @password), {
        maxConnectionLifetime: 3 * 60 * 60 * 1000, # 3 hours
        maxConnectionPoolSize: 50,
        connectionAcquisitionTimeout: 2 * 60 * 1000, # 2 minutes
        disableLosslessIntegers: true
      })
      
      # Test connection
      session = @driver.session()
      await session.run('RETURN 1')
      await session.close()
      
      console.log "✅ Connected to Neo4j at #{@uri}"
      return @driver
      
    catch error
      console.error "❌ Failed to connect to Neo4j:", error.message
      throw error

  getDriver: ->
    if not @driver
      throw new Error 'Database not connected. Call connect() first.'
    return @driver

  close: ->
    if @driver
      await @driver.close()
      console.log "🔌 Neo4j connection closed"

# Export singleton instance
module.exports = new DatabaseConfig()