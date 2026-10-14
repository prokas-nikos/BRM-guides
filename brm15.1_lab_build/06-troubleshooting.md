# BRM 15.1 / Oracle 19c Lab — Troubleshooting

Every failure hit while building this lab, symptom first.

## Installation and prerequisites

### `INS-08101 ... java.lang.NullPointerException` at state `supportedOSCheck`
The Oracle 19.3 installer's CVU cannot parse the OL 8.10 release string.

```bash
export CV_ASSUME_DISTID=OEL7.6
```

Needed for `runInstaller`, `dbca` and `netca`, so put it in the `oracle` user's profile.

### `INS-32047` central inventory not empty
Warning only. Ignore.

### Perl `Configure` fails: `skipping incompatible ... cannot find -lgdbm` / `-ldb`
The `-devel` packages are installed as **i686 only**, so the linker finds 32-bit `.so` files and no
64-bit ones. Usually a leftover from following BRM **12.0** instructions, which specify 32-bit Perl.

```bash
sudo dnf install gdbm-devel.x86_64 libdb-devel.x86_64 zlib-devel bzip2-devel
ls -l /usr/lib64/libgdbm.so /usr/lib64/libdb.so    # the linker symlinks you were missing
```

Leave the i686 packages installed — multilib handles both. Any future from-source build that fails
the same way wants the same fix: add the `.x86_64` `-devel`, never remove the i686 one.
`openssl-libs.i686` and `readline.i686` are on that list too.

### Downloaded file is tiny / `not an rpm package`
An Oracle download that hit the SSO wall is an HTML login page with the right filename.

```bash
file <download>     # "HTML document" means you got the login form
```

Always `file` and size-check Oracle downloads before using them. The same applies to a download
still in progress — a checksum mismatch on a growing file means nothing.

## Database

### `ORA-00990: missing or invalid privilege` on `grant unlimited tablespaces`
Documentation bug — the privilege is `UNLIMITED TABLESPACE`, **singular**.

### `ORA-65096: invalid common user or role name`
You are creating a local user while connected to `CDB$ROOT`.
`alter session set container = PDB1;` first.

### A query returns "no rows selected" for an object you know exists
Wrong container. `sqlplus / as sysdba` lands in `CDB$ROOT`, and `DBA_*` views describe only the
current container.

```sql
show con_name
alter session set container = PDB1;
```

Use `CDB_*` views with their `con_id` column to look across containers from the root.

### A patch looks missing in a PDB
`CDB_*` views **exclude `PDB$SEED`** (`_exclude_seed_cdb_view` defaults to TRUE) and skip any PDB
that is only `MOUNTED`. Open all PDBs, then:

```sql
alter session set "_exclude_seed_cdb_view"=FALSE;
```

### `PDB$SEED` reports "no release updates are installed in the PDB"
`dbca` runs `datapatch` against the root and your PDBs, but not the read-only seed. Check the
**`STATUS`** column of `pdb_plug_in_violations` before acting — `RESOLVED` means it is a stale
historical row, `PENDING` means the seed really needs patching:

```sql
select name, type, status, action, time from pdb_plug_in_violations order by time;
```

To patch the seed:

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

### The database hangs with no error
Classic full recovery area. Archiving stops at `db_recovery_file_dest_size` and the instance
freezes on the next log switch with `ORA-19809`. Guaranteed restore points make it likelier,
because they pin archive and flashback logs.

```sql
select file_type, round(percent_space_used,1) pct, round(percent_space_reclaimable,1) reclaimable
from v$flash_recovery_area_usage where percent_space_used > 0;
```

```
RMAN> backup as compressed backupset archivelog all delete input;
RMAN> delete noprompt obsolete;
```

`RMAN-08139: archived redo log not deleted, needed for guaranteed restore point` is that mechanism
working as designed, not an error.

### `RMAN-06171: not connected to target database`
`rman` alone starts the client unattached — use `rman target /`. And RMAN needs the `dba` group, so
run it as `oracle`; the `pin` user is in `oinstall`, not `dba`.

## BRM

### `pin_setup`: "The login credentials you have supplied are not valid"
…while `sqlplus pin@pdb1` works. BRM connects as `/@<alias>` using the external password store; no
password is sent. `sqlnet.ora` needs the wallet settings — see
[guide 05](05-postinstall-and-verification.md).

```bash
echo exit | sqlplus -s /@pdb1     # ORA-01017 confirms it
```

### `testnap` / `pin_virtual_time`: command not found
The BRM environment is not loaded. `.bashrc` setting `PIN_HOME` does not add `$PIN_HOME/bin` to
`PATH`; only `source.me.sh` does.

```bash
source $PIN_HOME/source.me.sh
```

### `orapki wallet display`: "ewallet.p12 not present at client"
`-wallet` takes a **path** and `client` is relative to your current directory.

```bash
orapki wallet display -wallet $BRM_WALLET
```

### `bad open for pin_virtual_time(): No such file or directory`
Benign — the virtual-time file is not initialised and components fall back to real time.

```bash
pin_virtual_time -m 0
```

### BRM_HOME came out one level too deep
`Installation Location` is the **Oracle home**; BRM goes in a `BRM/` subdirectory of it. For
`PIN_HOME=/app/pin/BRM`, answer `/app/pin`. See [guide 04](04-brm-server-install.md).

### `pin_setup`: "Change your username to pin and restart the script"
`pin_setup` requires the OS user to be literally named `pin`. Not configurable.

## Host (`brmdb`, Lenovo Z50-75)

### No IP address after `dnf update` + reboot
`/etc/sysconfig/kernel` has `UPDATEDEFAULT=yes`, so a newly installed kernel of the `DEFAULTKERNEL`
type takes over the GRUB default and discards any earlier `grubby --set-default`.

```bash
sudo vi /etc/sysconfig/kernel        # DEFAULTKERNEL=kernel  (RHCK, the one that works here)
sudo grubby --set-default /boot/vmlinuz-$(uname -r)
sudo grubby --default-kernel
```

Habit: run `sudo grubby --default-kernel` **before** rebooting after any update. Recovery: hold
Shift / tap Esc at boot and pick a working kernel.

NIC is a Realtek RTL8111/8168 rev 10 on driver `r8169`, which ships in **both** RHCK and UEK —
"missing driver" is not the explanation, and no firmware error appears in `dmesg` on the kernel
that works. Capture this from the console *before* rebooting away from a failing kernel:

```bash
{ uname -r; ip -br link; nmcli device status;
  dmesg | grep -i -E 'r8169|rtl|eth|enp'; } > /tmp/netfail.txt 2>&1
```

### PackageKit: "Failed to obtain authentication"
polkit has no agent in a plain SSH session. Use `sudo dnf install <pkg>` instead.

### `sqlplus`/`lsnrctl` not found as the oracle user
`su oracle` runs a non-login shell that skips `.bash_profile`. Use `sudo su - oracle`, with the dash.

## Two recurring lessons

**Shell quoting inside heredocs.** Two separate defects came from it: `dbstart \$ORACLE_HOME`
written literally into a startup script, and `db_create_file_dest='${DATA_DIR}'` silently set to
`''` because an unquoted heredoc expanded an undefined variable. When something "succeeded" but
nothing changed, check heredoc quoting first. Use `<<'EOF'` unless you *want* expansion.

**`PATH` edits accumulate.** Blocks appended to `.bashrc` over time, and scripts that prepend on
every source, produce duplicated entries and stale values that later shadow the right ones. If an
environment variable looks right but the command resolves wrong, print the whole file rather than
grepping one line.
