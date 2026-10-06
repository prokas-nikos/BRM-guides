# BRM Integrations — Web Services Customization

This directory contains all tooling to extend and rebuild the Oracle BRM 15.1
WebLogic web services WAR (`BrmWebServices.war`) for the LMT COBRA project.

The core idea is to start from the OOTB Oracle base WAR, extend selected
services with LMT-specific opcodes, generate new Java sources via `pin_wsgen`,
rebuild `web_services.jar` with the extended classes, and repackage the WAR.

---

## Directory Structure

```
brm_integrations/
├── config/
│   ├── pin_wsdl_generator.xml      # Opcode-to-service mapping (SOAP 1.1 + 1.2 WSDLs generated from here)
│   └── wsdl_gen/
│       ├── soap11/                 # Generated SOAP 1.1 WSDLs
│       └── soap12/                 # Generated SOAP 1.2 WSDLs
├── custom_services/
│   ├── custom_services.xml         # Ant build file — generates sources, compiles, jars
│   ├── jar/                        # Runtime jars needed for compilation (web_services.jar, jaxws etc.)
│   ├── src/                        # Generated Java sources (pin_wsgen output)
│   ├── classes/                    # Compiled .class files
│   └── wsdl/                       # Working WSDL copies used by pin_wsgen
├── schemas/
│   ├── *.xsd                       # OOTB BRM XSD schemas
│   ├── custom/                     # LMT-specific XSD schemas (LMT_OP_* opcodes)
│   └── merged/                     # Combined OOTB + custom XSDs (created at build time)
├── WSM/
│   └── *.xsd                       # Additional XSDs for custom opcodes
├── httpsfilter/
│   ├── WsdlRewriteFilter.java      # Rewrites WSDL URLs in responses
│   └── CharResponseWrapper.java    # Helper for WsdlRewriteFilter
├── custom_sun_jaws.awk             # Patches WEB-INF/sun-jaxws.xml (injects CUSTOM endpoints)
├── custom_web_xml.awk              # Patches WEB-INF/web.xml (injects WsdlRewriteFilter)
└── deploy_custom_flds_wsm_15.1.sh  # Master deploy script — orchestrates the entire build
```

---

## Services Overview

The following BRM web services are included in the deployed WAR. Services
marked **Extended** have been augmented with LMT-specific opcodes on top of
the OOTB Oracle operations. Services marked **New** do not exist in the OOTB
base WAR and are added entirely by this build.

| Service endpoint | Type | Java package | Notes |
|---|---|---|---|
| `BRMARServices12_v2` | Extended | `com.portal.jax.ar` | + `LMT_OP_GET_ACCT_BAL_PENDINGBILL_VAT`, `PCM_OP_AR_GET_ITEM_DETAIL` |
| `BRMBillServices12_v2` | Extended | `com.portal.jax.bill` | + `PCM_OP_BILL_MAKE_BILL`, `PCM_OP_BILL_MAKE_BILL_ON_DEMAND`, `PCM_OP_BILL_MAKE_CORRECTIVE_BILL`, `PCM_OP_BILL_GROUP_*` |
| `BRMContractServices12_v2` | Extended | `com.portal.jax.contract` | + 36 `LMT_OP_CONTRACT_*` opcodes (Finoblg, Minfee, Fixterm, Rent, Device, Installment, Insurance) |
| `BRMCollectionsServices12_v2` | Extended | `com.portal.jax.collection` | + `PCM_OP_COLLECTIONS_EXEMPT_BILLINFO`, `PCM_OP_COLLECTIONS_GET_SCENARIO_DETAIL` etc. |
| `BRMCustServices12_v2` | Extended | `com.portal.jax.cust` | Extended CUST opcodes |
| `BRMDepositServices12_v2` | Extended | `com.portal.jax.deposit` | + `LMT_OP_DEPOSIT_BATCH_CREATE` |
| `BRMPymtServices12_v2` | Extended | `com.portal.jax.pymt` | Custom `PCM_OP_PYMT_COLLECT` |
| `BRMSubscriptionServices12_v2` | Extended | `com.portal.jax.subscription` | + `PCM_OP_SUBSCRIPTION_SHARING_GROUP_*`, `PCM_OP_SUBSCRIPTION_TRANSITION_PLAN` |
| `BRMUMSServices12_v2` | **New** | `com.portal.jax.custom` | `PCM_OP_UMS_SET_MESSAGE` |
| `BRMCUSTOMServices12_v2` | Legacy | `com.portal.jax.custom` | Kept for backward compatibility during tester migration |
| All other OOTB services | OOTB | `com.portal.jax.*` | Unchanged from base WAR |

Each service is available in both SOAP 1.1 (`*Services_v2`) and SOAP 1.2
(`*Services12_v2`) variants. Use SOAP 1.2 for new integrations.

---

## How It Works

### The Problem

The OOTB `BrmWebServices.war` ships with `web_services.jar` containing
pre-compiled JAX-WS endpoint classes for each BRM service
(`BRMContractService12PttImpl`, `BRMARService12PttImpl` etc.). Each
`PttImpl` class only knows about the opcodes that were in the service when
Oracle generated it. To add new LMT opcodes to an existing service, the
`PttImpl` must be regenerated with the new operations included and the
rebuilt class must replace the one in `web_services.jar`.

### The Solution

1. `pin_wsdl_generator` reads `pin_wsdl_generator.xml` and generates new
   WSDLs for every service group — including all LMT opcodes merged into the
   relevant OOTB groups.
2. `pin_wsgen` processes each WSDL and generates new Java sources. For
   extended OOTB services the same package as Oracle is used
   (`com.portal.jax.contract`, `com.portal.jax.ar` etc.) so the generated
   `PttImpl` directly replaces the OOTB class when merged back into
   `web_services.jar`.
3. The Ant build (`custom_services.xml`) compiles all generated sources and
   produces a `custom_services.jar`.
4. The deploy script extracts the OOTB base WAR, merges the new classes into
   `web_services.jar`, injects the `WsdlRewriteFilter` into `web.xml`, injects
   the `BRMCUSTOMServices` and `BRMUMSServices` endpoints into
   `sun-jaxws.xml`, overwrites the OOTB WSDLs with the extended ones, and
   repackages the WAR.

---

## Build & Deploy

### Prerequisites

- Oracle BRM 15.1 installed at `$PIN_HOME` (`/app/pin/BRM`)
- Java 8 at `/usr/lib/jvm/jdk-1.8-oracle-x64`
- Apache Ant at `/app/Middleware/Oracle_Home/oracle_common/modules/thirdparty/org.apache.ant/1.10.5.0.0/apache-ant-1.10.5/bin/ant`
- WebLogic domain running at `172.23.17.70:7003`

### Build both STD and CN WARs

```bash
cd /app/pin/BRM/deploy/web_services
./deploy_custom_flds_wsm_15.1.sh /app/pin/BRM BrmWebServices.war.CN.15.1.0.0.0-38709835
```

### Build a specific variant only

```bash
# STD only
./deploy_custom_flds_wsm_15.1.sh /app/pin/BRM BrmWebServices.war.CN.15.1.0.0.0-38709835 STD

# CN only
./deploy_custom_flds_wsm_15.1.sh /app/pin/BRM BrmWebServices.war.CN.15.1.0.0.0-38709835 CN
```

### To deploy the war file

#### On-prem
Deploy via WebLogic console

#### Cloud Native
Build image brm_wsm_wls_custom and brm_wsm_wl_init and deploy wsm

---

## Deploy Script Steps (deploy_custom_flds_wsm_15.1.sh)

The script performs the following steps in order:

1. **Validate input** — checks `$PIN_HOME`, input WAR filename, and optional
   build type (`STD` / `CN` / both).

2. **Generate custom fields** — runs `gen_custom_ops_fields.sh` to create
   BRM custom field definitions.

3. **Extract base WAR** — extracts the OOTB `BrmWebServices.war` to
   `temp/`.

4. **Build `schemas/merged/`** — combines OOTB XSDs (`schemas/*.xsd`),
   extracted WAR XSDs (`WEB-INF/wsdl/*.xsd`), and custom LMT XSDs
   (`WSM/*.xsd`) into `schemas/merged/` so `pin_wsdl_generator` has a
   single `includePath` covering all opcode schemas.

5. **Generate WSDLs** — runs `pin_wsdl_generator` against
   `pin_wsdl_generator.xml` (SOAP 1.1) and a dynamically created
   `pin_wsdl_generator_v12.xml` (SOAP 1.2).

6. **Copy WSDLs** — copies generated WSDLs to:
   - `custom_services/wsdl/` — for `pin_wsgen` source generation
   - `WEB-INF/wsdl/` — overwrites OOTB WSDLs with extended versions
   - `BRMCustomServices` is renamed to `BRMCUSTOMServices` when copying to
     `WEB-INF/wsdl/` for legacy compatibility

7. **Copy `web_services.jar`** — copies the OOTB `web_services.jar` from the
   extracted WAR into `custom_services/jar/` so it is available on the Ant
   compile classpath.

8. **Ant build** — runs `ant -file custom_services.xml`:
   - Runs `pin_wsgen` for each service group to generate Java sources
   - Runs `pin_wsgen` against `BRMCustomServices_v2.wsdl` to regenerate a
     complete `ObjectFactory.java` covering all custom opcodes
   - Compiles all sources into `classes/`
   - Jars everything into `custom_services.jar`

9. **Merge into `web_services.jar`** — for each service in `CUSTOM_SERVICE_MAP`,
   extracts the compiled classes from `custom_services.jar` and merges them
   into the OOTB `web_services.jar`, replacing the OOTB `PttImpl` classes.

10. **Copy filter sources** — copies `httpsfilter/*.java` into
    `custom_services/src/com/portal/jax/custom/filter/`.

11. **Patch `sun-jaxws.xml`** — runs `custom_sun_jaws.awk` to inject
    `BRMCUSTOMServices` and `BRMUMSServices` endpoints.

12. **Patch `web.xml`** — runs `custom_web_xml.awk` to inject
    `WsdlRewriteFilter`.

13. **Build WAR(s)** — repackages `WEB-INF/` into `BrmWebServices.STD.war`
    and/or `BrmWebServices.CN.war` with the appropriate `Infranet.properties`.

---

## Adding a New Opcode to an Existing Service

1. Add the XSD schema file to `WSM/` (for LMT opcodes) or `schemas/`
   (for OOTB overrides).

2. Add the opcode to the relevant group in
   `config/pin_wsdl_generator.xml`. Also add it to the `CUSTOM` mirror
   group so `ObjectFactory.java` stays complete.

3. Run the deploy script. `pin_wsdl_generator` regenerates the WSDL,
   `pin_wsgen` generates the new dispatch method, and the rebuilt
   `web_services.jar` includes the updated `PttImpl`.

### Example — adding `LMT_OP_CONTRACT_NEW_OPCODE` to Contract service

```xml
<!-- in pin_wsdl_generator.xml, Contract group -->
<opcode name="LMT_OP_CONTRACT_NEW_OPCODE"></opcode>

<!-- also in CUSTOM group -->
<opcode name="LMT_OP_CONTRACT_NEW_OPCODE"></opcode>
```

---

## Adding a Completely New Service

1. Add the XSD to `WSM/`.
2. Create a new group in `pin_wsdl_generator.xml` with
   `includePath="../schemas/merged/"`.
3. Add also to the `CUSTOM` group.
4. Add a `pin_wsgen` target pair (SOAP 1.1 + 1.2) to `custom_services.xml`
   and add both to the `regenerate_objectfactory` depends list.
5. Add the service to `CUSTOM_SERVICE_MAP` in the deploy script with
   `["BRMNewServices"]="BRMNewServices"`.
6. If the service is not in the OOTB base WAR, add its endpoints to
   `custom_sun_jaws.awk`.

---

## Key Files Reference

| File | Purpose |
|---|---|
| `config/pin_wsdl_generator.xml` | Maps opcodes to service groups; drives WSDL generation |
| `custom_services/custom_services.xml` | Ant build — `pin_wsgen`, compile, jar |
| `custom_sun_jaws.awk` | Injects new endpoints into `WEB-INF/sun-jaxws.xml` |
| `custom_web_xml.awk` | Injects `WsdlRewriteFilter` into `WEB-INF/web.xml` |
| `deploy_custom_flds_wsm_15.1.sh` | Master build and deploy orchestrator |
| `httpsfilter/WsdlRewriteFilter.java` | Rewrites WSDL endpoint URLs in SOAP responses |
| `schemas/merged/` | Combined XSD directory (created at build time, not committed) |

---

## Notes

- `schemas/merged/` is created at build time and should not be committed to git.
- `BRMCUSTOMServices12_v2` is kept active for backward compatibility while
  teams migrate to the extended OOTB service endpoints. It will be removed
  in a future release.
- `PCM_OP_SUBSCRIPTION_TRANSITION_PLAN` also exists in the OOTB
  `BRMSubscriptionServices` base WAR WSDL — this duplicate is a known
  issue and will be addressed in a future build.
