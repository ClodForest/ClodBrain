#!/bin/bash

# Test runner script for ClodBrain using Node.js built-in test runner

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}🧠 ClodBrain Test Suite (Node.js Test Runner) 🧠${NC}"
echo ""

# Common test command parts
NODE_CMD="coffee --nodejs"
TEST_FILES="t/**/*.test.coffee"

# Run different test suites based on arguments
case "$1" in
    "watch")
        echo -e "${BLUE}Starting test watcher...${NC}"
        $NODE_CMD "--test --watch" $TEST_FILES
        ;;

    "coverage")
        echo -e "${BLUE}Running tests with coverage...${NC}"
        $NODE_CMD "--experimental-test-coverage --test" $TEST_FILES
        ;;

    "unit")
        echo -e "${BLUE}Running unit tests only...${NC}"
        $NODE_CMD "--test" t/services/*.test.coffee
        ;;

    "integration")
        echo -e "${BLUE}Running integration tests only...${NC}"
        $NODE_CMD "--test" t/integration/*.test.coffee
        ;;

    "quick")
        echo -e "${BLUE}Running quick smoke tests...${NC}"
        # Run with concurrency for speed
        $NODE_CMD "--test --test-concurrency=4" $TEST_FILES
        ;;

    "specific")
        if [ -z "$2" ]; then
            echo -e "${RED}Please specify a test file or pattern${NC}"
            echo "Usage: $0 specific <pattern>"
            exit 1
        fi
        echo -e "${BLUE}Running tests matching: $2${NC}"
        $NODE_CMD "--test" "t/**/*$2*.test.coffee"
        ;;

    "only")
        echo -e "${BLUE}Running tests marked with 'only'...${NC}"
        $NODE_CMD "--test --test-only" $TEST_FILES
        ;;

    "reporter")
        REPORTER="${2:-spec}"
        echo -e "${BLUE}Running tests with $REPORTER reporter...${NC}"
        $NODE_CMD "--test --test-reporter=$REPORTER" $TEST_FILES
        ;;

    "debug")
        echo -e "${BLUE}Running tests in debug mode...${NC}"
        $NODE_CMD "--inspect-brk --test" $TEST_FILES
        ;;

    *)
        echo -e "${BLUE}Running all tests...${NC}"
        $NODE_CMD "--test" $TEST_FILES
        ;;
esac

# Exit with test result code
exit $?