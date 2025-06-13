#!/bin/bash

# Test output summarizer for ClodBrain

echo "📊 Test Summary Report"
echo "===================="
echo ""

# Run tests and capture output
TEST_OUTPUT=$(npm test 2>&1)

# Save full output for reference
echo "$TEST_OUTPUT" > test-output-full.log

# Extract key metrics
echo "📈 Overall Stats:"
echo "$TEST_OUTPUT" | grep -E "^ℹ (tests|pass|fail)" | tail -5

echo ""
echo "❌ Framework Errors (not test failures):"
echo "----------------------------------------"
# Look for common framework errors
echo "$TEST_OUTPUT" | grep -E "(ReferenceError|TypeError|SyntaxError)" | grep -v "AssertionError" | sort | uniq -c | sort -nr | head -10

echo ""
echo "🔍 Common Error Patterns:"
echo "------------------------"
# Extract undefined references
echo "Undefined variables:"
echo "$TEST_OUTPUT" | grep -oE "[a-zA-Z_][a-zA-Z0-9_]* is not defined" | sort | uniq -c | sort -nr

echo ""
echo "Missing imports/requires:"
echo "$TEST_OUTPUT" | grep -oE "Cannot find module '[^']+'" | sort | uniq -c | sort -nr

echo ""
echo "📁 Files with Framework Errors:"
echo "------------------------------"
# Find which test files have errors (not just test failures)
echo "$TEST_OUTPUT" | grep -B2 -E "(ReferenceError|TypeError|SyntaxError)" | grep "test at" | cut -d' ' -f3 | sort | uniq | head -20

echo ""
echo "✅ Passing Test Files:"
echo "---------------------"
# Find files where all tests passed
echo "$TEST_OUTPUT" | grep -B1 "✔" | grep "\.coffee" | grep -v "✖" | sort | uniq | head -10

echo ""
echo "🎯 Quick Fix Suggestions:"
echo "------------------------"

# Check for common issues
if echo "$TEST_OUTPUT" | grep -q "mock is not defined"; then
    echo "- Add: { mock } = require 'node:test' to test files"
fi

if echo "$TEST_OUTPUT" | grep -q "vi is not defined"; then
    echo "- Replace 'vi' with 'mock' (vi was from Vitest)"
fi

if echo "$TEST_OUTPUT" | grep -q "expect.*is not defined"; then
    echo "- Convert expect() to assert calls"
fi

if echo "$TEST_OUTPUT" | grep -q "Cannot find module.*\.js"; then
    echo "- Remove .js extensions from local requires"
fi

if echo "$TEST_OUTPUT" | grep -q "exports is not defined"; then
    echo "- Some files might still be using ESM syntax"
fi

echo ""
echo "📝 Full output saved to: test-output-full.log"
echo ""
echo "Run specific test file example:"
echo "node -r coffeescript/register --test t/services/base-llm.test.coffee"