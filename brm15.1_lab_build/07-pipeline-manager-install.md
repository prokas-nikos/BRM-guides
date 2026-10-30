# Installing Pipeline Manager (IFW) on BRM 15.1

Pipeline Manager is added to an existing BRM install by relaunching the **same** server installer.
On this build the software installed fine but the database schema silently did not — because of
one character in a password. This guide covers the install, the failure, the manual schema
build that fixed it, then the environment setup, first start and a sample CDR test.

## Database preparation

Tablespaces in PDB1, sized deliberately (the datafiles sit on `/u02`, which is the root
filesystem):

```sql
alter session set container = PDB1;
create tablespace IFW_TABLE datafile size 300M autoextend on next 64K maxsize 4G;
create tablespace IFW_INDEX datafile size 200M autoextend on next 64K maxsize 4G;
```

If you skip this, the installer's `createDBUser.sql` creates `ifw_table` (600M) and `ifw_index`
(400M) itself, with no maxsize.

The installer also asks for a database **system** user (windows "Pipeline Database System User
Details" and "BRM Database System User Details"). It connects that user **`as sysdba`**, which
`SYSTEM` does not hold by default — the result is `ORA-01031: insufficient privileges`. The install
guide never mentions this; it comes from `$PIN_HOME/setup/scripts/pin_oracle_functions.pl`.

```sql
alter session set container = PDB1;
grant sysdba to system;
-- after the install, optionally: revoke sysdba from system;
```

Take a restore point first (as `oracle`):

```sql
alter session set container = PDB1;
create restore point BEFORE_PIPELINE guarantee flashback database;
```

## Running the installer

```bash
$JAVA_HOME/bin/java -jar brmserver_15.1.0.0.0_linux_generic_full.jar \
    -record -destinationFile ~/brm_installation/brm_pipeline.rsp
```

| Window | Answer |
|---|---|
| Installation Location | `/app/pin` — the same Oracle home as the BRM server |
| Installation Type | **Custom** |
| Components | **Pipeline Manager only** (plus the optional managers you want) |
| Pipeline schema user | `ifw`, tablespaces `ifw_table` / `ifw_index` |
| DB alias | `pdb1` |

Already-installed components cannot be selected again — the guide: *"If you already installed a
component, you must uninstall its features before reinstalling them."* The same rule means a failed
Pipeline install cannot simply be re-run; fix it in place (below).

Result: `IFW_HOME=/app/pin/ifw` (~180 MB), with its own `source.me.sh`.

## Use a plain password for `ifw`

**Letters, digits and underscore only.** The installer builds the schema user with:

```sql
-- /app/pin/ifw/database/Oracle/Scripts/createDBUser.sql
EXECUTE IMMEDIATE 'create user ifw identified by &1 default tablespace ifw_table ...';
```

`&1` is substituted **unquoted**. A password containing `.` (or any other character that is not
legal in an unquoted Oracle identifier) breaks the statement.

### What it looks like

The installer finishes and reports success-ish. The damage is only in the logs:

```
$ cat /app/pin/ifw/database/Oracle/Scripts/createDBUser.log
ORA-20005: DB User ifw creation has failed ORA-00922: missing or invalid option

$ cat /app/pin/ifw/ifw_Create.log
ORA-01017: invalid username/password; logon denied
Enter user-name: Enter password:
ORA-12162: TNS:net service name is incorrectly specified
SP2-0157: unable to CONNECT to ORACLE after 3 attempts, exiting SQL*Plus
```

`ORA-00922` is the real failure. Everything after it is a consequence: `ifw` does not exist, so
`ifw_Create.sql`, `ifw_Synonyms.sql` and `insertWIRELESS_SAMPLE.sql` all get `ORA-01017`. The
`ORA-12162` lines are just sqlplus re-prompting with empty input. **Do not chase the TNS error.**

The full sequence the installer ran is in the OUI log:

```bash
grep -E 'sqlScript =' /u01/app/oraInventory/logs/install<timestamp>.log
```

| Script | Connects as | |
|---|---|---|
| `/app/pin/setup/scripts/createPackages.sql` | system | OK |
| `ifw/database/Oracle/Scripts/createRoles.sql` | system | OK |
| `ifw/database/Oracle/Scripts/createDBUser.sql` | system | **ORA-00922** |
| `ifw/ifw_Create.sql` | ifw@pdb1 | failed |
| `ifw/database/Oracle/Scripts/ifw_Synonyms.sql` | ifw@pdb1 | failed |
| `ifw/insertWIRELESS_SAMPLE.sql` | ifw@pdb1 | failed |

Note: the OUI log records the `ifw` connect string — **password included, in clear text** — on the
`Exit code for command` lines. Treat that password as exposed.

## Fixing it: build the schema by hand

The software is fine; only the last four steps need redoing.

### 1. Create `ifw` (as `oracle`, `sqlplus / as sysdba`)

The installer's own statement, with the password double-quoted. Use the same password you gave the
installer — it is already written into the Pipeline configuration.

```sql
alter session set container = PDB1;
create user ifw identified by "<IFW_PASSWORD>" default tablespace ifw_table temporary tablespace TEMP quota unlimited on ifw_table quota unlimited on ifw_index;
grant create public synonym, create synonym, drop public synonym, create any view, create sequence, create table, create any index, create procedure, resource, connect, alter session, create database link, execute any type, select any table to ifw;
grant unlimited tablespace to ifw;
```

Check from the `pin` shell: `sqlplus ifw@pdb1` must connect.

### 2. Run the three scripts (as `pin`, as `ifw`)

Paths are relative to where sqlplus starts, so start it in `/app/pin/ifw`. Spool each script to its
own log:

```bash
cd /app/pin/ifw
sqlplus ifw@pdb1
```
```sql
spool /app/pin/ifw/ifw_Create_rerun.log
@ifw_Create.sql
spool off

spool /app/pin/ifw/ifw_Synonyms_rerun.log
@database/Oracle/Scripts/ifw_Synonyms.sql
spool off

spool /app/pin/ifw/insertWIRELESS_SAMPLE_rerun.log
@insertWIRELESS_SAMPLE.sql
```

- **Type `spool off` and the next `spool` as separate lines, one at a time.** Pasted as a block, the
  newline between them got lost twice on this build, giving
  `spool offspool ...` → `SP2-0768: Illegal SPOOL command`. The old spool stays open and every
  following script's output lands in the *first* log file. Harmless to the database, confusing in
  the logs.
- `insertWIRELESS_SAMPLE.sql` ends with `exit`, so it must be last; it closes the spool and returns
  you to the shell.
- **Run `insertWIRELESS_SAMPLE.sql` exactly once.** A second run mostly fails with `ORA-00001`
  (harmless), but `IFW_DISCOUNTSTEP` and `IFW_DSCTRIGGER` have no unique key on the sample rows, so
  **8 duplicate rows** go in. The clean fix is to rewind:

  ```sql
  -- as oracle, sqlplus / as sysdba, in CDB$ROOT
  alter pluggable database PDB1 close immediate;
  flashback pluggable database PDB1 to restore point BEFORE_IFW_SCHEMA;
  alter pluggable database PDB1 open resetlogs;
  ```
  then repeat steps 1 and 2. Take `BEFORE_IFW_SCHEMA` before step 1 for exactly this reason.

### 3. Verify

```bash
cd /app/pin/ifw
grep -h -o -E '(ORA|SP2|PLS)-[0-9]+' *_rerun.log | sort | uniq -c
grep -h -E -o '^(Table|Index|Sequence|View|Synonym|Procedure) created\.' *_rerun.log | sort | uniq -c
grep -h -E -o '^[0-9]+ rows? created\.' *_rerun.log | wc -l
```

Expected on a clean build:

| | Count |
|---|---|
| `ORA-` errors | **0** |
| Tables / indexes / sequences / procedures / views | 124 / 45 / 40 / 3 / 1 |
| `Table altered.` (constraints) | 161 |
| Synonyms | 169 |
| Rows inserted | 3807 (212 from `ifw_Create.sql` + 3595 sample) |

`SP2-0768` lines only mean a spool command was mangled — see above.

## Environment

All commands from here on run as `pin`.

### 1. Load both `source.me.sh` files from `~/.bashrc`

BRM and IFW each ship their own `source.me.sh`. `ifw` needs both: its own libraries in
`/app/pin/ifw/lib`, and BRM's (`libportal.so` and others) in `/app/pin/BRM/lib`.

```bash
# ~/.bashrc (relevant part)
export LD_LIBRARY_PATH=$ORACLE_HOME/lib
export PIN_HOME=/app/pin/BRM
...
. "$PIN_HOME/source.me.sh"
. /app/pin/ifw/source.me.sh
```

**Do not wrap the BRM line in a "load once" guard.** This build originally had:

```bash
if [ -z "$BRM_ENV_LOADED" ] && [ -f "$PIN_HOME/source.me.sh" ]; then
    . "$PIN_HOME/source.me.sh"
    export BRM_ENV_LOADED=1
fi
```

`export LD_LIBRARY_PATH=$ORACLE_HOME/lib` above it runs every time, but the guard skips the BRM
part in any shell that inherited `BRM_ENV_LOADED=1` (a sub-shell, `su - pin` from a pin shell,
or re-running `. ~/.bashrc`). `/app/pin/BRM/lib` is then gone from the path, and:

```
$ ifw -r conf/wireless.reg
ifw: error while loading shared libraries: libportal.so: cannot open shared object file: No such file or directory
```

After editing `~/.bashrc`, **log out and back in**. Re-sourcing it is not enough while the old
`BRM_ENV_LOADED` is still set. Check it:

```bash
echo $IFW_HOME                                  # /app/pin/ifw
ldd $IFW_HOME/bin/ifw | grep "not found"        # no output
```

Also remove any stale `export PIN_HOME=...` lines left from earlier attempts. Only
`PIN_HOME=/app/pin/BRM` should remain.

### 2. Set the event handler port in `/app/pin/ifw/source.me.sh`

With the libraries fixed, `ifw` stops at:

```
Error: IFW_EVENTHANDLER_PORT not set in environment, cannot proceed.
```

`ifw` reads this port from the environment. The installer does not set it anywhere. It is IFW
configuration, so it goes in IFW's own `source.me.sh`. Add these lines after the existing
`export` lines at the end:

```bash
IFW_EVENTHANDLER_PORT=26000
export IFW_EVENTHANDLER_PORT
```

- 26000 matches a working reference install. Any free port will do. Check with `ss -ltn`.
- Each running `ifw` instance needs its own port. `bin/start_ifw_realtime` and
  `bin/stop_ifw_realtime` copy it from `IFWRT_EVENTHANDLER_PORT`, so set that too (to a different
  port) only if you run the real-time pipeline with those scripts. The reference install does not
  set it.
- A BRM patch or reinstall may overwrite `source.me.sh`, so re-check this after patching.

Log out and back in, then: `echo $IFW_EVENTHANDLER_PORT` → `26000`.

## Database logins

`conf/wireless.reg` has `UserName`, `DatabaseName` and `AccessLib` in its `Login` (`ifw`),
`LoginInfranet` (`pin`) and `LoginQueue` (`pin`) blocks, but **no `PassWord` lines**. That is
expected. The passwords are read from the BRM wallet (`/app/pin/BRM/wallet`), which the
installer filled in, even though the schema step itself failed on this build. A working reference
install looks the same. Nothing to edit. The first start below proves the logins work.

## First start

```bash
cd $IFW_HOME
ifw -r conf/wireless.reg
```

It runs in the foreground. Leave it running and use a second terminal for the rest. **Check the
hostname in your prompt.** On this build the first "start" went to the wrong SSH tab, a
different box.

### What a clean start looks like

In `log/process/processWIRELESS.log`:

```
INF_DATABASE_OPENED | Database 'pdb1' version 'UNKNOWN' opened with user 'ifw'.
INF_DATABASE_OPENED | Database 'pdb1' version 'UNKNOWN' opened with user 'pin'.   (LoginInfranet)
INF_DATABASE_OPENED | Database 'pdb1' version 'UNKNOWN' opened with user 'pin'.   (LoginQueue)
...
INF_PARALLEL_INIT_FINISHED | Parallel initialization of 'ifw' finished.
INF_PIPELINE_START | The pipeline 'ifw.Pipelines.PRE_PROCESS' is started (active).
INF_PIPELINE_START | The pipeline 'ifw.Pipelines.PRE_RECYCLE' is started (active).
INF_PIPELINE_START | The pipeline 'ifw.Pipelines.ALL_RATE' is started (active).
```

Check the severities:

```bash
cd $IFW_HOME/log
grep -h -o -E "\b(CRITICAL|MAJOR|MINOR|WARNING|NORMAL)\b" process/processWIRELESS.log pipeline/*.log | sort | uniq -c
```

This build: 833 `NORMAL`, 65 `WARNING`, nothing higher. The warnings come from optional registry
entries that the sample `wireless.reg` leaves out, and are harmless for a lab:

- `ERR_REG_NAME_NOT_FOUND | Registry name '...Output...Sequencer' not found.` (one per output module)
- `ERR_REG_SUBTREE_NOT_FOUND | ... 'ifw.Pipelines.ALL_RATE.Output.Statistic' not found.`
- `... Output.MultiThreading' not found. Setting default value of 'FALSE'.`
- `WRN_NO_SCENARIOS_CONFIGURED` (Aggregate), `WRN_FIELD_MAP_NOT_FOUND | 'EdrFieldMap'` (Suspense)

## Test: push a sample CDR through

The `PRE_PROCESS` pipeline reads `test*.edr` from `$IFW_HOME/data/in`. The install ships a
sample file there:

```bash
cd $IFW_HOME/data/in
cp test_cdr.orig test_cdr.edr
```

It is processed within about a second, so by the time you look it has already left `data/in`.
Read the result from the logs and `data/done` instead:

```bash
cd $IFW_HOME
ls -la data/done                              # test_PREPROCESS_cdr.done, test_ALLRATE_cdr.done
cat log/stream/Stream_test_cdr.edr.log        # per-record reasons
grep -E "Total number of EDRs|EDRs with message" log/pipeline/pipeline_ALL_RATE.log
```

Flow: `data/in` → `PRE_PROCESS` → `data/edr/test_cdr.edr` → `ALL_RATE` → `data/out/...`
(or `data/reject`). The original goes to `data/done`.

Result on this build:

```
Total number of EDRs: 15, 0 (= 0%) are corrupted.
13 EDRs with message INF_EDR_DISCARDED_INFO (= 100.00%).
```

```
EDR discarded by 'Old Calls > 180 days'.          (for each of the 13 call records)
```

**This is a pass.** The 15 EDRs are a header, 13 calls and a trailer. The sample calls are dated
2000, and the sample discard rule drops anything older than 180 days. Every output file came
out empty, so the pipeline deleted it. That is why `data/out` and `data/reject` stay empty. The
file was read, parsed with 0 corrupt records, passed through both pipelines and committed.

Changing the dates to recent ones would get the calls past the discard rule. With no matching
BRM customers they would only end up in `data/reject`, so this is only worth doing after BRM
integration.

## Running it in the background, and stopping it

`ifw -r conf/wireless.reg` holds the terminal. To run it in the background, use the wrapper
scripts:

```bash
$IFW_HOME/bin/start_ifw     # starts ifw -r conf/wireless.reg in the background, waits for "IFW STARTED SUCCESSFULLY!"
$IFW_HOME/bin/stop_ifw      # writes "ifw.Active = False" to the semaphore file and waits for the process to exit
```

`start_ifw` writes console output to `$IFW_HOME/IFW.LOG` and the PID to `$IFW_HOME/IFW.PID`.
`stop_ifw` only knows about an `ifw` that `start_ifw` started (it reads `IFW.PID`). For one
started by hand in the foreground, use Ctrl-C.

### `start_all_pipeline.pl` / `stop_all_pipeline.pl` do **not** start or stop `ifw`

```
$ bin/start_all_pipeline.pl
Semaphore for start_all_pipeline is sent
```

These scripts only append lines like `ifw.Pipelines.ALL_RATE.Active = TRUE` to
`semaphore/semaphore.reg`. A **running** `ifw` checks that file, applies it and deletes it. That
way you can switch individual pipelines on and off inside a running `ifw`. If no `ifw` is
running, nothing happens and the file just sits there. Delete it before the next start, so a
stale command isn't applied:

```bash
rm $IFW_HOME/semaphore/semaphore.reg
```

The `*_all_pipeline` files also name `ALL_BCKOUT` and `ALL_RERATE`, which `wireless.reg` does
not define, so expect warnings for those two even when `ifw` is running.

## Status

- Schema built and sample data loaded 2026-10-29.
- Environment fixed, first start clean, sample CDR processed end to end 2026-10-30.
  **Pipeline Manager works on its own.**
- Not done yet: **BRM integration**, meaning account sync (BRM accounts and changes reaching the
  pipeline) and loading rated events back into BRM. `/app/pin/ifw/pin.conf` is still the unedited
  template (`cm_ptr ip XXX`) and is only needed for that step.
