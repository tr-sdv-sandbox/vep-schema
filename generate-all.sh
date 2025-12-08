#!/bin/bash
# Generate Protobuf and DDS IDL from IFEX definitions
#
# Usage:
#   ./generate-all.sh           # Generate both proto and IDL
#   ./generate-all.sh proto     # Generate proto only
#   ./generate-all.sh idl       # Generate IDL only
#   ./generate-all.sh validate  # Validate IFEX files only
#   ./generate-all.sh shell     # Start interactive shell in container
#
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Check if image exists
if ! docker image inspect vep-schema-tools &>/dev/null; then
    echo "Docker image not found. Building..."
    ./build-tool.sh
fi

# Run container as current user so generated files have correct ownership
run_container() {
    docker run --rm \
        -v "$SCRIPT_DIR:/workspace" \
        -w /workspace \
        -u "$(id -u):$(id -g)" \
        --entrypoint /bin/bash \
        vep-schema-tools \
        -c "/usr/local/bin/entrypoint.sh $*"
}

case "${1:-all}" in
    proto)
        run_container generate-proto
        ;;
    idl)
        run_container generate-idl
        ;;
    validate)
        run_container validate
        ;;
    shell)
        # Shell needs interactive terminal, run as root for full access
        docker run --rm -it \
            -v "$SCRIPT_DIR:/workspace" \
            -w /workspace \
            --entrypoint /bin/bash \
            vep-schema-tools
        ;;
    all|"")
        run_container generate-all
        ;;
    *)
        echo "VEP Schema Generator"
        echo ""
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  all       Generate both proto and IDL (default)"
        echo "  proto     Generate Protobuf files only"
        echo "  idl       Generate DDS IDL files only"
        echo "  validate  Validate IFEX file syntax"
        echo "  shell     Start interactive shell in container"
        echo ""
        echo "Output:"
        echo "  generated/proto/  - Protobuf files"
        echo "  generated/idl/    - DDS IDL files"
        exit 1
        ;;
esac
