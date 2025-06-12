#!/bin/bash

# Dual-LLM Chat System Setup Script
echo "🧠 Setting up Dual-LLM Split Brain Chat System..."

bin="$(dirname "$0")"
echo $bin
cd "$(realpath "$bin"/..)"
pwd

if ! [ -x bin/$(basename $0) ]; then
    echo "Something amiss in the directory situation..."
    exit 1
fi

# Create project directory structure
echo "📁 Creating project structure..."
mkdir -p ./{src/{config,models,services,controllers,middleware,utils},public/{css,js,assets},t/{unit,integration,fixtures},docs,bin}

# Create .env file
echo "⚙️ Creating environment configuration..."
cat > .env << 'EOF'
# Ollama Configuration
OLLAMA_HOST=http://localhost:11434
OLLAMA_TIMEOUT=300000

# Neo4j Configuration
NEO4J_URI=bolt://localhost:7687
NEO4J_USER=neo4j
NEO4J_PASSWORD=password

# Application Settings
PORT=3000
NODE_ENV=development
LOG_LEVEL=info

# Model Settings
ALPHA_MODEL=llama3.1:8b-instruct-q4_K_M
BETA_MODEL=qwen2.5-coder:7b-instruct-q4_K_M
EOF

# Create .gitignore
echo "📝 Creating .gitignore..."
cat > .gitignore << 'EOF'
# Node.js
node_modules/
npm-debug.log*
yarn-debug.log*
yarn-error.log*

# Environment variables
.env
.env.local
.env.development.local
.env.test.local
.env.production.local

# Logs
logs
*.log
npm-debug.log*
yarn-debug.log*
yarn-error.log*

# Runtime data
pids
*.pid
*.seed
*.pid.lock

# Coverage directory used by tools like istanbul
coverage/

# Compiled CoffeeScript
lib/
*.js.map

# IDE files
.vscode/
.idea/
*.swp
*.swo
*~

# OS generated files
.DS_Store
.DS_Store?
._*
.Spotlight-V100
.Trashes
ehthumbs.db
Thumbs.db

# PM2
.pm2/

# Docker
.docker/

# Vim
.sw?
.*.sw?
EOF

# Create CoffeeLint configuration
echo "☕ Creating CoffeeLint configuration..."
cat > .coffeelintrc.json << 'EOF'
{
  "arrow_spacing": {
    "level": "error"
  },
  "braces_spacing": {
    "level": "error",
    "spaces": 0
  },
  "camel_case_classes": {
    "level": "error"
  },
  "coffeescript_error": {
    "level": "error"
  },
  "colon_assignment_spacing": {
    "level": "error",
    "spacing": {
      "left": 0,
      "right": 1
    }
  },
  "cyclomatic_complexity": {
    "level": "warn",
    "value": 10
  },
  "duplicate_key": {
    "level": "error"
  },
  "empty_constructor_needs_parens": {
    "level": "ignore"
  },
  "ensure_comprehensions": {
    "level": "warn"
  },
  "eol_last": {
    "level": "ignore"
  },
  "indentation": {
    "value": 2,
    "level": "error"
  },
  "line_endings": {
    "level": "ignore",
    "value": "unix"
  },
  "max_line_length": {
    "value": 120,
    "level": "error"
  },
  "missing_fat_arrows": {
    "level": "ignore"
  },
  "newlines_after_classes": {
    "value": 3,
    "level": "ignore"
  },
  "no_backticks": {
    "level": "error"
  },
  "no_debugger": {
    "level": "warn"
  },
  "no_empty_functions": {
    "level": "ignore"
  },
  "no_empty_param_list": {
    "level": "ignore"
  },
  "no_implicit_braces": {
    "level": "ignore"
  },
  "no_implicit_parens": {
    "level": "ignore"
  },
  "no_interpolation_in_single_quotes": {
    "level": "ignore"
  },
  "no_nested_string_interpolation": {
    "level": "warn"
  },
  "no_plusplus": {
    "level": "ignore"
  },
  "no_stand_alone_at": {
    "level": "ignore"
  },
  "no_tabs": {
    "level": "error"
  },
  "no_this": {
    "level": "ignore"
  },
  "no_throwing_strings": {
    "level": "error"
  },
  "no_trailing_semicolons": {
    "level": "error"
  },
  "no_trailing_whitespace": {
    "level": "error"
  },
  "no_unnecessary_double_quotes": {
    "level": "ignore"
  },
  "no_unnecessary_fat_arrows": {
    "level": "warn"
  },
  "non_empty_constructor_needs_parens": {
    "level": "ignore"
  },
  "prefer_english_operator": {
    "level": "ignore"
  },
  "space_operators": {
    "level": "ignore"
  },
  "spacing_after_comma": {
    "level": "ignore"
  },
  "transform_messes_up_line_numbers": {
    "level": "warn"
  }
}
EOF

# Create README
echo "📖 Creating README..."
cat > docs/README.md << 'EOF'
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
EOF

# Create basic test file
echo "🧪 Creating basic test..."
cat > test/basic.test.coffee << 'EOF'
# Basic test to verify CoffeeScript setup
describe 'Dual-LLM Chat System', ->
  it 'should have proper test setup', ->
    expect(true).to.be.true

  it 'should load configuration', ->
    config = require '../src/config/models'
    expect(config).to.exist
    expect(config.alpha).to.exist
    expect(config.beta).to.exist
EOF

# Install dependencies
echo "📦 Installing Node.js dependencies..."
npm install

# Check if Ollama is running
echo "🔍 Checking Ollama status..."
if curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
    echo "✅ Ollama is running"

    # Check for required models
    echo "🔍 Checking for required models..."
    if curl -s http://localhost:11434/api/tags | grep -q "llama3.1:8b-instruct-q4_K_M"; then
        echo "✅ Alpha model (llama3.1:8b-instruct-q4_K_M) found"
    else
        echo "⚠️  Alpha model not found. Please run: ollama pull llama3.1:8b-instruct-q4_K_M"
    fi

    if curl -s http://localhost:11434/api/tags | grep -q "qwen2.5-coder:7b-instruct-q4_K_M"; then
        echo "✅ Beta model (qwen2.5-coder:7b-instruct-q4_K_M) found"
    else
        echo "⚠️  Beta model not found. Please run: ollama pull qwen2.5-coder:7b-instruct-q4_K_M"
    fi
else
    echo "⚠️  Ollama not running. Please start Ollama first."
fi

# Check Neo4j
echo "🔍 Checking Neo4j status..."
if nc -z localhost 7687 2>/dev/null; then
    echo "✅ Neo4j is running on port 7687"
else
    echo "⚠️  Neo4j not running. Please start Neo4j:"
    echo "   docker run --name neo4j -p7474:7474 -p7687:7687 -d -e NEO4J_AUTH=neo4j/password neo4j:latest"
fi

echo ""
echo "🎉 Setup complete! Next steps:"
echo ""
echo "1. Ensure Ollama is running with required models:"
echo "   ollama pull llama3.1:8b-instruct-q4_K_M"
echo "   ollama pull qwen2.5-coder:7b-instruct-q4_K_M"
echo ""
echo "2. Ensure Neo4j is running:"
echo "   docker run --name neo4j -p7474:7474 -p7687:7687 -d -e NEO4J_AUTH=neo4j/password neo4j:latest"
echo ""
echo "3. Start the development server:"
echo "   npm run dev"
echo ""
echo "4. Open your browser to:"
echo "   http://localhost:3000"
echo ""
echo "🧠 Happy dual-brain chatting!"
