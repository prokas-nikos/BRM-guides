# PDC / WebLogic – Startup and Shutdown Guide

Procedure for starting and stopping the PDC WebLogic domain and the PDC Transformation Engines (RRE and BRE) on `brmlmt151`.

## Overview

The PDC stack consists of three layers that must be started and stopped in a specific order:

1. **WebLogic Admin Server** – manages the domain.
2. **WebLogic Managed Server** (`infra_server_1`) – hosts the PDC application.
3. **Transformation Engines** (RRE and BRE) – run as standalone processes outside WebLogic and handle the rating and pricing data transformation.

**Startup order:** Admin Server → Managed Server → Transformation Engines
**Shutdown order:** Managed Server → Admin Server (the Transformation Engines are stopped separately)

## Shell Aliases and Paths

Two shell aliases are used throughout this guide. Run them as the `pin` user:

| Alias  | Directory                                                              | Purpose                               |
|--------|------------------------------------------------------------------------|---------------------------------------|
| `dbin` | `/app/Middleware/Config/user_projects/domains/base_domain_15.1.0/bin`  | WebLogic domain scripts               |
| `pbin` | `/app/Middleware/PDC_Home/PDC_BRM/apps/bin`                            | PDC Transformation Engine scripts     |

Example:

```bash
[pin@brmlmt151 BRM]$ dbin
[pin@brmlmt151 bin]$ pwd
/app/Middleware/Config/user_projects/domains/base_domain_15.1.0/bin
[pin@brmlmt151 bin]$ pbin
[pin@brmlmt151 bin]$ pwd
/app/Middleware/PDC_Home/PDC_BRM/apps/bin
```

## Startup

### 1. Start the Admin Server

```bash
dbin
nohup ./startWebLogic.sh > as.out &
tail -f as.out
```

Wait until the log shows that the server has reached the **RUNNING** state before continuing. `nohup` keeps the process alive after you close the terminal session, and the output is redirected to `as.out`.

### 2. Start the Managed Server

```bash
dbin
nohup ./startManagedWebLogic.sh infra_server_1 > ms.out &
tail -f ms.out
```

Again, wait for the **RUNNING** state in `ms.out` before starting the Transformation Engines.

### 3. Start the Transformation Engines

The Transformation Engines must be started **after** the Managed Server is up.

> **Important – if PDC was stuck or hung:**
> Before starting the engines, the **PVT must be set back to the reference date** used for the products. Otherwise the products will be synchronized with an incorrect PVT.

Start the RRE Transformer:

```bash
pbin
./startRRETransformer
# enter the password when prompted
# press Ctrl-Z to suspend the process
bg
disown -h
```

Then start the BRE Transformer:

```bash
./startBRETransformer
# enter the password when prompted
# press Ctrl-Z to suspend the process
bg
disown -h
```

**What the Ctrl-Z / bg / disown sequence does:**

- `Ctrl-Z` suspends the foreground process after the password has been entered.
- `bg` resumes it in the background.
- `disown -h` detaches it from the shell so it keeps running (it won't receive SIGHUP) when you log out.

Use `ps -ef | grep -i transformer` to verify both processes are running.

## Shutdown

The **Managed Server must be stopped first**, then the Admin Server.

### 1. Stop the Managed Server

```bash
dbin
./stopManagedWebLogic.sh infra_server_1
```

### 2. Stop the Admin Server

```bash
./stopWebLogic.sh
```

## Quick Reference

| Action                  | Directory | Command                                                      |
|-------------------------|-----------|--------------------------------------------------------------|
| Start Admin Server      | `dbin`    | `nohup ./startWebLogic.sh > as.out &`                        |
| Start Managed Server    | `dbin`    | `nohup ./startManagedWebLogic.sh infra_server_1 > ms.out &`  |
| Start RRE Transformer   | `pbin`    | `./startRRETransformer`                                      |
| Start BRE Transformer   | `pbin`    | `./startBRETransformer`                                      |
| Stop Managed Server     | `dbin`    | `./stopManagedWebLogic.sh infra_server_1`                    |
| Stop Admin Server       | `dbin`    | `./stopWebLogic.sh`                                          |

## Notes

- Always follow the start/stop order above; stopping the Admin Server first can leave the Managed Server in an inconsistent state.
- Monitor `as.out` and `ms.out` for errors during startup.
- If PDC is stuck, reset the PVT to the product reference date **before** bringing up the Transformation Engines.
