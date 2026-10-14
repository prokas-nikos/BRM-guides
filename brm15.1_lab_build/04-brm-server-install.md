# Installing the BRM 15.1 Server

Covers the media, the OUI installer, the one answer that is easy to get wrong, and how to undo it.

## Media

BRM 15.1 comes from Oracle eDelivery (account + licence acceptance; no `wget` of a public URL).
Part numbers are opaque, so list each archive before extracting:

```bash
for f in V*.zip; do echo "== $f"; unzip -l "$f" | head -8; done
```

From one BRM 15.1 download set:

| Part | Component |
|---|---|
| V1049529 | **BRM Server** — `brmserver_15.1.0.0.0_linux_generic_full.jar` |
| V1049530 | BRM Clients |
| V1049526 | PDC |
| V1049533 | Pipeline Configuration Center |
| V1049528 | Billing Care |
| V1049531 | Business Operations Center |
| V1049532 | BRM REST Services Manager |
| V1049527 | ECE |
| V1049508 | OCOMC (Offline Mediation Controller) |

Always verify before extracting — an interrupted or unauthenticated download is a *small HTML file*
with the right name:

```bash
ls -lh V1049529-01.zip
file V1049529-01.zip        # must NOT say "HTML document"
unzip -t V1049529-01.zip
```

**Pipeline Manager needs no separate download.** It is a selectable component inside the BRM server
installer, along with its optional managers (CIBER Roaming, Interconnect, Pipeline Configuration,
Pipeline PDK, TAP Roaming).

## Use the `_full` jar

The archive contains two jars. The installation guide states: *"The Zip archive includes the
installer: `brmserver_15.1.x.y.0_linux_generic_full.jar`"*, and every documented example uses it.

## Before launching

**The installing user must be able to write to oraInventory.** On a box that already has a database,
that inventory belongs to `oracle:oinstall`:

```bash
sudo usermod -aG oinstall pin      # then log out and back in
id -nG pin                         # must now include oinstall
```

The documented alternative is a separate inventory via `-invPtrLoc <path>/oraInst.loc`, but that
flag is then required on every future install and patch, and forgetting it produces confusing
errors much later.

**The OS user must be named `pin`.** `pin_setup` enforces this literally:

```sh
PINUSER=pin
USER=`/usr/bin/whoami`
if [ "$USER" != "$PINUSER" ]; then
   echo "Change your username to $PINUSER and restart the script."
   exit 1
fi
```

A `brm` or `oracle` account gets through the installer and fails at configuration.

## Installation Location — the trap

**`Installation Location` is the Oracle home, not `PIN_HOME`.** The installer builds the OUI
scaffolding *at* the path you give (`OPatch`, `oui`, `inventory`, `oraInst.loc`, `oracle_common`)
and puts BRM in a `BRM/` subdirectory beneath it.

| You enter | You get |
|---|---|
| `/app/pin/BRM` | Oracle home `/app/pin/BRM`, **`BRM_HOME=/app/pin/BRM/BRM`** ✗ |
| `/app/pin` | Oracle home `/app/pin`, **`BRM_HOME=/app/pin/BRM`** ✓ |

For `PIN_HOME=/app/pin/BRM`, answer **`/app/pin`**. Getting this wrong costs a full uninstall and
reinstall.

## Launch

```bash
cd /path/to/media
$JAVA_HOME/bin/java -jar brmserver_15.1.0.0.0_linux_generic_full.jar \
  -record -destinationFile /home/pin/brm_installation/brm_typical.rsp
```

`-record` captures a response file as you click through, so later installs can be replayed:

```bash
$JAVA_HOME/bin/java -jar brmserver_15.1.0.0.0_linux_generic_full.jar \
  -silent -responseFile /home/pin/brm_installation/brm_typical.rsp
```

That pairs well with flashback restore points: rewind the PDB, replay the install, back to a known
state in minutes. GUI mode needs X11 — SSH forwarding is enough.

## Answer sheet (Typical install)

| Window | Answer |
|---|---|
| Welcome | Next |
| Specify Inventory Directory | usually skipped if `/etc/oraInst.loc` exists; else `/u01/app/oraInventory`, group `oinstall` |
| **Installation Location** | **`/app/pin`** — absolute, no environment variables |
| Installation Type | **Typical** (CM, Oracle DM, Batch Controller, billing/invoicing utilities) |
| Specify Prerequisite Libraries Location | the **directory** holding `ojdbc8.jar`, e.g. `/app/pin/Thirdparty` · Enable SSL unchecked |
| Specify Wallet Details | client / root / server wallet passwords — record them outside the terminal |
| Specify BRM Log Location | your choice |
| Database SSL Options | No |
| Create BRM Database Schema User | **No** if you already created `PIN` (guide 03) |
| BRM Database Connection Details | Host `brmdb.localdomain` · Port `1521` · Database Name **`pdb1`** (the service/alias) · User `pin` |
| BRM Root User Details | password for the BRM root user (`root.0.0.0.1`) |
| BRM User Details | password for all other default BRM users |
| CM Details | host + port (default) |
| EAI Framework Details | default port |
| Oracle DM Details | Database Number `0.0.0.1` (15.1 allows only the default for the primary schema) · **Is Primary DB? Yes** |
| Select BRM Data Storage Model | Test <700 MB · Small <1.5 GB · Medium <30 GB · Large >30 GB |
| BRM Table and Index Tablespace | `PIN_TABLE` / `PIN_INDEX` |
| Select Drop BRM Database Tables | **No** on a first install |
| Select BRM Database Partitions | optional; No keeps the first pass simple |

"Drop BRM Database Tables" becomes tempting after a failed attempt — prefer a flashback rewind,
which is faster and leaves no half-dropped state.

## Typical vs Complete

Typical installs the common server components. **Adding components later is supported** via
"Installing Individual BRM Components" — relaunch the same jar and choose from the Available
Product Components window. One caveat, quoted:

> "If you already installed a component, you must uninstall its features before reinstalling them."

So new components can be added freely; already-installed ones cannot simply be re-run over. That
asymmetry is a good reason to start with Typical and add deliberately.

## Uninstalling

**Never `rm -rf` a BRM home.** The installer registers it in the central inventory:

```xml
<HOME NAME="oraclehome1" LOC="/app/pin" TYPE="O" IDX="2"/>
```

Deleting the directory leaves a stale entry that confuses later installs. Use the deinstaller:

```bash
cd /app/pin/oui/bin        # <Oracle home>/oui/bin
./deinstall.sh             # GUI
```

Then clean up manually — quoted from the guide: *"Uninstalling BRM does not uninstall the
configuration files generated during the BRM installation. You must remove these files manually."*

```bash
rm -rf /app/pin/BRM
grep -i 'app/pin' /u01/app/oraInventory/ContentsXML/inventory.xml   # expect no match
```

And rewind the database, since the installer created schema objects:

```sql
alter session set container = CDB$ROOT;
alter pluggable database PDB1 close immediate;
flashback pluggable database PDB1 to restore point BEFORE_BRM_INSTALL;
alter pluggable database PDB1 open resetlogs;
```

## What a good install looks like

```
/app/pin/              OPatch  install  inventory  oracle_common  oraInst.loc  oui  plugins  setup  BRM/
/app/pin/BRM/          apps bin diagnostics jars lib lib64 plugins setup source
                       source.me.csh source.me.sh sys tmp tools var wallet xsd
/app/pin/BRM/wallet/   client/ root/ server/   each with ewallet.p12 + cwallet.sso
```

The installer finishing is **not** the end — `pin_setup` still has to configure the database.
See [guide 05](05-postinstall-and-verification.md).
