# Ollama API Configuration
axios = require 'axios'

module.exports = {
  host: process.env.OLLAMA_HOST || 'http://localhost:11434'
  timeout: parseInt(process.env.OLLAMA_TIMEOUT) || 300000  # 5 minutes
  
  # Default request configuration
  defaultConfig:
    timeout: parseInt(process.env.OLLAMA_TIMEOUT) || 300000
    headers:
      'Content-Type': 'application/json'
    
  # Health check function
  healthCheck: ->
    try
      response = await axios.get "#{@host}/api/tags", {
        timeout: 5000
      }
      return {
        status: 'healthy'
        models: response.data?.models || []
        timestamp: new Date().toISOString()
      }
    catch error
      return {
        status: 'unhealthy'
        error: error.message
        timestamp: new Date().toISOString()
      }
  
  # List available models
  listModels: ->
    try
      response = await axios.get "#{@host}/api/tags"
      return response.data?.models || []
    catch error
      console.error 'Failed to list Ollama models:', error.message
      return []
  
  # Check if specific model exists
  hasModel: (modelName) ->
    try
      models = await @listModels()
      return models.some (model) -> model.name is modelName
    catch error
      return false
  
  # Pull a model if it doesn't exist
  ensureModel: (modelName) ->
    try
      if await @hasModel(modelName)
        console.log "✅ Model #{modelName} already available"
        return true
      
      console.log "📥 Pulling model #{modelName}..."
      response = await axios.post "#{@host}/api/pull", 
        { name: modelName }
        { timeout: 600000 }  # 10 minutes for model download
      
      console.log "✅ Model #{modelName} pulled successfully"
      return true
      
    catch error
      console.error "❌ Failed to pull model #{modelName}:", error.message
      return false
}