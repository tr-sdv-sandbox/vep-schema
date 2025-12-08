#!/bin/bash
# VEP Schema tools entrypoint
set -e

IFEX_DIR="/workspace/ifex"
OUT_DIR="/workspace/generated"

# Custom templates take precedence over IFEX defaults
PROTO_TEMPLATE="/workspace/templates/protobuf"
IDL_TEMPLATE="/workspace/templates/dds-idl"

case "$1" in
    validate)
        echo "Validating IFEX files..."
        for f in "$IFEX_DIR"/*.ifex; do
            echo "  Checking: $(basename "$f")"
            python -c "
import yaml
import sys
try:
    with open('$f', 'r') as file:
        data = yaml.safe_load(file)
    if 'name' not in data or 'namespaces' not in data:
        print('  ERROR: Missing required fields (name, namespaces)')
        sys.exit(1)
    print('  OK')
except Exception as e:
    print(f'  ERROR: {e}')
    sys.exit(1)
"
        done
        echo "All files valid."
        ;;

    generate-proto)
        echo "Generating Protobuf from IFEX..."
        mkdir -p "$OUT_DIR/proto"

        # Use custom template if available, otherwise fall back to IFEX default
        if [ -d "$PROTO_TEMPLATE" ]; then
            TEMPLATE_DIR="$PROTO_TEMPLATE"
            echo "  Using custom template: templates/protobuf"
        else
            TEMPLATE_DIR="/opt/ifex/ifex/output_filters/templates/protobuf"
            echo "  Using IFEX default template"
        fi

        if [ -d "$TEMPLATE_DIR" ]; then
            for f in "$IFEX_DIR"/*.ifex; do
                name=$(basename "$f" .ifex)
                echo "  Processing: $name.ifex"
                if ifexgen -d "$TEMPLATE_DIR" "$f" > "$OUT_DIR/proto/$name.proto" 2>&1; then
                    echo "    → $name.proto"
                else
                    echo "    Warning: generation failed for $name"
                    cat "$OUT_DIR/proto/$name.proto"
                fi
            done
            echo ""
            echo "Generated files in $OUT_DIR/proto/"
        else
            echo "ERROR: Protobuf template not available"
            exit 1
        fi
        ;;

    generate-idl)
        echo "Generating DDS IDL from IFEX..."
        mkdir -p "$OUT_DIR/idl"

        # Use custom template (required - IFEX has no IDL template)
        if [ -d "$IDL_TEMPLATE" ]; then
            TEMPLATE_DIR="$IDL_TEMPLATE"
            echo "  Using custom template: templates/dds-idl"
        else
            echo "ERROR: DDS IDL template not found at templates/dds-idl/"
            echo "  IFEX does not include a DDS IDL template."
            echo "  Please ensure templates/dds-idl/AST_dds-idl.tpl exists."
            exit 1
        fi

        for f in "$IFEX_DIR"/*.ifex; do
            name=$(basename "$f" .ifex)
            echo "  Processing: $name.ifex"
            if ifexgen -d "$TEMPLATE_DIR" "$f" > "$OUT_DIR/idl/$name.idl" 2>&1; then
                echo "    → $name.idl"
            else
                echo "    Warning: generation failed for $name"
                cat "$OUT_DIR/idl/$name.idl"
            fi
        done
        echo ""
        echo "Generated files in $OUT_DIR/idl/"
        ;;

    generate-dbus)
        echo "Generating D-Bus XML from IFEX..."
        mkdir -p "$OUT_DIR/dbus"
        TEMPLATE_DIR="/opt/ifex/ifex/output_filters/templates/D-Bus"
        if [ -d "$TEMPLATE_DIR" ]; then
            for f in "$IFEX_DIR"/*.ifex; do
                echo "  Processing: $(basename "$f")"
                ifexgen -d "$TEMPLATE_DIR" "$f" > "$OUT_DIR/dbus/$(basename "$f" .ifex).xml" 2>&1 || echo "  Warning: generation failed"
            done
            echo "Generated files in $OUT_DIR/dbus/"
        else
            echo "D-Bus template not available"
        fi
        ;;

    generate-all)
        echo "Generating all outputs from IFEX..."
        echo ""
        $0 generate-proto
        echo ""
        $0 generate-idl
        echo ""
        echo "Done."
        ;;

    shell)
        echo "Starting interactive shell..."
        exec /bin/bash
        ;;

    ifexgen)
        shift
        exec ifexgen "$@"
        ;;

    help|*)
        echo "VEP Schema Tools"
        echo ""
        echo "Usage: docker run --rm -v \$(pwd):/workspace vep-schema-tools <command>"
        echo ""
        echo "Commands:"
        echo "  validate        Validate all IFEX files in ifex/"
        echo "  generate-proto  Generate Protobuf from IFEX"
        echo "  generate-idl    Generate DDS IDL from IFEX"
        echo "  generate-dbus   Generate D-Bus XML from IFEX"
        echo "  generate-all    Generate all outputs (proto + idl)"
        echo "  shell           Start interactive bash shell"
        echo "  ifexgen <args>  Run ifexgen directly with arguments"
        echo "  help            Show this help"
        echo ""
        echo "Output directories:"
        echo "  generated/proto/  - Protobuf files"
        echo "  generated/idl/    - DDS IDL files"
        echo "  generated/dbus/   - D-Bus XML files"
        echo ""
        echo "IFEX version:"
        pip show ifex 2>/dev/null | grep Version || echo "  ifex not found"
        ;;
esac
