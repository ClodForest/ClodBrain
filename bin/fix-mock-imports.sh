#!/bin/bash

echo "🔧 Fixing mock imports in test files..."

# Fix all test files to properly import mock
for file in t/**/*.test.coffee; do
    if [ -f "$file" ]; then
        # Check if file uses mock but doesn't import it
        if grep -q "mock\." "$file" && ! grep -q "mock.*=.*require.*node:test" "$file"; then
            echo "Fixing: $file"

            # Add mock to the existing node:test import if it exists
            if grep -q "require 'node:test'" "$file"; then
                # Add mock to the destructuring if not already there
                sed -i '' "s/{ \([^}]*\) } = require 'node:test'/{ \1, mock } = require 'node:test'/g" "$file"
                # Remove duplicate mock
                sed -i '' 's/, mock, mock/, mock/g' "$file"
                sed -i '' 's/{, mock/{ mock/g' "$file"
            else
                # Add the import if missing entirely
                sed -i '' "1i\\
{ mock } = require 'node:test'\\
" "$file"
            fi
        fi
    fi
done

echo "✅ Fixed mock imports!"
echo ""
echo "Run 'npm test' to verify all tests pass"