#!/bin/bash
# Build the vep-schema-tools Docker image
#
# Usage: ./build-tool.sh
#
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Building vep-schema-tools Docker image..."
docker build --network=host -t vep-schema-tools -f tools/docker/Dockerfile .

echo ""
echo "Built: vep-schema-tools"
echo ""
echo "Usage:"
echo "  ./generate-all.sh           # Generate proto and IDL from IFEX"
echo "  ./generate-all.sh proto     # Generate proto only"
echo "  ./generate-all.sh idl       # Generate IDL only"
echo "  ./run-tests.sh              # Run test suite"
