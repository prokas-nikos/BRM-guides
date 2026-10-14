# BRM 15.1 Post-Installation and Verification

The installer finishing is not the end. `pin_setup` configures the database and generates every
`pin.conf`; until it succeeds you have binaries and nothing else.

## The blocker: BRM connects with a wallet, not a password

Symptom — the installer completed, but `$PIN_HOME/setup/pin_setup.log` says:

```
User:         pin
Password:     ****
Alias:        pdb1
The login credentials you have supplied are not valid.
Please make sure you entered the correct 'user', 'password', and 'alias'
for MAIN_DB in pin_setup.values, and then run this install program again.
```

and yet `sqlplus pin@pdb1` works perfectly with that password.

**The message is misleading: no password was sent at all.** From
`$PIN_HOME/setup/scripts/pin_oracle_functions.pl`:

```perl
if ((defined($ENV{PRIMARY_SCHEMA_USERNAME_TEMP}) && $ENV{PRIMARY_SCHEMA_USERNAME_TEMP} eq "1")) {
    $sqlshell = "... -s ".$DB{"user"}."/".$DB{"password"}."@".$DB{alias}." $is_sysdba";
} else {
    $sqlshell = "... -s /@".$DB{alias}." $is_sysdba";          # <-- the default path
}
```

BRM connects as `/@pdb1` — an Oracle **secure external password store** lookup. `pin_setup.values`
has no password key at all; credentials live in the BRM wallet. If `sqlnet.ora` does not point at
that wallet, the connection fails and BRM reports it as bad credentials.

Confirm in one command:

```bash
echo exit | sqlplus -s /@pdb1
# ORA-01017 before the fix, silent success after
```

### The fix — the deferred "Setting BRM Wallet Location in sqlnet.ora" task

This is a **pre-installation** task in the guide. It is easy to read as optional ("if you use a
wallet"); BRM always uses one.

Give BRM its own `TNS_ADMIN` rather than editing the database's `sqlnet.ora` — that file is shared
with the running database server, and `WALLET_LOCATION` is also a legacy fallback location for the
TDE keystore:

```bash
mkdir -p /app/pin/BRM/network/admin
cp $ORACLE_HOME/network/admin/tnsnames.ora /app/pin/BRM/network/admin/

cat > /app/pin/BRM/network/admin/sqlnet.ora <<'EOF'
NAMES.DIRECTORY_PATH = (TNSNAMES, EZCONNECT)
SQLNET.EXPIRE_TIME = 10

SQLNET.WALLET_OVERRIDE = TRUE
WALLET_LOCATION=(
   SOURCE=(METHOD=FILE)
   (METHOD_DATA=(DIRECTORY=/app/pin/BRM/wallet/client))
)
EOF
```

Then in `~/.bashrc` — **this must persist**, or `dm_oracle` fails on the next login:

```bash
export TNS_ADMIN=/app/pin/BRM/network/admin
```

Verify from a fresh login:

```bash
echo $TNS_ADMIN
echo exit | sqlplus -s /@pdb1 && echo "WALLET AUTH OK"
```

If `/@pdb1` still fails after this, the wallet has no credential for the alias:

```bash
mkstore -wrl /app/pin/BRM/wallet/client -createCredential pdb1 pin
```

## Running pin_setup

```bash
cd /app/pin/BRM
source source.me.sh
cd setup
./pin_setup
```

`pin_setup` requires `$PIN_HOME/bin` on `PATH` and `$PIN_HOME/lib` on `LD_LIBRARY_PATH` (both
provided by `source.me.sh`) and the OS user to be literally `pin`. `DEBUG=1` is set in the script,
so output appears live as well as in `pin_setup.log`.

A successful run generates every `pin.conf`, creates the AES key for `dm_oracle`, builds the schema,
creates the AQ queues, loads pricing and config data, starts the formatter, DM and CM, and ends:

```
Testnap has successfully connected to the CM.
Portal Base is up and running.
...
!! Your installation has completed !!
```

### A warning that is not a problem

```
Warning:  File not found:  /app/pin/BRM/sys/dm_oracle/pin.conf
          To complete the cm install, update the following entries in
          /app/pin/BRM/sys/cm/pin.conf and then restart the CM process:
- cm dm_pointer 0.0.0.1 ip brmdb.localdomain 12950
```

The CM's `pin.conf` is generated before the DM's; `pin_setup` fills these in afterwards. Verify
rather than act:

```bash
grep -E 'dm_pointer|em_pointer' $PIN_HOME/sys/cm/pin.conf
```

## Shell environment

`.bashrc` setting `PIN_HOME` is **not** enough — only `source.me.sh` puts `$PIN_HOME/bin` on
`PATH`. Without it, `testnap` and `pin_virtual_time` are "command not found" on a perfectly healthy
install with a running CM.

```bash
if [ -z "$BRM_ENV_LOADED" ] && [ -f "$PIN_HOME/source.me.sh" ]; then
    . "$PIN_HOME/source.me.sh"
    export BRM_ENV_LOADED=1
fi
```

The guard matters: `source.me.sh` *prepends* to `PATH`, `LD_LIBRARY_PATH` and `PERL5LIB` every time
it runs, so re-sourcing `.bashrc` without one stacks duplicates. It does not touch `TNS_ADMIN`, so
the wallet setting survives.

`source.me.sh` sets, among others:

```
PIN_HOME=/app/pin/BRM
BRM_WALLET=/app/pin/BRM/wallet/client
BRM_CONF_WALLET=/app/pin/BRM/wallet/client
```

## Verification

```bash
cd $PIN_HOME/sys/test
./sanity_check_cm.sh
```

```
===> database 0.0.0.1 from pin.conf "userid"
Success: CM is up and responding
```

That one check exercises the whole stack: `testnap` → CM → `dm_pointer` → `dm_oracle` → PDB1.
`testnap` authenticates without prompting even though `login_type 1` is set and `login_pw` is
commented out, because the root user's credentials come from the wallet.

Check the wallet contents with the **path**, not a bare name — `-wallet client` is relative and
resolves against your current directory:

```bash
orapki wallet display -wallet $BRM_WALLET      # not "-wallet client"
```

`pin_virtual_time` complains until initialised; the warning is benign and components fall back to
real time:

```bash
pin_virtual_time -m 0     # mode 0 regular, 1 fixed, 2 running
pin_virtual_time
```

## Which post-installation tasks actually apply

From the guide's non-production list:

| Task | Applies to a Typical, no-Pipeline install? |
|---|---|
| Editing `pin_setup.values` / Running `pin_setup` | done during installation |
| Changing Your Database Partitions | optional |
| Setting Env Variables for Pipeline Manager | no — separate machines/directories only |
| Updating Client Wallet for Pipeline Manager | no — same condition |
| Copying Files for Compiling CM and FM Modules | **no** — needs `PortalDevKit`, which ships with the BRM SDK optional component |
| Editing and Loading the Event Notification List | **yes** |
| Loading the Tailor-Made Stored Procedure | no — requires Pipeline Manager and its `ifw_*` tables |

### Event notification list

The guide says to remove two entries, but BRM 15.1 already ships them commented out:

```
#2354	0	/event/billing/settlement/notify
#2355	0	/event/billing/dispute/notify
```

`pin_setup` creates the `/config/notify` class but never loads the list, so this is the one real
step — run it from the directory holding the matching `pin.conf`:

```bash
cd $PIN_HOME/sys/data/config
load_pin_notify -v pin_notify
```

Verify:

```sql
-- as pin, in PDB1
select count(*) from config_notify_events_t;
```

## Capture the working state

```sql
alter session set container = PDB1;
create restore point BRM_CONFIGURED guarantee flashback database;
```

Then an RMAN backup, because restore points live in the FRA on the same disk:

```bash
sudo su - oracle
rman target /           # RMAN needs the dba group; the pin user is not in it
```
```
RMAN> backup as compressed backupset database plus archivelog;
```
