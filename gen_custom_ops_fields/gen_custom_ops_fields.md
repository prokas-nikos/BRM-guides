# gen_custom_ops_fields.sh

## Purpose

Regenerates the BRM custom field artifacts directly from the data dictionary, replacing Developer Center's **"Generate Custom Fields Source..."** GUI action.

It queries the dictionary with `PCM_OP_SDK_GET_FLD_SPECS` through `testnap`, rebuilds `custom_flds.h`, merges it with `custom_ops.h`, and then regenerates and recompiles the C (`pcmc`) and Java (`pcmjava`) field bindings, packaging them as jars.

## Usage

```bash
./gen_custom_ops_fields.sh <PIN_HOME>
```

| Argument | Description |
|----------|-------------|
| `PIN_HOME` | Path to the BRM installation. Must be an existing directory. |

**Run it from `$PIN_HOME/include`** (see [Known issues](#known-issues-and-caveats)).

### Prerequisites

- `testnap`, `parse_custom_ops_fields.pl`, `javac`, `jar` and `dos2unix` on the `PATH`
- A working BRM connection configured in `$PIN_HOME/sys/test` (`pin.conf`)
- `$PIN_HOME/jars/pcm.jar` and `pcmext.jar`
- Environment variable `PIN_HOME` set (used for the Java classpath, in addition to the argument)

## Configuration (top of script)

| Variable | Default | Meaning |
|----------|---------|---------|
| `TESTNAP_DIR` | `$pin_home/sys/test` | Directory testnap runs from |
| `OUTPUT_DIR` | `$pin_home/include` | Where `custom_flds.h` is written |
| `OUTPUT_FILE` | `$OUTPUT_DIR/custom_flds.h` | Generated header |
| `MIN_CUSTOM_FLD_NUM` | `10000` | Fields with numbers >= this are "custom" |
| `MAX_CUSTOM_FLD_NUM` | `99999` | Upper bound of the custom range |
| `FLD_PREFIX` | `LMT_FLD_` | Prefix for generated `#define` names |
| `RAW_OUTPUT` | `/tmp/gen_custom_flds_raw.$$.txt` | Temporary testnap capture (removed on exit) |

## What it does

### 1. Validate input
Exits with a usage message if the argument is missing or not a directory.

### 2. Query the data dictionary
Runs testnap from `$pin_home/sys/test` with:

```
r << XXX 1
0 PIN_FLD_POID  POID [0] 0.0.0.1 /dd/objects -1 0
XXX
d 1
xop PCM_OP_SDK_GET_FLD_SPECS 0 1
q
```

Output is captured to the temp file (and copied to `/tmp/raw_capture_debug.txt` for debugging).

### 3. Parse the response into `custom_flds.h`
- Strips CR characters for portability.
- A POSIX-awk parser (no gawk-only features) walks each `PIN_FLD_FIELD ARRAY[n]` block and buffers `PIN_FLD_FIELD_NAME`, `PIN_FLD_FIELD_NUM` and `PIN_FLD_FIELD_TYPE`. Because sub-field order inside a block is not guaranteed, a `#define` is emitted only when the **next** block starts (or at EOF).
- Only fields with a number within `[MIN_CUSTOM_FLD_NUM, MAX_CUSTOM_FLD_NUM]` are kept.
- Numeric type codes are mapped to symbolic names:

| Code | Macro | Status |
|------|-------|--------|
| 1 | `PIN_FLDT_INT` | verified |
| 3 | `PIN_FLDT_ENUM` | verified against existing fields |
| 5 | `PIN_FLDT_STR` | verified |
| 6 | `PIN_FLDT_BUF` | unverified |
| 7 | `PIN_FLDT_POID` | verified |
| 8 | `PIN_FLDT_TSTAMP` | verified |
| 9 | `PIN_FLDT_ARRAY` | verified |
| 10 | `PIN_FLDT_SUBSTRUCT` | verified |
| 11 | `PIN_FLDT_OBJ` | verified |
| 12 | `PIN_FLDT_BINSTR` | unverified |
| 13 | `PIN_FLDT_ERR` | unverified |
| 14 | `PIN_FLDT_DECIMAL` | verified |
| 17 | `PIN_FLD_HEADER_NUM` | as coded |
| other | `PIN_FLDT_UNKNOWN` | flags the field for manual review |

  The original comments state the mapping was cross-checked against the 130 existing custom fields (10000–10129) with zero conflicts.
- Names have `PIN_FLD_` / `LMT_FLD_` stripped and are re-prefixed with `LMT_FLD_`, producing lines like:

```c
#define LMT_FLD_EXAMPLE		PIN_MAKE_FLD(PIN_FLDT_STR, 10001)
```

### 4. Sort and de-duplicate
Duplicates by field number are dropped (first occurrence wins), the list is sorted numerically, and the result replaces `custom_flds.h`. The line count is reported.

> The timestamped backup of the previous header is **commented out**, so the old file is overwritten with no safety copy.

### 5. Build `custom_ops_flds.h`
- If `custom_ops.h` exists: `custom_ops.h` + blank lines + `custom_flds.h`.
- Otherwise: a copy of `custom_flds.h`.
- Runs `dos2unix` on the result.

### 6. Generate C bindings
```bash
parse_custom_ops_fields.pl -L pcmc -I custom_ops_flds.h -O custom_ops_flds
```

### 7. Rebuild `customfields/` (Java, standard package)
1. Empties `$pin_home/include/customfields/`.
2. Generates Java from `custom_ops.h` and `custom_flds.h` (package `customfields`).
3. Compiles against `pcm.jar` and `pcmext.jar`.
4. Packages `CustomFields.jar` containing `customfields/*.class` and `CustomOp.class`.

### 8. Rebuild `customfieldswsm/` (Java, web services package)
1. Empties `$pin_home/include/customfieldswsm/`.
2. Generates Java from `custom_ops_flds.h` with package `com.portal.jax.custom`.
3. Compiles and packages `CustomFields.jar` from `com/portal/jax/custom/*.class`.

### 9. CM restart (disabled)
The block that stops and starts the CM (`stop_cm` / `start_cm`) is commented out. Restart the CM manually for the new fields to take effect.

## Outputs

| Path | Content |
|------|---------|
| `$pin_home/include/custom_flds.h` | Regenerated custom field `#define`s |
| `$pin_home/include/custom_ops_flds.h` | Ops header + field header, LF line endings |
| `custom_ops_flds*` (C output of `pcmc`) | Generated C bindings |
| `$pin_home/include/customfields/CustomFields.jar` | Java bindings (includes `CustomOp`) |
| `$pin_home/include/customfieldswsm/CustomFields.jar` | Java bindings for BRM web services |
| `/tmp/raw_capture_debug.txt` | Raw testnap output kept for debugging |

## Known issues and caveats

1. **Missing argument gives a bash error, not the usage message.** With `set -u`, `"$1"` aborts with "unbound variable". Use `${1:-}`.
2. **Duplicate shebang and `set -euo pipefail`.** The header from a second script (`gen_custom_flds.sh`) was pasted in; the second shebang is just a comment and harmless, but redundant.
3. **`pin_home` vs `PIN_HOME`.** The argument sets `pin_home`, but the `javac` classpath uses `${PIN_HOME}`. If the environment variable points at a different install, the wrong jars are used. Consider `PIN_HOME="$pin_home"`.
4. **Working directory.** After `popd`, the script returns to the caller's directory. The `custom_ops.h` / `custom_flds.h` steps use relative paths, so it only works when invoked from `$pin_home/include`. Adding `cd "$pin_home/include"` after `popd` would remove that requirement.
5. **Relative `PIN_HOME` argument.** Later `cd` calls would break a relative path. Pass an absolute path.
6. **No backup.** The backup of the previous `custom_flds.h` is commented out. Re-enable it or commit the file to git before running.
7. **Unverified type codes.** BUF, BINSTR and ERR are marked unverified; new fields of those types may be mis-typed. `PIN_FLDT_UNKNOWN` in the output needs manual review.
8. **Type 17 mapping.** It maps to `PIN_FLD_HEADER_NUM` (a field macro, not a `PIN_FLDT_*` type), which looks suspicious.
9. **Possible stale-state risk.** `rm -rf customfields/*` runs before regeneration. If generation or compilation fails, the directory is left empty (`set -e` stops the script at that point).
10. **Missing `TIME` etc.** Some textbook types (UINT, TIME) are not in the mapping and would emit `PIN_FLDT_UNKNOWN`.
11. **Leftover debug echoes.** Several `echo " "` lines and commented-out echoes remain and can be tidied.
