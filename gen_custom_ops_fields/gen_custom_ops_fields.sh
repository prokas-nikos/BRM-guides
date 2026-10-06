#!/bin/bash
#############################################################################
# gen_custom_ops_fields.sh
#
# Regenerates custom_flds.h by querying the BRM data dictionary directly
# via PCM_OP_SDK_GET_FLD_SPECS, instead of using Developer Center's
# "Generate Custom Fields Source..." action. Then rebuilds the C (pcmc) and
# Java (pcmjava) custom field bindings and jars.
#
# testnap is always run from $pin_home/sys/test (it needs pin.conf / cwd
# context there to connect). The script cd's there to run testnap, then
# switches to $pin_home/include for everything else, so it can be started
# from any directory.
#
# Usage: ./gen_custom_ops_fields.sh <PIN_HOME>
#############################################################################

set -euo pipefail

# Input check
if [[ -z "${1:-}" || ! -d "$1" ]]; then
    echo "Usage: $0 <PIN_HOME>" >&2
    exit 1
fi

# Jars (pcm.jar) are kept only in the main CM, found via the PIN_HOME
# environment variable; the CM given as argument may be a dev CM.
if [[ -z "${PIN_HOME:-}" ]]; then
    echo "ERROR: PIN_HOME environment variable is not set." >&2
    exit 1
fi

# Resolve to an absolute path (the script cd's around)
pin_home=$(cd "$1" && pwd)

# Output helpers
step() { echo; echo "=== [$1] $2"; }
info() { echo "    $*"; }

# ---------------- Configurable block ----------------
TESTNAP_DIR="$pin_home/sys/test"
OUTPUT_DIR="$pin_home/include"
OUTPUT_FILE="$OUTPUT_DIR/custom_flds.h"
MIN_CUSTOM_FLD_NUM=10000       # anything >= this is considered "custom"
MAX_CUSTOM_FLD_NUM=99999       # adjust upper bound if you also want to exclude
                                # storable-class-reserved ranges etc.
FLD_PREFIX="LMT_FLD_"          # prefix used in the generated #defines
RAW_OUTPUT="/tmp/gen_custom_flds_raw.$$.txt"
CLASSPATH_JARS="$PIN_HOME/jars/pcm.jar:$PIN_HOME/jars/pcmext.jar"
# ------------------------------------------------------

cleanup() {
    rm -f "$RAW_OUTPUT"
}
trap cleanup EXIT

if [[ ! -d "$TESTNAP_DIR" ]]; then
    echo "ERROR: testnap directory not found: $TESTNAP_DIR" >&2
    exit 1
fi

step "1/5" "Querying data dictionary (PCM_OP_SDK_GET_FLD_SPECS via testnap)"
info "testnap dir: $TESTNAP_DIR"

pushd "$TESTNAP_DIR" > /dev/null

testnap <<'EOF' > "$RAW_OUTPUT" 2>&1
r << XXX 1
0 PIN_FLD_POID                      POID [0] 0.0.0.1 /dd/objects -1 0
XXX
d 1
xop PCM_OP_SDK_GET_FLD_SPECS 0 1
q
EOF

cp "$RAW_OUTPUT" /tmp/raw_capture_debug.txt

popd > /dev/null

# From here on, always work in the include directory.
cd "$OUTPUT_DIR"

# testnap dumps flists with the RAW_OUTPUT file now containing
# both the input echo (superOpcode debug lines don't appear here since
# we're not in Dev Center) and the output PIN_FLD_FIELD array.
# We just need lines from the response, so filter defensively:
#   - PIN_FLD_FIELD_NUM   ENUM [0] <num>
#   - PIN_FLD_FIELD_NAME  STR  [0] "<name>"
#   - PIN_FLD_FIELD_TYPE  INT  [0] <type>
# and group them per PIN_FLD_FIELD array element.

step "2/5" "Generating custom_flds.h from testnap output"

# Strip any CRLF line endings defensively (SSH/terminal capture, or if
# testnap output ever gets piped through something that adds \r) so
# field-splitting and numeric comparisons behave the same on every awk.
tr -d '\r' < "$RAW_OUTPUT" > "${RAW_OUTPUT}.lf"
mv "${RAW_OUTPUT}.lf" "$RAW_OUTPUT"

awk -v minnum="$MIN_CUSTOM_FLD_NUM" -v maxnum="$MAX_CUSTOM_FLD_NUM" -v prefix="$FLD_PREFIX" '
# Portable POSIX-awk parsing (no gawk-only match(...,arr) 3-arg extension,
# since the awk implementation on the target host is not guaranteed to be gawk).
#
# IMPORTANT: field order within each PIN_FLD_FIELD ARRAY[n] block is NOT
# guaranteed (NAME/NUM/TYPE can appear in different orders depending on
# how testnap was invoked/piped). We therefore buffer all three sub-fields
# per array block and only emit the #define when a NEW array block starts
# (or at EOF for the final block) -- never mid-block on any single field
# line. This avoids silently using stale values from the previous block.

function emit() {
    if (have_num && have_name && fnum+0 >= minnum+0 && fnum+0 <= maxnum+0) {
        # Map numeric PIN_FLDT_* type codes to symbolic macro names.
        # Verified against $PIN_HOME/include/pcm.h (PIN_FLDT_* defines) and
        # against the existing custom fields in custom_flds.h.
        # Codes not listed here (0 UNUSED, 2 UINT and 4 NUM are obsolete;
        # 15 TIME and 16 TEXTBUF are private/opaque) are emitted as
        # PIN_FLDT_UNKNOWN so any such field is caught for manual review
        # rather than silently mis-typed.
        type_str = "PIN_FLDT_UNKNOWN"
        if (ftype == 1)       type_str = "PIN_FLDT_INT"
        else if (ftype == 3)  type_str = "PIN_FLDT_ENUM"
        else if (ftype == 5)  type_str = "PIN_FLDT_STR"
        else if (ftype == 6)  type_str = "PIN_FLDT_BUF"
        else if (ftype == 7)  type_str = "PIN_FLDT_POID"
        else if (ftype == 8)  type_str = "PIN_FLDT_TSTAMP"
        else if (ftype == 9)  type_str = "PIN_FLDT_ARRAY"
        else if (ftype == 10) type_str = "PIN_FLDT_SUBSTRUCT"
        else if (ftype == 11) type_str = "PIN_FLDT_OBJ"
        else if (ftype == 12) type_str = "PIN_FLDT_BINSTR"
        else if (ftype == 13) type_str = "PIN_FLDT_ERR"
        else if (ftype == 14) type_str = "PIN_FLDT_DECIMAL"
        else if (ftype == 17) type_str = "PIN_FLDT_INT64"

        bare = fname
        sub(/^PIN_FLD_/, "", bare)
        sub(/^LMT_FLD_/, "", bare)

        printf "#define %s%s\t\tPIN_MAKE_FLD(%s, %s)\n", prefix, bare, type_str, fnum
    }
    have_num = 0; have_name = 0; have_type = 0
    fnum = ""; fname = ""; ftype = ""
}

/PIN_FLD_FIELD[ \t]+ARRAY[ \t]*\[/ {
    # Start of a new array block: flush whatever we buffered for the
    # previous block first, then reset.
    emit()
    next
}
/PIN_FLD_FIELD_TYPE/ {
    ftype = $NF
    have_type = 1
}
/PIN_FLD_FIELD_NUM/ {
    fnum = $NF
    have_num = 1
}
/PIN_FLD_FIELD_NAME/ {
    n = split($0, parts, "\"")
    fname = parts[2]
    have_name = 1
}
END {
    # flush the final buffered block
    emit()
}
' "$RAW_OUTPUT" > "$OUTPUT_FILE.tmp"

# Sort numerically by the field number embedded in PIN_MAKE_FLD(TYPE, NUM),
# and drop duplicate field numbers (keep first occurrence).
awk -F'[(), ]+' '
{
    fnum = $(NF-1)
    if (!(fnum in seen)) {
        seen[fnum] = 1
        print fnum, $0
    }
}' "$OUTPUT_FILE.tmp" | sort -k1,1n | cut -d' ' -f2- > "$OUTPUT_FILE.sorted"

mv "$OUTPUT_FILE.sorted" "$OUTPUT_FILE"
rm -f "$OUTPUT_FILE.tmp"

COUNT=$(wc -l < "$OUTPUT_FILE")
info "Wrote $COUNT custom field #defines to $OUTPUT_FILE"

step "3/5" "Building custom_ops_flds.h and C bindings (pcmc)"
if [[ -f "custom_ops.h" ]]; then
    cp custom_ops.h custom_ops_flds.h
    echo ' ' >> custom_ops_flds.h
    echo ' ' >> custom_ops_flds.h
    cat custom_flds.h >> custom_ops_flds.h
    info "custom_ops_flds.h = custom_ops.h + custom_flds.h"
else
    cp custom_flds.h custom_ops_flds.h
    info "custom_ops_flds.h = custom_flds.h (no custom_ops.h found)"
fi
dos2unix custom_ops_flds.h
parse_custom_ops_fields.pl -L pcmc -I custom_ops_flds.h -O custom_ops_flds

step "4/5" "Rebuilding customfields/ (Java)"
rm -rf customfields/*
parse_custom_ops_fields.pl -L pcmjava -I custom_ops.h -O customfields
parse_custom_ops_fields.pl -L pcmjava -I custom_flds.h -O customfields -P customfields
cd "$OUTPUT_DIR/customfields"
javac -d . *.java -classpath "$CLASSPATH_JARS"
jar -cf CustomFields.jar customfields/*.class CustomOp.class
info "Created $OUTPUT_DIR/customfields/CustomFields.jar"
cd "$OUTPUT_DIR"

step "5/5" "Rebuilding customfieldswsm/ (Java, web services)"
rm -rf customfieldswsm/*
parse_custom_ops_fields.pl -L pcmjava -I custom_ops_flds.h -O customfieldswsm -P com.portal.jax.custom
cd "$OUTPUT_DIR/customfieldswsm"
javac -d . *.java -classpath "$CLASSPATH_JARS"
jar -cf CustomFields.jar com/portal/jax/custom/*.class
info "Created $OUTPUT_DIR/customfieldswsm/CustomFields.jar"
cd "$OUTPUT_DIR"

# Restart the CM manually (or uncomment) for the new fields to take effect.
# "$pin_home/bin/stop_cm"
# "$pin_home/bin/start_cm"

echo
echo "=== Done. Review $OUTPUT_FILE before committing."
