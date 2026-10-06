#!/bin/bash

set -euo pipefail

# Input check
if [[ -z "$1" || ! -d "$1" ]]; then
    echo "Parameter: $0 [\$PIN_HOME]"
    exit 1
fi

pin_home=$1

#!/bin/bash
#############################################################################
# gen_custom_flds.sh
#
# Regenerates custom_flds.h by querying the BRM data dictionary directly
# via PCM_OP_SDK_GET_FLD_SPECS, instead of using Developer Center's
# "Generate Custom Fields Source..." action.
#
# Must be able to be invoked from $pin_home/include, but testnap itself
# is always run from $pin_home/sys/test (it needs pin.conf / cwd context
# there to connect). We cd there to run testnap, then come back.
#
# Usage: ./gen_custom_flds.sh   (run from $pin_home/include)
#############################################################################

set -euo pipefail

# ---------------- Configurable block ----------------
TESTNAP_DIR="$pin_home/sys/test"
OUTPUT_DIR="$pin_home/include"
OUTPUT_FILE="$OUTPUT_DIR/custom_flds.h"
MIN_CUSTOM_FLD_NUM=10000       # anything >= this is considered "custom"
MAX_CUSTOM_FLD_NUM=99999       # adjust upper bound if you also want to exclude
                                # storable-class-reserved ranges etc.
FLD_PREFIX="LMT_FLD_"          # prefix used in the generated #defines
RAW_OUTPUT="/tmp/gen_custom_flds_raw.$$.txt"
# ------------------------------------------------------

cleanup() {
    rm -f "$RAW_OUTPUT"
}
trap cleanup EXIT

if [[ ! -d "$TESTNAP_DIR" ]]; then
    echo "ERROR: testnap directory not found: $TESTNAP_DIR" >&2
    exit 1
fi

echo "Running PCM_OP_SDK_GET_FLD_SPECS via testnap in $TESTNAP_DIR ..."

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

# testnap dumps flists with the RAW_OUTPUT file now containing
# both the input echo (superOpcode debug lines don't appear here since
# we're not in Dev Center) and the output PIN_FLD_FIELD array.
# We just need lines from the response, so filter defensively:
#   - PIN_FLD_FIELD_NUM   ENUM [0] <num>
#   - PIN_FLD_FIELD_NAME  STR  [0] "<name>"
# and pair them up, since they appear as consecutive lines per array element.

echo "Parsing testnap output -> $OUTPUT_FILE"

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
        # This mapping was reverse-derived and VERIFIED against your actual
        # LMT dictionary: all 130 existing custom fields (10000-10129) in
        # custom_flds.h were cross-checked against their live FIELD_TYPE
        # codes from PCM_OP_SDK_GET_FLD_SPECS output, with zero conflicts.
        # NOTE: codes 2 (UINT), 4 (BINSTR), 6 (BUF), 13 (ERR), 15 (TIME),
        # 3 (ENUM, not STR) are textbook PIN_FLDT_* guesses that were NOT
        # seen in your data and are unverified -- flagged UNKNOWN so any
        # new field using them is caught for manual review rather than
        # silently mis-typed.
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
        else if (ftype == 17) type_str = "PIN_FLD_HEADER_NUM"

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

# Back up the existing header (if any) before overwriting, so a bad
# parse/run never destroys the previous known-good file silently.
# if [[ -f "$OUTPUT_FILE" ]]; then
#     cp "$OUTPUT_FILE" "$OUTPUT_FILE.bak.$(date +%Y%m%d_%H%M%S)"
# fi

mv "$OUTPUT_FILE.sorted" "$OUTPUT_FILE"
rm -f "$OUTPUT_FILE.tmp"

COUNT=$(wc -l < "$OUTPUT_FILE")
echo "Wrote $COUNT custom field #defines to $OUTPUT_FILE"
# echo "Previous version (if any) backed up alongside it as .bak.<timestamp>"
echo "Review before committing, e.g.:"
# echo "  diff $OUTPUT_FILE $OUTPUT_FILE.bak.* | tail"
echo " "
echo " "
echo " "


if [[ -f "custom_ops.h" ]]; then
    cp custom_ops.h custom_ops_flds.h
    echo ' ' >> custom_ops_flds.h
    echo ' ' >> custom_ops_flds.h
    cat custom_flds.h >> custom_ops_flds.h
else
    cp custom_flds.h custom_ops_flds.h
fi
dos2unix custom_ops_flds.h

parse_custom_ops_fields.pl -L pcmc -I custom_ops_flds.h -O custom_ops_flds
echo ''


echo 'Updating customfields/'
cd $pin_home/include
rm -rf customfields/*
parse_custom_ops_fields.pl -L pcmjava -I custom_ops.h -O customfields
parse_custom_ops_fields.pl -L pcmjava -I custom_flds.h -O customfields -P customfields
echo ''
cd $pin_home/include/customfields
javac -d  . *.java -classpath ${PIN_HOME}/jars/pcm.jar:${PIN_HOME}/jars/pcmext.jar
echo ''
jar -cvf CustomFields.jar customfields/*.class CustomOp.class
echo ''

echo 'Updating customfieldswsm/'
cd $pin_home/include
rm -rf customfieldswsm/*
echo ''
parse_custom_ops_fields.pl -L pcmjava -I custom_ops_flds.h -O customfieldswsm -P com.portal.jax.custom
echo ''
cd $pin_home/include/customfieldswsm
javac -d . *.java -classpath ${PIN_HOME}/jars/pcm.jar:${PIN_HOME}/jars/pcmext.jar
echo ''
jar -cvf CustomFields.jar com/portal/jax/custom/*.class
echo ''

# echo 'Restarting CM'
# echo "Stopping CM..."
# ${pin_home}/bin/stop_cm
# # rm -f ${pin_home}/var/cm/cm.pinlog 
# # echo "cm.pinlog removed!!!" 
# echo "Starting CM..." 
# ${pin_home}/bin/start_cm


cd $pin_home/include
