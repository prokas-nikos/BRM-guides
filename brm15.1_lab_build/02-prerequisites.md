# BRM 15.1 Prerequisites on Oracle Linux 8.10

What BRM 15.1 actually requires, and how to get each piece onto OL 8.10.

## The versions that matter

Taken from the BRM 15.1 Compatibility Matrix (`compatibility-matrix.pdf`). Verify against your own
release — do **not** reuse the 12.0 matrix, which differs on nearly every line.

| Component | BRM 15.1 requires |
|---|---|
| Oracle Database Enterprise Edition | 19.x where **x >= 23** |
| Oracle Database Client | 19.x where x >= 20 |
| Oracle Linux / RHEL | **8.10 or later** (or 9.4+) |
| Oracle Java SE | **21.0.6** |
| Perl (64-bit) | **5.38.2** |
| Compilers | **gcc 12.2.1** |
| Apache Kafka client | 3.8.0 |
| Apache Tomcat | 11.0.2 |
| Oracle WebLogic Server | 14.1.2 (needed by PDC) |
| Oracle Coherence for Java | 14.1.2 (needed by ECE, **not** bundled with it) |
| Groovy | 4.0.22 (ECE monitoring tools, not bundled) |

> The compatibility matrix lists versions but no steps; the installation guide lists steps but
> defers versions. You need both open.

## Java 21

In the OL 8 AppStream, so this is the easy one:

```bash
sudo dnf install java-21-openjdk-devel
```

Point `JAVA_HOME` at the **alternatives-maintained symlink**, never the versioned directory —
the latter changes on every JDK patch and silently breaks everything downstream:

```bash
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk      # correct
# NOT /usr/lib/jvm/java-21-openjdk-21.0.12.1.1-1.1.0.1.el8.x86_64
```

Use the SDK (`java-21-openjdk`), not the JRE (`jre-21-openjdk`) — BRM's installers need `javac`.

## Perl 5.38.2 — must be built from source

OL 8's `perl` module streams stop at 5.32:

```
$ dnf module list perl
perl 5.24 / 5.26 [d][e] / 5.30 / 5.32
```

There is no packaged route to 5.38.2, so build it. **Use Oracle's exact `Configure` flags** —
an equivalent-looking line of your own is not equivalent:

```bash
sudo dnf install gcc make gdbm-devel.x86_64 libdb-devel.x86_64 zlib-devel bzip2-devel

cd /home/pin/perl_build
wget https://www.cpan.org/src/5.0/perl-5.38.2.tar.gz
sha256sum perl-5.38.2.tar.gz     # compare with perl-5.38.2.tar.gz.sha256.txt from the same dir
tar -xzf perl-5.38.2.tar.gz
cd perl-5.38.2

# Oracle's prescribed temporary clean environment — THIS SHELL ONLY, never in .bashrc
export -n PATH
export -n LD_LIBRARY_PATH
export PATH=/usr/bin:/usr/local/bin:/bin

sh Configure -des \
  -Accflags=-fPIC \
  -Dcc="gcc -m64 -D_FORTIFY_SOURCE=1" \
  -Dusethreads \
  -Duserelocatableinc \
  -Dprefix=/opt/perl-5.38.2

make -j4
sudo make install
```

Verify all four properties:

```bash
/opt/perl-5.38.2/bin/perl -V:usethreads          # define
/opt/perl-5.38.2/bin/perl -V:userelocatableinc   # define
/opt/perl-5.38.2/bin/perl -V:ptrsize             # 8
/opt/perl-5.38.2/bin/perl -V:ccflags             # contains -fPIC
```

`-Accflags=-fPIC` is the flag most likely to matter: BRM links Perl into shared objects.

Two traps:

- **Leave `/usr/bin/perl` (5.26.3) alone.** `dnf` and system scripts depend on it.
- **The `export -n PATH` block is temporary.** It comes straight from the install guide and is
  correct *for the build shell*. Left in `.bashrc` it wipes `$ORACLE_HOME/bin` and
  `$JAVA_HOME/bin` from every login — see guide 06.

Run the build under `screen`; it takes 15–25 minutes and an SSH drop costs you the whole thing.

## gcc 12.2.1

The system compiler is 8.5.0. Oracle wants 12.2.1, available as a Software Collection:

```bash
sudo dnf install gcc-toolset-12
source /opt/rh/gcc-toolset-12/enable      # activate when needed
gcc --version                             # 12.2.1
```

This does not replace the system compiler; it is opt-in per shell.

## Apache Kafka 3.8.0

Not in the repos — a tarball from Apache. The matrix asks for the Kafka **client**, so extracting
the archive is enough; no broker is needed to install BRM.

```bash
wget https://archive.apache.org/dist/kafka/3.8.0/kafka_2.13-3.8.0.tgz
sha512sum kafka_2.13-3.8.0.tgz    # compare against ...tgz.sha512 from the same directory
tar -xzf kafka_2.13-3.8.0.tgz
```

`libs/kafka-clients-3.8.0.jar` is the artifact the matrix actually names. Kafka 3.8 needs Java 17+,
so Java 21 is fine. Run a broker in KRaft mode when you eventually need one — ZooKeeper is the
deprecated path that older tutorials still show.

## ojdbc8.jar

The installation guide says to download it, but if the machine has an Oracle database home you
already have a copy matched to your database version, which is what the guide actually asks for:

```bash
mkdir -p /app/pin/Thirdparty
cp $ORACLE_HOME/jdbc/lib/ojdbc8.jar /app/pin/Thirdparty/
```

The installer prompts for the **directory**, not the jar path, in its "Specify Prerequisite
Libraries Location" window.

## Environment

Everything BRM runs as the `pin` user. In `~/.bashrc`:

```bash
export ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1
export PATH=$PATH:$ORACLE_HOME/bin

export JAVA_HOME=/usr/lib/jvm/java-21-openjdk
export PATH=$JAVA_HOME/bin:$PATH

export PERL_HOME=/opt/perl-5.38.2
export PATH=$PERL_HOME/bin:$PATH

export KAFKA_HOME=/home/pin/brm_installation/prereqs/kafka/kafka_2.13-3.8.0
export PATH=$KAFKA_HOME/bin:$PATH

export LD_LIBRARY_PATH=$ORACLE_HOME/lib
export NLS_LANG=American_America.AL32UTF8
export TNS_SERVICE_NAME=pdb1
export TNS_ADMIN=/app/pin/BRM/network/admin      # see guide 05 — wallet-enabled sqlnet.ora
export PIN_HOME=/app/pin/BRM
export HOSTNAME=$(hostname -f)

# BRM environment; the guard stops repeated sourcing stacking PATH entries
if [ -z "$BRM_ENV_LOADED" ] && [ -f "$PIN_HOME/source.me.sh" ]; then
    . "$PIN_HOME/source.me.sh"
    export BRM_ENV_LOADED=1
fi
```

`NLS_LANG` must be `American_America` regardless of locale — the guide is explicit about this, and
a client/server character-set mismatch corrupts data silently.

`$PIN_HOME/bin` is **not** added by any of the above; only `source.me.sh` does that. Without it
`testnap` and friends are "command not found" even on a perfectly good install.
