# Stub for socket.io-client in tests
# This avoids needing the real socket.io-client dependency for unit tests

module.exports = {
  connect: -> {
    on: ->
    emit: ->
    disconnect: ->
    id: 'test-socket-id'
  }
}