#!/bin/bash
# Generate Protobuf, DDS IDL, and C/H files from IFEX definitions
#
# Usage:
#   ./generate-all.sh           # Generate proto, IDL, and C/H files
#   ./generate-all.sh proto     # Generate proto only
#   ./generate-all.sh idl       # Generate IDL only
#   ./generate-all.sh dds       # Generate C/H from IDL (requires idlc)
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

# Generate C/H files from IDL using idlc
generate_dds_sources() {
    echo "Generating DDS C/H files from IDL..."

    IDL_DIR="$SCRIPT_DIR/generated/idl"
    OUT_DIR="$SCRIPT_DIR/generated/c"

    # Check for idlc
    if ! command -v idlc &>/dev/null; then
        echo "Error: idlc not found. Install cyclonedds-dev package."
        exit 1
    fi

    # Check IDL files exist
    if [ ! -f "$IDL_DIR/types.idl" ]; then
        echo "Error: IDL files not found. Run './generate-all.sh idl' first."
        exit 1
    fi

    # Create output directory
    mkdir -p "$OUT_DIR"

    # List of IDL files to compile (in dependency order)
    IDL_FILES=(
        "types"
        "vss-signal"
        "avtp"
        "otel-metrics"
        "otel-logs"
        "diagnostics"
        "events"
        "opaque"
        "security"
        "uds-dtc"
    )

    # Compile each IDL file
    for idl in "${IDL_FILES[@]}"; do
        echo "  Compiling ${idl}.idl..."
        idlc -f keylist -l c -I"$IDL_DIR" -o "$OUT_DIR" "$IDL_DIR/${idl}.idl"
    done

    echo "Generated files in $OUT_DIR:"
    ls -la "$OUT_DIR"/*.c "$OUT_DIR"/*.h 2>/dev/null || echo "  (no files)"
}

case "${1:-all}" in
    proto)
        run_container generate-proto
        ;;
    idl)
        run_container generate-idl
        ;;
    dds)
        generate_dds_sources
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
        generate_dds_sources
        ;;
    *)
        echo "VEP Schema Generator"
        echo ""
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  all       Generate proto, IDL, and C/H files (default)"
        echo "  proto     Generate Protobuf files only"
        echo "  idl       Generate DDS IDL files only"
        echo "  dds       Generate C/H files from IDL (requires idlc)"
        echo "  validate  Validate IFEX file syntax"
        echo "  shell     Start interactive shell in container"
        echo ""
        echo "Output:"
        echo "  generated/proto/  - Protobuf files"
        echo "  generated/idl/    - DDS IDL files"
        echo "  generated/c/      - C/H files for DDS (from idlc)"
        exit 1
        ;;
esac
