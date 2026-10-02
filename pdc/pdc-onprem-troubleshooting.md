# PDC Down on On-Prem (brmlmt151 / 172.23.17.70): Troubleshooting Guide

**Symptom:** Firefox shows "Unable to connect" for
`http://172.23.17.70:7003/pdc/faces/oracle/communications/brm/pdc/ui/pages/login.jspx`

**Rule of thumb:** "Connection refused" means the server isn't running. Find the right domain by its IP, verify its scripts and DB, then start the Admin Server first and the managed server second.

---

## 1. Classify the failure from the network side

```bash
nc -vz 172.23.17.70 7003
curl -v --max-time 5 http://172.23.17.70:7003/
```

- **Connection refused**: the host is reachable but nothing is listening. The WebLogic server is down.
- **Timeout**: firewall, routing, VPN, or the host is down.

## 2. Check what is running on the host

```bash
ps -ef | grep -i weblogic | grep -v grep
ss -tlnp | grep java
```

- Look at `-Dweblogic.Name=` and `-Ddomain.home=` in each process to see which domains are up.
- On brmlmt151 only the BI Publisher domains (`oap`, `bi`) and ECE were running. No PDC domain was up and nothing listened on 7001/7003.

## 3. Identify which domain is the PDC one

Several domains exist under `/app/Middleware/Config/user_projects/domains/`:
`base_domain`, `base_domain_15.0.0`, `base_domain_15.1.0`, `base_domain_PS5`, plus `oap` and `bi` (BI Publisher).

```bash
cd /app/Middleware/Config/user_projects/domains
grep -l "172.23.17.70" */config/config.xml           # bound to the on-prem IP
grep -n "PricingDesignCenter" */config/config.xml    # PDC app deployed
ls -lt | head                                         # recently modified
```

- `grep -l "172.23.17.70"` was the deciding check. Only `base_domain_15.1.0` matched.
- Don't rely on port numbers alone. Several domains all claim 7001/7003.
- `172.23.17.170` is the **CN** environment. Domains with that address (`base_domain_PS5`, `base_domain`) are not the on-prem install. Do not "fix" them by changing `.170` to `.70`.
- The PDC product install is `/app/Middleware/PDC_Home_15.0.1`, but the running domain is built on 15.1.0.

## 4. Pre-flight checks on the chosen domain

```bash
cd /app/Middleware/Config/user_projects/domains/base_domain_15.1.0

# scripts point at THIS domain
grep -n '^DOMAIN_HOME=\|^LONG_DOMAIN_HOME=' startWebLogic.sh bin/startWebLogic.sh bin/setDomainEnv.sh

# listen addresses and ports
grep -nE 'listen-address|listen-port' config/config.xml

# unattended start possible
ls servers/AdminServer/security/boot.properties servers/*/security/boot.properties

# DB URLs, and does the host resolve
grep -ho 'jdbc:oracle:thin:[^<"]*' config/jdbc/*.xml config/fmwconfig/jps-config.xml | sort -u
getent hosts <dbhost>

# memory headroom (ECE runs with large heaps on this host)
free -g
```

**Gotchas we hit:**

- A copied domain can have `DOMAIN_HOME` hardcoded to a different domain. Starting `base_domain_PS5` actually started `base_domain`. Always confirm `domain.home` in the startup log.
- DB host `brm12ps8` did not resolve (`could not resolve the connect identifier`), so JPS looped on retries. That was a CN-style domain, not the on-prem one.
- Check the listener and PDB before starting: `ss -tlnp | grep 1521`.

## 5. Start order

```bash
cd /app/Middleware/Config/user_projects/domains/base_domain_15.1.0

# Admin Server (default port 7001)
nohup ./startWebLogic.sh > admin.out 2>&1 &
tail -f admin.out            # wait for "Server state changed to RUNNING"

# Managed server that hosts PDC (7003 HTTP / 8003 SSL)
nohup ./bin/startManagedWebLogic.sh infra_server_1 http://172.23.17.70:7001 > infra.out 2>&1 &
tail -f infra.out
```

The managed server is slow to start because PDC and BRM web services deploy on startup.

## 6. Verify

```bash
ss -tlnp | grep -E ':7001|:7003'
curl -sI http://172.23.17.70:7003/pdc/faces/oracle/communications/brm/pdc/ui/pages/login.jspx | head -3
```

Expect a 200 or a redirect, then open the login page in the browser.

---

## Key facts

| Item | Value |
|---|---|
| Host | brmlmt151 (172.23.17.70) |
| On-prem domain | `base_domain_15.1.0` |
| Admin Server | `172.23.17.70:7001` |
| PDC managed server | `infra_server_1`, 7003 (HTTP) / 8003 (SSL) |
| PDC app | `PricingDesignCenter` |
| DB | `brmlmt151:1521/orclpdb` |
| CN environment | `172.23.17.170`, not on-prem |
| Logs | `servers/infra_server_1/logs/infra_server_1.log`, `admin.out`, `infra.out` |

## If it fails after starting

| Error | Likely cause |
|---|---|
| `Cannot assign requested address` | Wrong `listen-address` in `config.xml` |
| `ORA-...` or `could not resolve the connect identifier` | DB listener, PDB state, credentials, or hostname |
| `BEA-149...` or deployment failed | `PricingDesignCenter` deployment error; check the managed server log |
| Stuck in STARTING | Slow deployment; wait a few minutes and follow the server log |
