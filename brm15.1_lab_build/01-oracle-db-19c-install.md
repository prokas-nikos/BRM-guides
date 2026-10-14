# Oracle Database 19c on Oracle Linux 8.10 — Install Runbook

**Host:** `brmdb.localdomain` (192.168.11.114) · **Installed:** 2026-07-30 · **Guide written:** 2026-09-23
**Purpose:** database tier for an Oracle BRM 15.1 learning environment.

## Provenance of this document

Everything marked **[sourced]** was recovered from the machine itself — `/home/oracle/.bash_history`,
`installActions*.log`, `cfgtoollogs/dbca/cdb1/`, `opatch lsinventory`, and live `v$` / `cdb_*` queries.
Everything marked **[inferred]** is reconstruction — correct in effect, but not a literal transcript.

Passwords below are **placeholders**. The real ones were passed on the `dbca` command line and are
therefore in cleartext in `/home/oracle/.bash_history`. Rotate them and consider clearing that history.

---

## 1. Final state

| Item | Value |
|---|---|
| Edition | Enterprise Edition 19.3.0.0.0, patched to **19.32.0.0.0** |
| `ORACLE_BASE` | `/u01/app/oracle` |
| `ORACLE_HOME` | `/u01/app/oracle/product/19.0.0/dbhome_1` |
| Central inventory | `/u01/app/oraInventory` (group `oinstall`) |
| CDB / SID | `cdb1` |
| PDB | `PDB1` |
| Datafiles | `/u02/oradata/CDB1` |
| Character set | `AL32UTF8` / `AL16UTF16` |
| SGA target | ~1.5 GB (`-totalMemory 2000` with `auto_sga`) |
| PGA target | 500 MB |
| Archive mode | **NOARCHIVELOG** |
| Listener | default `LISTENER` on 1521, no `listener.ora` |
| RU applied | 39472050 — Database Release Update 19.32.0.0.260721 |
| EM Express | not configured (`-emConfiguration NONE`) |
| OJVM RU | deliberately skipped (lab box) |

---

## 2. OS preparation

The `oracle-database-preinstall` package created the `oracle` user, the `oinstall`/`dba`/`oper`/
`backupdba`/`dgdba`/`kmdba`/`racdba` groups, and applied Oracle's sysctl and limits tuning. **[sourced]**

Resulting identity:

```
uid=54321(oracle) gid=54321(oinstall)
groups=oinstall,wheel,dba,oper,backupdba,dgdba,kmdba,racdba
```

Verification performed before installing: **[sourced]**

```bash
cat /etc/oracle-release
uname -r
sudo rpm -q binutils compat-libstdc++ gcc glibc libaio libgcc libstdc++ make sysstat unixodbc
grep Huge /proc/meminfo
ulimit -a
sudo sysctl -w vm.hugetlb_shm_group=54321
```

The running kernel was pinned to the UEK/RHCK kernel the install was validated against: **[sourced]**

```bash
sudo grubby --default-kernel
sudo grubby --set-default /boot/vmlinuz-4.18.0-553.146.1.el8_10.x86_64
sudo reboot
```

Firewall opened for the listener: **[sourced]**

```bash
sudo firewall-cmd --permanent --zone=public --add-port=1521/tcp
sudo firewall-cmd --reload
sudo firewall-cmd --permanent --zone=public --list-ports
```

SELinux was left **enforcing**. No policy changes were needed.

---

## 3. Directories and ownership

```bash
sudo mkdir -p /u01/app/oracle/product/19.0.0/dbhome_1
sudo mkdir -p /u02/oradata
sudo chown -R oracle:oinstall /u01 /u02
sudo chmod -R 775 /u01 /u02
sudo mkdir /home/oracle/scripts
sudo chown -R oracle:oinstall /home/oracle/scripts
```

**[sourced]** — `/u01` holds the software, `/u02` the datafiles.

---

## 4. Environment for the `oracle` user

`/home/oracle/scripts/setEnv.sh`: **[sourced — actual file contents]**

```bash
# Oracle Settings
export TMP=/tmp
export TMPDIR=$TMP

export ORACLE_HOSTNAME=ol8-19.localdomain     # NOTE: wrong, see §11
export ORACLE_UNQNAME=cdb1
export ORACLE_BASE=/u01/app/oracle
export ORACLE_HOME=$ORACLE_BASE/product/19.0.0/dbhome_1
export ORA_INVENTORY=/u01/app/oraInventory
export ORACLE_SID=cdb1
export PDB_NAME=pdb1
export DATA_DIR=/u02/oradata

export PATH=/usr/sbin:/usr/local/bin:$PATH
export PATH=$PATH:$ORACLE_HOME/bin

export LD_LIBRARY_PATH=$ORACLE_HOME/lib:/lib:/usr/lib
export CLASSPATH=$ORACLE_HOME/jlib:$ORACLE_HOME/rdbms/jlib
```

Sourced from `/home/oracle/.bash_profile`:

```bash
. /home/oracle/scripts/setEnv.sh
```

And in `/home/oracle/.bashrc` — **the single most important line on OL 8.10**:

```bash
export CV_ASSUME_DISTID=OEL7.6
```

> **Always use `sudo su - oracle` with the dash.** Without it the login profile is skipped and
> `sqlplus` / `lsnrctl` are "command not found".

---

## 5. Software media

`LINUX.X64_193000_db_home.zip` (~3.0 GB) — 19c is an *image-based* install, so the zip is extracted
**directly into `ORACLE_HOME`** and `runInstaller` is run from there. **[sourced]**

```bash
cd $ORACLE_HOME
sudo cp /home/pin/oracle_db/LINUX.X64_193000_db_home.zip .
sudo chown oracle:oinstall LINUX.X64_193000_db_home.zip
unzip LINUX.X64_193000_db_home.zip
rm LINUX.X64_193000_db_home.zip
```

---

## 6. Software-only install

```bash
export CV_ASSUME_DISTID=OEL7.6        # MUST be set first — see §12
cd $ORACLE_HOME

./runInstaller -ignorePrereq -waitforcompletion -silent \
  -responseFile ${ORACLE_HOME}/install/response/db_install.rsp \
  oracle.install.option=INSTALL_DB_SWONLY \
  ORACLE_HOSTNAME=${ORACLE_HOSTNAME} \
  UNIX_GROUP_NAME=oinstall \
  INVENTORY_LOCATION=${ORA_INVENTORY} \
  SELECTED_LANGUAGES=en,en_GB \
  ORACLE_HOME=${ORACLE_HOME} \
  ORACLE_BASE=${ORACLE_BASE} \
  oracle.install.db.InstallEdition=EE \
  oracle.install.db.OSDBA_GROUP=dba \
  oracle.install.db.OSBACKUPDBA_GROUP=dba \
  oracle.install.db.OSDGDBA_GROUP=dba \
  oracle.install.db.OSKMDBA_GROUP=dba \
  oracle.install.db.OSRACDBA_GROUP=dba \
  SECURITY_UPDATES_VIA_MYORACLESUPPORT=false \
  DECLINE_SECURITY_UPDATES=true
```

**[sourced — verbatim, confirmed against `sun.java.command` in `installActions2026-07-30_04-12-25AM.log`]**

Expected warning, safe to ignore:

```
[WARNING] [INS-32047] The location (/u01/app/oraInventory) specified for the
central inventory is not empty.
```

### Root scripts

```bash
cd /u01/app/oraInventory && sudo ./orainstRoot.sh
cd $ORACLE_HOME          && sudo ./root.sh
```

**[sourced]** — `root.sh` copies `dbhome`, `oraenv`, `coraenv` to `/usr/local/bin` and installs TFA.
Log: `$ORACLE_HOME/install/root_brmdb.localdomain_2026-07-30_04-15-54-784019675.log`

---

## 7. OPatch refresh + Release Update

OPatch must be updated **before** applying the RU — the shipped version is too old. **[sourced]**

```bash
export SOFTWARE_DIR=/u01/software
export PATH=${ORACLE_HOME}/OPatch:${PATH}
export OPATCH_FILE="p6880880_190000_Linux-x86-64.zip"
export PATCH_FILE="p39472050_190000_Linux-x86-64.zip"
export PATCH_TOP=${SOFTWARE_DIR}/39472050

mkdir /u01/software
mv p6880880_190000_Linux-x86-64.zip ${SOFTWARE_DIR}/
mv p39472050_190000_Linux-x86-64.zip ${SOFTWARE_DIR}/

# 1) refresh OPatch — unzips OVER $ORACLE_HOME/OPatch
cd ${ORACLE_HOME}
unzip -oq ${SOFTWARE_DIR}/${OPATCH_FILE}

# 2) unpack and apply the RU
cd ${SOFTWARE_DIR}
unzip -oq ${PATCH_FILE}
cd ${PATCH_TOP}
opatch prereq CheckConflictAgainstOHWithDetail -ph ./
opatch apply -silent
```

Result: OPatch `12.2.0.1.52`, patch `39472050` applied Thu Jul 30 06:21:05 EDT 2026. **[sourced —
`opatch lsinventory`]**

> The RU is applied to the *software home* here. The *SQL* half of the RU is applied per-container by
> `datapatch`, which `dbca` runs automatically for the CDB and PDB1 — **but not for `PDB$SEED`.** See §9.

---

## 8. Listener and database creation

```bash
lsnrctl start
```

`netca` was never run, so there is **no `listener.ora`, `tnsnames.ora`, or `sqlnet.ora`.** The listener
runs on defaults: `LISTENER`, port 1521, dynamic registration only. This works, but see §11.

```bash
dbca -silent -createDatabase \
  -templateName General_Purpose.dbc \
  -gdbname ${ORACLE_SID} -sid ${ORACLE_SID} -responseFile NO_VALUE \
  -characterSet AL32UTF8 \
  -sysPassword    <SYS_PASSWORD> \
  -systemPassword <SYSTEM_PASSWORD> \
  -createAsContainerDatabase true \
  -numberOfPDBs 1 \
  -pdbName ${PDB_NAME} \
  -pdbAdminPassword <PDB_ADMIN_PASSWORD> \
  -databaseType MULTIPURPOSE \
  -memoryMgmtType auto_sga \
  -totalMemory 2000 \
  -storageType FS \
  -datafileDestination "${DATA_DIR}" \
  -redoLogFileSize 50 \
  -emConfiguration NONE \
  -ignorePreReqs
```

**[sourced — verbatim, passwords redacted]** Runtime was roughly 06:34 → 07:47 (~70 min).

> Passing passwords on the command line puts them in shell history and the process table. For a
> repeat, use `-responseFile` with a `chmod 600` file instead.

---

## 9. Post-install: patch `PDB$SEED` (the step that gets missed)

`dbca` runs `datapatch` against CDB$ROOT and PDB1, but `PDB$SEED` is open **read-only** and gets
skipped. The seed is the template for every future PDB, so it must be patched too.

```bash
sqlplus -s / as sysdba <<'EOF'
alter session set "_oracle_script"=true;
alter pluggable database PDB$SEED close immediate;
alter pluggable database PDB$SEED open read write;
EOF

$ORACLE_HOME/OPatch/datapatch -verbose

sqlplus -s / as sysdba <<'EOF'
alter session set "_oracle_script"=true;
alter pluggable database PDB$SEED close immediate;
alter pluggable database PDB$SEED open read only;
EOF
```

**[sourced — performed 2026-08-16/17]**

Make PDB1 open automatically on startup:

```sql
alter pluggable database PDB1 open;
alter pluggable database PDB1 save state;
```

---

## 10. Verification

```sql
-- CDB_* views EXCLUDE PDB$SEED and skip any PDB that is only MOUNTED.
-- Without this line the seed is invisible and you will misread the result.
alter session set "_exclude_seed_cdb_view"=FALSE;

select con_id, patch_id, action, status from cdb_registry_sqlpatch order by con_id;
select con_id, comp_id, version, status from cdb_registry order by con_id, comp_id;
select con_id, count(*) from cdb_objects where status='INVALID' group by con_id;
select name, type, status, message from pdb_plug_in_violations;
show pdbs
```

Confirmed 2026-09-21/23:

- `39472050 APPLY SUCCESS` in con_id **1, 2 and 3**
- All 15 registry components **VALID** in all three containers (`RAC` shows `OPTION OFF` — correct for single instance)
- Zero invalid objects
- Tablespaces: `SYSTEM` 2270 MB, `SYSAUX` 1980 MB, `UNDOTBS1` 1380 MB, `USERS` 10 MB
- Redo: 3 groups × 50 MB, 1 member each

**`PDB$SEED` violation resolved (checked 2026-09-25).** `pdb_plug_in_violations` carries an `ERROR`
row for `PDB$SEED` reading "no release updates are installed in the PDB", but its `STATUS` is
`RESOLVED` and its timestamp is 30-JUL-26 07:47 — the original `dbca` run, before the seed was
patched in August. It is stale history, not an open problem. Always check `STATUS` on that view; the
row text alone is misleading.

---

## 11. Known deviations to fix

1. ~~**`start_all.sh` / `stop_all.sh` are broken.**~~ **FIXED 2026-09-23.** Both ended with a literal
   `dbstart \$ORACLE_HOME` — the backslash was written into the file by an unquoted heredoc, so the
   variable never expanded. Backslash removed in both.
2. ~~**`/etc/oratab` has two malformed lines.**~~ **FIXED 2026-09-23.** `~/scripts/start_all.sh` and
   `~/scripts/stop_all.sh` were neither comments nor valid `SID:HOME:FLAG` entries and would have
   broken `dbstart`/`dbshut`/`oraenv`. Now commented out.
3. ~~**`ORACLE_HOSTNAME=ol8-19.localdomain`**~~ **FIXED 2026-09-23.** Tutorial leftover that did not
   resolve. Now `export ORACLE_HOSTNAME=$(hostname -f)`, which self-corrects if the host is ever
   renamed. Note this is evaluated each time the file is sourced, so it depends on `/etc/hosts` and
   `hostname` staying correct.
4. ~~**`db_create_file_dest` is empty.**~~ **FIXED 2026-09-23.** OMF is now on:
   `alter system set db_create_file_dest='/u02/oradata' scope=both;` at CDB$ROOT, inherited by PDB1.
   Verified by creating a tablespace with no path (`create tablespace omf_test datafile size 10M;`),
   which only succeeds when OMF is configured, then dropping it.
   The original failure was `alter system set db_create_file_dest='${DATA_DIR}'` inside an **unquoted**
   heredoc run as `pin`: the shell expanded the empty variable, so Oracle silently received `''`.
5. ~~**No autostart.**~~ **FIXED 2026-09-23, verified across a reboot 2026-09-24.**
   `/etc/systemd/system/dbora.service` created and enabled — see §13. Confirmed by `systemctl status`
   showing `active (exited)` with a boot-time PID, the listener and `pmon` in the cgroup, and PDB1
   `READ WRITE` 22 hours later with no manual start. Depended on fixes 1 and 2.
6. ~~**No `tnsnames.ora`.**~~ **FIXED 2026-09-23.** `listener.ora`, `tnsnames.ora` and `sqlnet.ora`
   hand-written into `$ORACLE_HOME/network/admin` (netca never used) — see §15.
7. ~~**NOARCHIVELOG.**~~ **FIXED 2026-09-24.** ARCHIVELOG enabled, FRA on `/home/oracle/fra` (60 GB),
   guaranteed restore points and PDB-level flashback tested end-to-end. See §17.

---

## 12. Gotchas worth remembering

| Symptom | Cause | Fix |
|---|---|---|
| `INS-08101 ... NullPointerException` at state `supportedOSCheck` | CVU can't parse the OL 8.10 release string | `export CV_ASSUME_DISTID=OEL7.6` before `runInstaller`, `dbca`, `netca` |
| `INS-32047` inventory not empty | Central inventory already had entries | Warning only — ignore |
| `sqlplus: command not found` as oracle | Used `su oracle` instead of `su - oracle` | Use the dash; non-login shells skip `.bash_profile` |
| Patch looks missing in a PDB | `CDB_*` views hide `PDB$SEED` and closed PDBs | Open all PDBs, then `alter session set "_exclude_seed_cdb_view"=FALSE` |
| `PDB altered with errors` during `dbca` | Seed not patched by the RU | §9 |

The failed first `runInstaller` attempt (04:11) and the successful retry (04:12) are both in the
inventory logs — the only difference was `CV_ASSUME_DISTID`.

---

## 13. Daily operation

Since 2026-09-23 the database and listener start automatically at boot via `dbora.service`.

```bash
sudo systemctl status dbora.service
sudo systemctl start  dbora.service
sudo systemctl stop   dbora.service      # clean shutdown immediate, not a kill
```

`/etc/systemd/system/dbora.service`:

```ini
[Unit]
Description=Oracle Database 19c (cdb1) and Listener
After=network-online.target remote-fs.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
User=oracle
Group=oinstall
Environment=ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1
Environment=ORACLE_SID=cdb1
ExecStart=/home/oracle/scripts/start_all.sh
ExecStop=/home/oracle/scripts/stop_all.sh
TimeoutStartSec=600
TimeoutStopSec=600

[Install]
WantedBy=multi-user.target
```

`RemainAfterExit=yes` is essential: `dbstart` exits once the database is up, and without it systemd
would treat the service as dead and never run `ExecStop` at shutdown — meaning crash recovery on
every boot.

Manual equivalent, if the unit is ever disabled:

```bash
sudo su - oracle          # dash matters
/home/oracle/scripts/start_all.sh     # starts listener AND instance via oratab 'Y'
/home/oracle/scripts/stop_all.sh
```

> Do **not** run `start_all.sh` when the database is already up. `dbstart` detects the running
> instance, warns "possibly left running when system went down (system crash?)", shuts it down and
> restarts it. Harmless but disruptive. Check `ps -ef | grep pmon` first if unsure.

`dbstart`/`dbshut` logs: `$ORACLE_HOME/rdbms/log/startup.log` and `shutdown.log`
(**not** `$ORACLE_HOME/startup.log`, which is where the docs imply they live).

Connecting from SQL Developer — **Basic** connection type, **Service name** (not SID):

| | CDB root | PDB1 |
|---|---|---|
| Host | 192.168.11.114 | 192.168.11.114 |
| Port | 1521 | 1521 |
| Service | `cdb1` | `pdb1` |

Local OS authentication (`sqlplus / as sysdba`) always works regardless of password state, and is how
a lost SYS password is reset:

```sql
alter user sys identified by "<new_password>";
```

SYS and SYSTEM are common users — changing them at the root applies to all containers, and the
password file is updated automatically because `remote_login_passwordfile=EXCLUSIVE`.

---

## 14. Next: what BRM needs from this database

BRM does **not** create a database — it creates objects inside this one. Before running the BRM
installer:

1. Create a tablespace in `PDB1`. OMF is on since 2026-09-23, so no path is needed:
   `create tablespace pin00 datafile size 2G autoextend on next 200M maxsize 10G;`
2. Create the BRM schema user (conventionally `pin`) and grant it.
3. Point the installer at `//brmdb.localdomain:1521/pdb1`.

Confirm BRM 15.1 certification against 19c on My Oracle Support before starting.

---

## 15. Oracle Net configuration (added 2026-09-23)

`netca` was never run. These three files were hand-written into
`$ORACLE_HOME/network/admin/`. Nothing else on the box sets `TNS_ADMIN`, so clients using this
`ORACLE_HOME` find them by default.

**`tnsnames.ora`** — aliases `CDB1`, `PDB1`, and `BRMDB` (a stable alias pointing at `pdb1`, so BRM
configuration need not change if the PDB is renamed):

```
PDB1 =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = brmdb.localdomain)(PORT = 1521))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = pdb1)
    )
  )
```

**`sqlnet.ora`**:

```
NAMES.DIRECTORY_PATH = (TNSNAMES, EZCONNECT)
SQLNET.EXPIRE_TIME = 10
ADR_BASE = /u01/app/oracle
```

**`listener.ora`** — explicit TCP + IPC endpoints, plus one static entry. `GLOBAL_DBNAME` is
deliberately `cdb1_static`, not `cdb1`: reusing the dynamically registered name produces a confusing
duplicate service in `lsnrctl status`. The static entry allows a remote `STARTUP` while the instance
is down; it permanently reports `status UNKNOWN`, which is normal.

Verified: `tnsping PDB1` and `tnsping BRMDB` both return `OK (0 msec)` via the TNSNAMES adapter.

### Reading `lsnrctl status` in a CDB

A CDB has **one instance** serving **many services**. Every line reads `Instance "cdb1"` because
that is the only instance — PDBs are services on it, not instances. `Service "pdb1" → Instance
"cdb1"` is correct, and is why clients must connect by **SERVICE_NAME, never SID**.

| Service | Meaning |
|---|---|
| `cdb1` | CDB root, dynamically registered |
| `pdb1` | PDB1 — the BRM target |
| `cdb1_static` | Static entry, `UNKNOWN` by design |
| `cdb1XDB` | XML DB dispatcher, created by dbca |
| `57d3a19…`, `86b637b…` | GUID aliases Oracle creates per container |

After a listener restart, dynamic services take up to 60s to reappear. Force it with
`alter system register;`.

### If BRM reports ORA-12154

BRM components running under a different Oracle client or home will not find this `tnsnames.ora`.
Set in that component's environment:

```bash
export TNS_ADMIN=$ORACLE_HOME/network/admin
```

---

## 16. Host gotcha: kernel updates break networking

**Symptom:** after `dnf update` + reboot, the machine has no IP address.

**Cause:** `/etc/sysconfig/kernel` has `UPDATEDEFAULT=yes`, so a newly installed kernel of the
`DEFAULTKERNEL` type takes over the GRUB default and discards any earlier `grubby --set-default`.

**Hardware:** Realtek RTL8111/8168/8211/8411 rev 10 (Lenovo Z50-75), driver `r8169`, iface `enp1s0`.
`r8169` ships in *both* RHCK and UEK — "missing driver" is NOT the explanation, and missing firmware
is ruled out (no `Direct firmware load` error in dmesg on the working kernel).

**Resolved 2026-09-24 — stay on RHCK:**

```
# /etc/sysconfig/kernel
UPDATEDEFAULT=yes
DEFAULTKERNEL=kernel          # RHCK, not kernel-uek
```

with the default pinned to `4.18.0-553.164.1.el8_10`, confirmed healthy:

```
r8169 0000:01:00.0 enp1s0: Link is Up - 1Gbps/Full - flow control rx/tx
```

UEK installs can no longer seize the default. Which kernel actually fails was never identified —
prime suspect is UEK 5.15.0-324.217.5.3, installed the same day as the working RHCK.

**Habit:** after any `dnf update`, run `sudo grubby --default-kernel` *before* rebooting. A new RHCK
will auto-become default and is untested; known-good fallback is 4.18.0-553.164.1.

**Recovery:** hold Shift / tap Esc at boot, pick the working kernel from the GRUB menu.

**Diagnose it properly next time it fails** — from the console, before rebooting away:

```bash
{ uname -r; ip -br link; nmcli device status;
  dmesg | grep -i -E 'r8169|rtl|eth|enp'; } > /tmp/netfail.txt 2>&1
```

`Direct firmware load for rtl_nic/... failed` → `dnf install linux-firmware`.
`Link is Down` with no firmware error → driver regression; stay on UEK.

**Database impact:** none directly. `dbora.service` still starts, because the listener binds to
`brmdb.localdomain`, which resolves from the static `/etc/hosts` entry rather than DNS. A bad-kernel
boot costs remote access, not the database.

---

## 17. ARCHIVELOG, flashback and backups (added 2026-09-24)

A lab that is deliberately broken and rebuilt needs recovery more than a stable system does. Enabled
2026-09-24.

### Disk layout constraint

`/u01` and `/u02` are directories on the **root** filesystem (70 GB, ~38 GB free), shared with the OS
and later the BRM install. `/home` is a separate LV with 133 GB free. The recovery area therefore
lives on `/home`, so a runaway archive log cannot fill the root filesystem.

### Enabling

```sql
-- as oracle, in CDB$ROOT
alter system set db_recovery_file_dest_size = 60G scope=both;     -- size BEFORE destination
alter system set db_recovery_file_dest = '/home/oracle/fra' scope=both;

shutdown immediate
startup mount
alter database archivelog;
alter database open;

archive log list
```

Confirmed: `Database log mode: Archive Mode`, `Automatic archival: Enabled`,
`Archive destination: USE_DB_RECOVERY_FILE_DEST`. Archive logs appear under
`/home/oracle/fra/CDB1/archivelog/<date>/` at ~41 MB each (redo is 3 × 50 MB).

### Guaranteed restore points — the everyday rewind

Requires ARCHIVELOG plus local undo (`LOCAL_UNDO_ENABLED = TRUE`, the `dbca` default). 19c can flash
back a **single PDB**, leaving the CDB untouched.

Before any risky step:

```sql
alter session set container = PDB1;
create restore point BEFORE_BRM guarantee flashback database;
```

To rewind:

```sql
alter session set container = CDB$ROOT;
alter pluggable database PDB1 close immediate;
flashback pluggable database PDB1 to restore point BEFORE_BRM;
alter pluggable database PDB1 open resetlogs;
```

**Tested end-to-end on 2026-09-24 — the full cycle works.**

Notes:

- Restore points created inside a PDB are only visible from that PDB. Querying `v$restore_point` or
  dropping them from `CDB$ROOT` gives `ORA-38780: Restore point does not exist`.
- After `open resetlogs`, check `dba_pdb_saved_states` still lists PDB1, or the PDB will not
  auto-open at boot. Re-run `alter pluggable database PDB1 save state;` if missing.
- Take a point per milestone (`BEFORE_BRM`, `AFTER_BRM_SCHEMA`, `BEFORE_PDC`) to rewind to any stage.
- Restore points are **not backups** — they live in the FRA on the internal disk and die with it.

### The failure mode to watch

**A full recovery area hangs the instance.** When usage hits `db_recovery_file_dest_size`, archiving
stops and the database freezes on the next log switch with `ORA-19809: limit exceeded for recovery
files`. It presents as a hang, not an error. Guaranteed restore points make this more likely, since
flashback logs accumulate and are not auto-deleted.

```sql
select file_type,
       round(percent_space_used,1)        pct_used,
       round(percent_space_reclaimable,1) pct_reclaimable,
       number_of_files
from   v$flash_recovery_area_usage
where  percent_space_used > 0;
```

Reclaim with:

```
RMAN> backup as compressed backupset archivelog all delete input;
RMAN> crosscheck archivelog all;
RMAN> delete noprompt obsolete;
```

and drop restore points once genuinely finished with them.

### External drive for RMAN backups

Planned, not yet done. Design: **FRA stays internal, backups go external.** The FRA is on the
critical write path — if a USB drive stalls, archiving stops and the instance hangs. Backups are
write-once and belong on separate physical media.

```bash
lsblk -f                                   # identify device first
sudo mkfs.ext4 -L ORABACKUP /dev/sdX1      # ext4/xfs only — NOT NTFS/exFAT (no UNIX ownership)
sudo blkid /dev/sdX1                       # get UUID
```

`/etc/fstab` — **`nofail` is mandatory on this laptop**, or booting without the drive drops to
emergency mode:

```
UUID=<uuid>  /u03/backup  ext4  defaults,nofail,x-systemd.device-timeout=10  0  2
```

```bash
sudo mount -a
sudo chown -R oracle:oinstall /u03/backup
```

RMAN (run from the **shell**, not `SQL>`):

```
RMAN> CONFIGURE RETENTION POLICY TO RECOVERY WINDOW OF 7 DAYS;
RMAN> CONFIGURE CONTROLFILE AUTOBACKUP ON;
RMAN> CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE DISK TO '/u03/backup/cf_%F';
RMAN> CONFIGURE CHANNEL DEVICE TYPE DISK FORMAT '/u03/backup/%U';
RMAN> CONFIGURE DEVICE TYPE DISK BACKUP TYPE TO COMPRESSED BACKUPSET;
RMAN> BACKUP DATABASE PLUS ARCHIVELOG;
```

Database is ~12 GB; expect 3–4 GB per compressed full backup.
