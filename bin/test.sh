#!/bin/bash

# Test runner script for ClodBrain

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}🧠 ClodBrain Test Suite 🧠${NC}"
echo ""

# Check if running in CI or local
if [ "$CI" = "true" ]; then
    echo -e "${YELLOW}Running in CI mode${NC}"
else
    echo -e "${YELLOW}Running in local mode${NC}"
fi

# Install dependencies if needed
if [ ! -d "node_modules" ]; then
    echo -e "${BLUE}Installing dependencies...${NC}"
    npm install
fi

# Run different test suites based on arguments
case "$1" in
    "watch")
        echo -e "${BLUE}Starting test watcher...${NC}"
        npm run test:watch
        ;;

    "coverage")
        echo -e "${BLUE}Running tests with coverage...${NC}"
        npm run test:coverage
        echo -e "${GREEN}Coverage report generated in ./coverage${NC}"
        ;;

    "ui")
        echo -e "${BLUE}Starting Vitest UI...${NC}"
        npm run test:ui
        ;;

    "unit")
        echo -e "${BLUE}Running unit tests only...${NC}"
        npx vitest run test/services/
        ;;

    "integration")
        echo -e "${BLUE}Running integration tests only...${NC}"
        npx vitest run test/integration/
        ;;

    "quick")
        echo -e "${BLUE}Running quick smoke tests...${NC}"
        npx vitest run --reporter=dot --bail 3
        ;;

    "ci")
        echo -e "${BLUE}Running CI test suite...${NC}"
        # Run tests with coverage and fail on low coverage
        npx vitest run --coverage --reporter=json --reporter=default

        # Check coverage thresholds
        COVERAGE_RESULT=$?
        if [ $COVERAGE_RESULT -ne 0 ]; then
            echo -e "${RED}Tests failed!${NC}"
            exit 1
        fi

        echo -e "${GREEN}All tests passed!${NC}"
        ;;

    "specific")
        if [ -z "$2" ]; then
            echo -e "${RED}Please specify a test file or pattern${NC}"
            echo "Usage: $0 specific <pattern>"
            exit 1
        fi
        echo -e "${BLUE}Running tests matching: $2${NC}"
        npx vitest run "$2"
        ;;

    "debug")
        echo -e "${BLUE}Running tests in debug mode...${NC}"
        NODE_OPTIONS='--inspect-brk' npx vitest run --no-threads
        ;;

    *)
        echo -e "${BLUE}Running all tests...${NC}"
        npm test
        ;;
esac

# Exit with test result code
exit $?