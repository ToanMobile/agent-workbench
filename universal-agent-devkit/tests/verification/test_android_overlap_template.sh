#!/usr/bin/env bash
. "$(cd "$(dirname "$0")/../.." && pwd)/tests/lib/clean_git_env.sh"
set -u

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
FAILS=0
ok()  { echo "✔ $1"; }
bad() { echo "✖ $1"; FAILS=$((FAILS + 1)); }

TEMPLATE_DIR="$(cd "$(dirname "$0")/../.." && pwd)/profiles/android/templates/compose-overlap-invariants"
DEVKIT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

if [ ! -d "$TEMPLATE_DIR" ]; then
    bad "Template directory $TEMPLATE_DIR does not exist"
else
    # Check required files
    for f in README.md OverlapInvariants.kt config.csv ExampleOverlapTest.kt; do
        if [ ! -f "$TEMPLATE_DIR/$f" ]; then
            bad "Missing required file: $f"
        fi
    done

    # Check NO placeholders
    if grep -riE "Logic to check|TODO" "$TEMPLATE_DIR"; then
        bad "Found placeholders in template files"
    fi

    if [ -f "$TEMPLATE_DIR/README.md" ]; then
        README_CONTENT=$(cat "$TEMPLATE_DIR/README.md")
        
        # Check README mentions ALL real files in the directory
        for file in "$TEMPLATE_DIR"/*; do
            filename=$(basename "$file")
            if ! echo "$README_CONTENT" | grep -q "$filename"; then
                bad "README missing mention of file: $filename"
            fi
        done
        
        if ! echo "$README_CONTENT" | grep -q "compose-ui-test"; then
            bad "README missing dependency: compose-ui-test"
        fi
        if ! echo "$README_CONTENT" | grep -q "Robolectric"; then
            bad "README missing dependency: Robolectric"
        fi
        if ! echo "$README_CONTENT" | grep -q "working dir"; then
            bad "README missing note about CSV working dir"
        fi
    else
        bad "README.md missing"
    fi

    # Check Kotlin files
    for KT_FILE in "$TEMPLATE_DIR"/*.kt; do
        if [ -f "$KT_FILE" ]; then
            if ! grep -q "^package " "$KT_FILE"; then
                bad "Missing package in Kotlin file $KT_FILE"
            fi
            if ! grep -q "^import " "$KT_FILE"; then
                bad "Missing import in Kotlin file $KT_FILE"
            fi
            
            if [[ "$KT_FILE" == *"OverlapInvariants.kt"* ]]; then
                if ! grep -q "setQualifiers" "$KT_FILE"; then
                    bad "OverlapInvariants.kt missing setQualifiers"
                fi
            fi

            # Check bracket balance
            OPEN_BRACKETS=$(grep -o "{" "$KT_FILE" | wc -l)
            CLOSE_BRACKETS=$(grep -o "}" "$KT_FILE" | wc -l)
            if [ "$OPEN_BRACKETS" -ne "$CLOSE_BRACKETS" ]; then
                bad "Unbalanced brackets in $KT_FILE"
            fi
        fi
    done

    # Check CSV
    CSV_FILE="$TEMPLATE_DIR/config.csv"
    if [ -f "$CSV_FILE" ]; then
        HEADER=$(head -n 1 "$CSV_FILE")
        if [ "$HEADER" != "id,isLandscape,isGestureNav,statusInset,navInset,cutoutInset,fontScale,isRtl" ]; then
            bad "CSV header does not match WindowConfig fields"
        fi
        
        if ! grep -q ",false,true," "$CSV_FILE"; then
            bad "CSV missing portrait gesture row"
        fi
        if ! grep -q ",false,false," "$CSV_FILE"; then
            bad "CSV missing portrait 3-button row"
        fi
        if ! grep -q ",true,true," "$CSV_FILE"; then
            bad "CSV missing landscape gesture row"
        fi
        if ! grep -q ",true,false," "$CSV_FILE"; then
            bad "CSV missing landscape 3-button row"
        fi
    else
        bad "config.csv missing"
    fi
fi

RULE_TEXT_FILE="$DEVKIT_DIR/profiles/android/rules/android-rules.md"
if [ -f "$RULE_TEXT_FILE" ]; then
    RULE_TEXT=$(cat "$RULE_TEXT_FILE")
    if ! echo "$RULE_TEXT" | grep -q "bảng cấu hình" && ! echo "$RULE_TEXT" | grep -q "ma trận trạng thái" && ! echo "$RULE_TEXT" | grep -q "compose-overlap-invariants"; then
        bad "Rule text missing mention of bảng cấu hình/ma trận trạng thái/compose-overlap-invariants"
    fi
else
    bad "Rule file $RULE_TEXT_FILE does not exist"
fi

if [ "$FAILS" = 0 ]; then
    echo "ALL OK"
    exit 0
else
    echo "$FAILS FAILED"
    exit 1
fi
