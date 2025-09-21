#!/bin/bash

# Helper script to convert CoffeeScript files from ESM to CommonJS

echo "🔄 Converting ClodBrain from ESM to CommonJS..."
echo ""

# Function to convert a single file
convert_file() {
    local file=$1
    echo "Converting: $file"

    # Create a backup
    cp "$file" "$file.esm.bak"

    # Convert import statements to require
    # import { thing } from 'module' -> { thing } = require 'module'
    sed -i '' -E "s/^import \{ ([^}]+) \} from '([^']+)'/{ \1 } = require '\2'/g" "$file"

    # import thing from 'module' -> thing = require 'module'
    sed -i '' -E "s/^import ([a-zA-Z_][a-zA-Z0-9_]*) from '([^']+)'/\1 = require '\2'/g" "$file"

    # import 'module' -> require 'module'
    sed -i '' -E "s/^import '([^']+)'/require '\1'/g" "$file"

    # Remove .js extensions from local requires
    sed -i '' -E "s/require '(\.\.[^']+)\.js'/require '\1'/g" "$file"
    sed -i '' -E "s/require '(\.\/[^']+)\.js'/require '\1'/g" "$file"

    # export default -> module.exports =
    sed -i '' -E "s/^export default /module.exports = /g" "$file"

    # export name = -> exports.name =
    sed -i '' -E "s/^export ([a-zA-Z_][a-zA-Z0-9_]*) = /exports.\1 = /g" "$file"

    # export { name } -> exports.name = name (this is trickier, might need manual fix)
    sed -i '' -E "s/^export \{ ([a-zA-Z_][a-zA-Z0-9_]*) \}/exports.\1 = \1/g" "$file"

    echo "✅ Converted: $file"
}

# Convert source files
echo "Converting source files..."
find src -name "*.coffee" -type f | while read -r file; do
    if grep -q "^import\|^export" "$file"; then
        convert_file "$file"
    else
        echo "⏭️  Skipping $file (no ESM syntax found)"
    fi
done

echo ""
echo "Converting test files..."
find t -name "*.coffee" -type f | while read -r file; do
    if grep -q "^import\|^export" "$file"; then
        convert_file "$file"
    else
        echo "⏭️  Skipping $file (no ESM syntax found)"
    fi
done

echo ""
echo "Converting bin files..."
find bin -name "*.coffee" -type f | while read -r file; do
    if grep -q "^import\|^export" "$file"; then
        convert_file "$file"
    else
        echo "⏭️  Skipping $file (no ESM syntax found)"
    fi
done

echo ""
echo "🎉 Conversion complete!"
echo ""
echo "Next steps:"
echo "1. Review the changes: git diff"
echo "2. Run tests to verify: npm test"
echo "3. Remove backup files when satisfied: find . -name '*.esm.bak' -delete"
echo "4. Make sure package.json doesn't have \"type\": \"module\""
echo ""
echo "Manual fixes may be needed for:"
echo "- Complex export patterns"
echo "- Dynamic imports"
echo "- Import assertions"
echo "- Named exports with destructuring"