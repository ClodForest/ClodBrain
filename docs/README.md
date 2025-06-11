# Dual-LLM Split Brain Chat System

A NodeJS/Express application implementing a dual-LLM "split-brain" architecture where two models collaborate through controlled communication patterns. Built entirely in CoffeeScript with real-time chat interface and Neo4j tool integration.

## 🧠 Architecture

- **Alpha Brain (Left)**: Analytical, logical, sequential processing
- **Beta Brain (Right)**: Creative, intuitive, pattern recognition
- **Corpus Callosum**: Inter-LLM communication layer
- **Neo4j Integration**: Shared knowledge graph

## 🚀 Quick Start

### Prerequisites

1. **Node.js 18+**
2. **Ollama** with models:
   ```bash
   ollama pull llama3.1:8b-instruct-q4_K_M
   ollama pull qwen2.5-coder:7b-instruct-q4_K_M
   ```
3. **Neo4j** (Community Edition)
   ```bash
   docker run --name neo4j -p7474:7474 -p7687:7687 -d -e NEO4J_AUTH=neo4j/password neo4j:latest
   ```

### Installation

```bash
# Clone and setup
git clone <your-repo>
cd dual-llm-chat

# Install dependencies
npm install

# Setup Neo4j schema
npm run neo4j:setup

# Start development server
npm run dev
```

### Usage

1. Open http://localhost:3000
2. Select communication mode (Parallel, Sequential, Debate, Synthesis, Handoff)
3. Chat with both AI brains simultaneously
4. Watch the inter-brain communication in real-time

## 🎛️ Communication Modes

- **Parallel**: Both models process simultaneously
- **Sequential**: Alpha then Beta (or vice versa)
- **Debate**: Models challenge and refine each other
- **Synthesis**: Combine responses into unified output
- **Handoff**: One model takes over from the other

## 🛠️ Development

```bash
npm run dev          # Development with auto-reload
npm run compile      # Compile CoffeeScript
npm run test         # Run test suite
npm run lint         # CoffeeScript linting
```

## 📊 Features

- Real-time dual-brain chat interface
- WebSocket-based communication
- Neo4j knowledge graph integration
- Multiple orchestration modes
- Inter-LLM communication visualization
- CoffeeScript throughout

## 🔧 Configuration

Edit `.env` file for:
- Ollama host and models
- Neo4j connection
- Application settings

## 📝 License

MIT License - see LICENSE file
