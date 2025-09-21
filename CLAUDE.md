# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Common Development Commands

### Running the Application
```bash
npm run dev        # Start development server with nodemon
npm start          # Start production server
```

### Testing
```bash
npm test                    # Run all tests
npm run test:unit          # Run unit tests only
npm run test:integration   # Run integration tests only
npm run test:watch         # Run tests in watch mode
npm run test:coverage      # Run tests with coverage report
```

### Database Setup
```bash
npm run docker:neo4j       # Start Neo4j Docker container
npm run neo4j:setup        # Seed Neo4j with initial data
```

## Architecture Overview

This is a **dual-LLM chat system** called "ClodBrain" implementing a split-brain architecture with two AI models working together:

### Core Components

**Dual Brain Architecture:**
- **Alpha LLM**: Analytical "left brain" (default: llama3.1:8b) - logical, methodical, precise
- **Beta LLM**: Creative "right brain" (default: qwen2.5-coder:7b) - intuitive, creative, holistic
- **Corpus Callosum**: Communication layer orchestrating interaction between the two brains

**Key Services:**
- `MessageRouter`: Routes messages through the dual-brain system, manages conversations
- `CorpusCallosum`: Orchestrates different interaction modes (parallel, sequential, debate, synthesis, handoff)
- `Neo4jTool`: Manages knowledge graph storage and retrieval
- `BaseLLM/LLMAlpha/LLMBeta`: Interface with Ollama API for LLM interactions

### Communication Modes

The system supports multiple orchestration modes:
- **Parallel**: Both brains process simultaneously
- **Sequential**: One brain then the other (Alpha→Beta or Beta→Alpha)
- **Debate**: Brains challenge and refine each other's responses
- **Synthesis**: Combine responses into unified output
- **Handoff**: One brain takes over from the other

### Technology Stack

- **Language**: CoffeeScript (compiles to CommonJS)
- **Runtime**: Node.js >=24.2.0
- **LLM Backend**: Ollama (local LLM hosting)
- **Database**: Neo4j (knowledge graph)
- **Web Framework**: Express.js with Socket.IO for real-time communication
- **Testing**: Node.js Test Runner

### Configuration

Models and behavior are configured in `src/config/`:
- `models.coffee`: LLM configurations, personalities, system prompts
- `database.coffee`: Neo4j connection settings
- `ollama.coffee`: Ollama API configuration

Environment variables:
- `ALPHA_MODEL`: Override default Alpha model
- `BETA_MODEL`: Override default Beta model
- `NEO4J_URI`: Neo4j connection string
- `OLLAMA_HOST`: Ollama API endpoint

### File Structure

```
src/
├── app.coffee                    # Main Express application
├── config/                      # Configuration files
├── services/
│   ├── base-llm.coffee          # Base LLM interface
│   ├── llm-alpha.coffee         # Alpha brain implementation
│   ├── llm-beta.coffee          # Beta brain implementation
│   ├── corpus-callosum.coffee   # Brain orchestration
│   ├── mode-executors.coffee    # Individual mode implementations
│   ├── message-router.coffee    # Message routing and conversation management
│   └── neo4j-tool.coffee        # Neo4j integration
t/                               # Test files (mirrors src structure)
bin/                             # Scripts and utilities
```

## Development Notes

- The system stores conversations, messages, entities, and concepts in Neo4j for knowledge building
- Real-time communication uses Socket.IO events (message_send, alpha_response, beta_response, etc.)
- Inter-brain communication uses structured patterns (ALPHA_TO_BETA:, BETA_TO_ALPHA:)
- All async operations should be properly handled with try/catch blocks
- The test suite uses Node.js Test Runner with comprehensive mocking utilities