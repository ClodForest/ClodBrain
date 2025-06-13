#!/bin/bash

# Cleanup script to remove all vitest references

echo "🧹 Cleaning up Vitest references..."
echo ""

# Convert test files from vitest to node:test
echo "Converting test imports..."
for file in t/**/*.test.coffee; do
    if [ -f "$file" ] && grep -q "vitest" "$file"; then
        echo "Updating: $file"
        # Change vitest imports to node:test
        sed -i '' "s/{ describe, it, expect, beforeEach, vi } = require 'vitest'/{ describe, it, beforeEach } = require 'node:test'/g" "$file"
        sed -i '' "s/{ describe, it, expect, beforeEach, afterEach, vi } = require 'vitest'/{ describe, it, beforeEach, afterEach } = require 'node:test'/g" "$file"
        sed -i '' "s/{ describe, it, expect, before, beforeEach, mock } = require 'vitest'/{ describe, it, before, beforeEach, mock } = require 'node:test'/g" "$file"

        # Add assert require after the test require
        sed -i '' "/= require 'node:test'/a\\
assert = require 'node:assert'\\
{ mock } = require 'node:test'" "$file"

        # Remove duplicate mock imports
        sed -i '' '/^{ mock } = require.*node:test.*$/d' "$file"

        # Convert vi.fn() to mock.fn()
        sed -i '' 's/vi\.fn()/mock.fn()/g' "$file"
        sed -i '' 's/vi\.mock/mock.module/g' "$file"

        # Convert expect to assert
        sed -i '' 's/expect(\([^)]*\))\.toBe(\([^)]*\))/assert.equal \1, \2/g' "$file"
        sed -i '' 's/expect(\([^)]*\))\.toEqual(\([^)]*\))/assert.deepEqual \1, \2/g' "$file"
        sed -i '' 's/expect(\([^)]*\))\.toBeTruthy()/assert.ok \1/g' "$file"
        sed -i '' 's/expect(\([^)]*\))\.toBeFalsy()/assert.ok not \1/g' "$file"
        sed -i '' 's/expect(\([^)]*\))\.toBeUndefined()/assert.equal \1, undefined/g' "$file"
        sed -i '' 's/expect(\([^)]*\))\.toMatchObject/assert.deepEqual \1,/g' "$file"

        echo "✅ Updated: $file"
    fi
done

echo ""
echo "Removing vitest config..."
if [ -f "vitest.config.js" ]; then
    rm vitest.config.js
    echo "✅ Removed vitest.config.js"
fi

if [ -f "vitest.config.mjs" ]; then
    rm vitest.config.mjs
    echo "✅ Removed vitest.config.mjs"
fi

echo ""
echo "Updating t/README.md..."
if [ -f "t/README.md" ]; then
    # Update the README to reflect Node.js test runner
    sed -i '' 's/Vitest/Node.js Test Runner/g' t/README.md
    sed -i '' 's/vitest/node:test/g' t/README.md
    sed -i '' '/vite-plugin-coffee/d' t/README.md
    echo "✅ Updated t/README.md"
fi

echo ""
echo "Removing vitest from package.json devDependencies..."
if grep -q "vitest" package.json; then
    # Remove vitest-related lines
    sed -i '' '/"vitest":/d' package.json
    sed -i '' '/"@vitest\/ui":/d' package.json
    sed -i '' '/"@vitest\/coverage-v8":/d' package.json
    sed -i '' '/"vite-plugin-coffee.*":/d' package.json

    # Fix any trailing commas
    sed -i '' ':a; N; $!ba; s/,\n  }/\n  }/g' package.json

    echo "✅ Cleaned package.json"
fi

echo ""
echo "🎉 Vitest cleanup complete!"
echo ""
echo "Next steps:"
echo "1. Review changes: git diff"
echo "2. Run tests: npm test"
echo "3. Install updated dependencies: npm install"
echo ""
echo "Note: Complex expect() chains may need manual conversion to assert"