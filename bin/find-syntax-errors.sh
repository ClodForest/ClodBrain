#!/bin/bash

echo "🔍 Finding CoffeeScript syntax errors..."
echo ""

# Check each test file for syntax errors
for file in t/**/*.test.coffee t/**/*.coffee; do
    if [ -f "$file" ]; then
        # Try to compile it
        if ! coffee -c "$file" > /dev/null 2>&1; then
            echo "❌ Syntax error in: $file"
            echo "Error details:"
            coffee -c "$file" 2>&1 | head -10
            echo "---"
            echo ""
        fi
    fi
done

echo ""
echo "📦 Checking for missing socket.io-client..."
if [ -f "t/integration/dual-llm-system.test.coffee" ]; then
    echo "Integration test file exists. Checking imports..."
    grep -n "socket.io-client" t/integration/dual-llm-system.test.coffee || echo "No socket.io-client import found"

    echo ""
    echo "Suggestion: Either:"
    echo "1. Comment out integration tests for now (they need a running server)"
    echo "2. Or add to package.json devDependencies: \"socket.io-client\": \"^4.7.2\""
fi

echo ""
echo "🔧 Quick syntax check on all test files:"
find t -name "*.coffee" -type f -exec sh -c 'echo -n "Checking {} ... "; coffee -c {} > /dev/null 2>&1 && echo "✓" || echo "✗"' \;