# Preparing the Oracle 19c Database for BRM 15.1

What BRM needs from the database before the installer runs: tablespaces and a schema user.
Assumes the database from [guide 01](01-oracle-db-19c-install.md) — a CDB `cdb1` with PDB `PDB1`.

## Multitenant: get the container right first

This is the single most common way to waste an afternoon.

`sqlplus / as sysdba` **always lands in `CDB$ROOT`**. Everything you create goes into whatever
container the session points at, and the root is the default.

| | |
|---|---|
| `CDB$ROOT` (con_id 1) | Oracle's own metadata and common users. **Not for application data.** |
| `PDB$SEED` (con_id 2) | Read-only template for cloning new PDBs |
| `PDB1` (con_id 3) | Your database — where BRM lives |

There is **one instance** (`cdb1`) serving many **services**. PDBs are services on that instance,
not instances, which is why clients must connect by `SERVICE_NAME` and never by SID.

Create BRM's tablespaces at the root and PDB1 cannot see them; containers share nothing. Oracle
will stop you creating a *user* at the root (`ORA-65096: invalid common user or role name`) but it
will happily let you create a *tablespace* in the wrong place.

```sql
alter session set container = PDB1;
show con_name                     -- make this a habit before any DDL
```

Two more consequences worth knowing:

- `DBA_*` views describe **the current container only**. `CDB_*` views span all open containers and
  carry a `con_id`. Querying `dba_users` from the root for a PDB-local user returns "no rows" —
  not because the user is missing, but because you are looking in the wrong dictionary.
- `CDB_*` views **hide `PDB$SEED`** by default and skip any PDB that is merely `MOUNTED`. To see
  everything: `alter session set "_exclude_seed_cdb_view"=FALSE;` and open all PDBs first.

## Turn on OMF first

Oracle Managed Files makes every later `create tablespace` path-free, which is both less error-prone
and what BRM's own sample commands assume:

```sql
-- in CDB$ROOT
alter system set db_create_file_dest='/u02/oradata' scope=both;
```

Use the parent directory, not `/u02/oradata/CDB1` — Oracle appends `DB_UNIQUE_NAME` itself.
PDBs inherit the setting. Files then land under a per-PDB GUID directory as `o1_mf_*.dbf`.

## Tablespaces

The installation guide gives two variants, for "Oracle ASM" and not. The ASM one is really the
*OMF* one — its own test is `show parameters DB_CREATE_FILE_DEST` — so with OMF on, use it:

```sql
alter session set container = PDB1;

create tablespace PIN_TABLE datafile size 600M autoextend on next 64K maxsize unlimited;
create tablespace PIN_INDEX datafile size 400M autoextend on next 64K maxsize unlimited;
create temporary tablespace PIN_TEMP tempfile size 100M autoextend on next 64K maxsize unlimited;
```

Oracle's stated minimums are 600 MB / 400 MB / 100 MB with 64 KB extents, with an explicit caution
that these values are **for demonstration systems only** and will cause performance problems in
production.

> `maxsize unlimited` on a datafile that lives on the root filesystem is a loaded gun on a small
> box: a runaway tablespace fills `/` and takes down the OS and the database together. Capping it
> turns that into a recoverable error:
> `alter database datafile '<path>' autoextend on next 64K maxsize 10G;`

## The BRM schema user

Oracle's docs call it `pin_user`, but that is a **placeholder** — the guide says "Usually, the BRM
database is set up with the user name `pin`, but you can choose another name". Using `pin` matches
every BRM document and tutorial you will read.

Create it **inside PDB1**, where it is a local user needing no `C##` prefix:

```sql
alter session set container = PDB1;
show con_name

create user pin identified by "<PIN_PASSWORD>";
grant resource, connect to pin;
alter user pin default tablespace PIN_TABLE;
alter user pin temporary tablespace PIN_TEMP;

grant unlimited tablespace to pin;        -- NOTE: singular, see below
grant alter session to pin;
grant execute on dbms_lock to pin;
grant execute on dbms_aq to pin;
grant execute on dbms_aqadm to pin;
grant select on sys.gv_$aq to pin;
grant select on v_$session to pin;
grant select on sys.dba_2pc_pending to pin;
grant create synonym, create any synonym, create public synonym, drop public synonym,
      create view, create sequence, create table, create any index,
      create procedure to pin;
```

**Documentation bug:** the installation guide prints `grant unlimited tablespaces to pin_user;`
(plural). There is no such privilege and it fails with `ORA-00990: missing or invalid privilege`.
The system privilege is `UNLIMITED TABLESPACE`, singular. It is granted separately because since
12c the `RESOURCE` role no longer carries it.

## Verify

```sql
-- tablespaces really landed in PDB1 (con_id 3)
select con_id, tablespace_name, status from cdb_tablespaces
where tablespace_name like 'PIN%' order by con_id;

-- the user, in PDB1
alter session set container = PDB1;
select username, account_status, default_tablespace, temporary_tablespace
from dba_users where username = 'PIN';

select granted_role from dba_role_privs where grantee = 'PIN';   -- CONNECT, RESOURCE
select owner, table_name, privilege from dba_tab_privs where grantee = 'PIN';
select privilege from dba_sys_privs where grantee = 'PIN';
```

System privileges, roles and object privileges live in three different views — a short
`dba_sys_privs` result does not mean grants are missing.

Then prove the whole network path, which is what BRM will use:

```bash
sqlplus pin@PDB1
```

That exercises the `tnsnames.ora` alias, the listener, the service, the local user and the
`CONNECT` role in one command.

## Take a restore point before BRM touches anything

With ARCHIVELOG and a flashback-capable FRA (guide 01), a failed BRM install becomes a two-minute
rewind instead of a rebuild:

```sql
alter session set container = PDB1;
create restore point BEFORE_BRM_INSTALL guarantee flashback database;
```

Wait for `Restore point created.` — if the statement was pasted badly and left in the buffer, you
get no restore point and no error.

To rewind later:

```sql
alter session set container = CDB$ROOT;
alter pluggable database PDB1 close immediate;
flashback pluggable database PDB1 to restore point BEFORE_BRM_INSTALL;
alter pluggable database PDB1 open resetlogs;
```

PDB-level flashback needs local undo (`LOCAL_UNDO_ENABLED = TRUE`), which `dbca` sets by default.

Name restore points for the state they contain, not the step you are about to do — a point named
`AFTER_BRM_INSTALL` taken before `pin_setup` succeeded is actively misleading six weeks later.
