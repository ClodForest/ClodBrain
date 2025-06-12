# ClodBrain Test Suite

## Overview

ClodBrain uses **Vitest** as its testing framework - a blazing fast unit test framework powered by Vite. It was chosen for:

- Zero configuration needed
- Native CoffeeScript support via plugin
- Built-in mocking and coverage
- Watch mode with intelligent test re-running
- Compatible with Jest APIs

## Test Structure

```
test/
├── setup.coffee           # Common test utilities and mocks
├── services/              # Unit tests for each service
│   ├── base-llm.test.coffee
│   ├── llm-alpha.test.coffee
│   ├── llm-beta.test.coffee
│   ├── corpus-callosum.test.coffee
│   ├── mode-executors.test.coffee
│   ├── message-router.test.coffee
│   └── neo4j-tool.test.coffee
└── integration/           # Full system integration tests
    └── dual-llm-system.test.coffee
```

## Running Tests

### Basic Commands

```bash
# Run all tests once
npm test

# Run tests in watch mode (recommended for development)
npm run test:watch

# Run with coverage report
npm run test:coverage

# Open Vitest UI in browser
npm run test:ui
```

### Using the Test Script

```bash
# Make script executable
chmod +x bin/test.sh

# Run all tests
./bin/test.sh

# Watch mode
./bin/test.sh watch

# Coverage report
./bin/test.sh coverage

# Unit tests only
./bin/test.sh unit

# Integration tests only
./bin/test.sh integration

# Quick smoke test
./bin/test.sh quick

# Run specific test file
./bin/test.sh specific mode-executors

# Debug mode
./bin/test.sh debug
```

## Writing Tests

### Basic Test Structure

```coffeescript
{ describe, it, expect, beforeEach, vi } = require 'vitest'
MyService = require '../../src/services/my-service'

describe 'MyService', ->
  service = null

  beforeEach ->
    service = new MyService()

  describe 'methodName', ->
    it 'should do something', ->
      result = service.methodName('input')
      expect(result).toBe('expected output')
```

### Using Test Utilities

```coffeescript
{
  createMockOllamaResponse
  createMockNeo4jTool
  createTestConfig
  waitForPromises
} = require '../setup'

# Create mocked dependencies
mockNeo4j = createMockNeo4jTool()
config = createTestConfig()

# Wait for async operations
await waitForPromises(100)
```

### Mocking with Vitest

```coffeescript
# Mock a module
vi.mock 'axios', ->
  {
    post: vi.fn()
    get: vi.fn()
  }

# Create a spy
spy = vi.fn()

# Mock implementation
mock.mockImplementation((arg) ->
  Promise.resolve({ data: arg })
)

# Check calls
expect(mock).toHaveBeenCalledWith('expected arg')
expect(mock).toHaveBeenCalledTimes(2)
```

## Test Coverage

Current coverage targets:
- **Statements**: 80%
- **Branches**: 75%
- **Functions**: 80%
- **Lines**: 80%

View coverage report:
```bash
npm run test:coverage
open coverage/index.html
```

## Common Test Patterns

### Testing Async Code

```coffeescript
it 'should handle async operations', ->
  promise = service.asyncMethod()

  result = await promise
  expect(result).toBe('success')

# Or with expect assertions
it 'should reject with error', ->
  await expect(service.failingMethod()).rejects.toThrow('Error message')
```

### Testing WebSocket Events

```coffeescript
mockSocket = createMockSocket()

# Emit event
await handler({ message: 'test' })

# Check emissions
emissions = mockSocket.getEmitted('response_event')
expect(emissions[0].data).toBe('expected')
```

### Testing Neo4j Queries

```coffeescript
mockNeo4j = createMockNeo4jTool()

# Set up response
mockNeo4j.executeQuery.mockResolvedValue({
  records: [{ name: 'Test' }]
})

# Verify query
expect(mockNeo4j.executeQuery).toHaveBeenCalledWith(
  expect.stringContaining('MATCH')
  expect.any(Object)
)
```

## Debugging Tests

### VS Code Debugging

Add to `.vscode/launch.json`:
```json
{
  "type": "node",
  "request": "launch",
  "name": "Debug Tests",
  "program": "${workspaceFolder}/node_modules/vitest/vitest.mjs",
  "args": ["run", "${file}"],
  "console": "integratedTerminal"
}
```

### Command Line Debugging

```bash
# Debug specific test
NODE_OPTIONS='--inspect-brk' npx vitest run test/services/corpus-callosum.test.coffee

# Then open chrome://inspect
```

## CI/CD Integration

For GitHub Actions:
```yaml
- name: Run Tests
  run: ./bin/test.sh ci

- name: Upload Coverage
  uses: codecov/codecov-action@v3
  with:
    files: ./coverage/coverage-final.json
```

## Troubleshooting

### Tests Hanging
- Check for unresolved promises
- Ensure all mocks are properly reset in `beforeEach`
- Use `vi.useFakeTimers()` for timer-based code

### Flaky Tests
- Avoid hardcoded delays
- Use `waitForPromises` utility
- Mock all external dependencies

### Coffee Compilation Errors
- Ensure `vite-plugin-coffee` is installed
- Check CoffeeScript syntax
- Verify import paths use correct extensions

## Best Practices

1. **Test Organization**
   - One test file per source file
   - Mirror source directory structure
   - Group related tests with `describe`

2. **Test Naming**
   - Use descriptive test names
   - Start with "should" for clarity
   - Include expected behavior

3. **Mocking**
   - Mock all external dependencies
   - Reset mocks in `beforeEach`
   - Verify mock calls when relevant

4. **Assertions**
   - One logical assertion per test
   - Use appropriate matchers
   - Test both success and error cases

5. **Performance**
   - Keep tests fast (<100ms each)
   - Avoid real network/database calls
   - Use minimal test data

## Contributing Tests

When adding new features:
1. Write tests first (TDD approach)
2. Ensure all edge cases are covered
3. Add integration tests for complex flows
4. Update this README if adding new patterns

Happy Testing! 🧪✨