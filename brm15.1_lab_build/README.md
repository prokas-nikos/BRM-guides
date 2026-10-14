# BRM 15.1 Lab Build on Oracle Linux 8.10 (`brmdb`)

End-to-end build of a single-box Oracle Communications Billing and Revenue Management 15.1
learning lab: Oracle Database 19c, the third-party prerequisites, the BRM server install, and
the post-installation work needed to get a Connection Manager answering.

Written from an actual build, so it records what went wrong as well as what worked.

## The machine

| | |
|---|---|
| Host | `brmdb.localdomain` / 192.168.11.114 (Lenovo Z50-75 laptop, AMD A10-7300, 14 GB RAM) |
| OS | Oracle Linux 8.10, SELinux enforcing, firewalld active |
| Database | Oracle 19c EE, patched to 19.32, CDB `cdb1` with PDB `PDB1` |
| BRM | 15.1, Typical install, `PIN_HOME=/app/pin/BRM` |
| OS account | everything BRM runs as the `pin` user (this is **mandatory**, see guide 04) |

Disk layout matters here: `/u01` and `/u02` are directories on the **root** filesystem
(~35 GB free), while `/home` has ~130 GB. `/app` is a bind mount of `/home/pin/app` so that
`PIN_HOME` lives on the roomy filesystem while keeping a clean path.

```
/home/pin/app  /app  none  bind  0 0        # /etc/fstab
```

## Guides

| # | Guide | Covers |
|---|---|---|
| 01 | [Oracle Database 19c install](01-oracle-db-19c-install.md) | Silent 19.3 install, 19.32 RU, `dbca`, Oracle Net, ARCHIVELOG + flashback, autostart |
| 02 | [BRM prerequisites](02-prerequisites.md) | The compatibility matrix, Java 21, Perl 5.38.2 from source, gcc 12, Kafka, `ojdbc8.jar` |
| 03 | [Database preparation for BRM](03-database-prep.md) | Tablespaces, the `PIN` schema user, OMF, multitenant container pitfalls |
| 04 | [BRM server install](04-brm-server-install.md) | Media, the installer, the Installation Location trap, answer sheet, uninstall |
| 05 | [Post-installation and verification](05-postinstall-and-verification.md) | `pin_setup`, the wallet/`sqlnet.ora` blocker, shell environment, sanity check |
| 06 | [Troubleshooting](06-troubleshooting.md) | Every failure hit during this build, symptom first |

## Read this first

Two documents govern a BRM install and **neither is sufficient alone**:

- **BRM Compatibility Matrix** — gives versions, no procedure.
- **BRM Installation Guide** — gives procedure, defers all versions to the matrix.

Use both, and make sure both are for **your** release. Following the BRM 12.0 matrix during this
build cost real time: it specifies Perl 5.36 **32-bit** and Java 8, while 15.1 wants Perl 5.38.2
**64-bit** and Java 21. The 32-bit development packages installed from those instructions later
broke a from-source Perl build (guide 06).

## Conventions

- `BRM_home` / `$PIN_HOME` = `/app/pin/BRM`
- All passwords in these guides are placeholders such as `<PIN_PASSWORD>`.
- Commands run as `pin` unless the prompt says `[oracle@brmdb ...]`.
