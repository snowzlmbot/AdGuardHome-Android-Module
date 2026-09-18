# AdGuardHome Android Module Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development or executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a public-ready Magisk/KernelSU AdGuard Home Android module for arm64 and armv7 that combines the useful behavior of the two audited projects while isolating optional features and removing unsafe update, deletion, and rollback logic.

**Architecture:** Use an A+ modular design. `service.sh` starts a supervisor that coordinates independent core, network, firewall, proxy-adapter, file-adapter, and diagnostics components. Components communicate through atomic state/request files and have separate PIDs, locks, logs, retry budgets, and failure states; the only hard safety dependency is that DNS redirection is removed when the AdGuard Home core is not healthy.

**Tech Stack:** POSIX/BusyBox `ash`; Magisk/KernelSU module contract; AdGuard Home official arm64/armv7 assets; iptables/ip6tables with explicit ownership chains; shell-based fixture tests on Linux; GitHub Actions for release packaging and checksum/SBOM generation.

---

## Scope and fixed decisions

- Repository target: `snowzlmbot/AdGuardHome-Android-Module`.
- Public repository creation is the final external step, after local implementation and verification.
- Supported managers: Magisk and KernelSU.
- Supported architectures: arm64 and armv7; unsupported ABI must abort installation.
- DNS modes: LAN-compatible, encrypted-upstream, and Bootstrap.
- First install: random Web UI password stored root-only; no public `root/root` default.
- Proxy adapter: Box, `box_bll`, Clash, and Mihomo paths; default disabled; backup and conditional restoration required.
- File adapter: the maintained project's target list may be included as candidates; default disabled; no unconditional deletion of other module files, databases, shared preferences, IFW, or `==deleted==` directories.
- IPv4/IPv6 DNS and TCP/UDP 853 protection: independently configurable and enabled by default; documentation must describe compatibility effects.
- Updates: GitHub Release ZIP only, SHA-256/signature verified, user installs manually; runtime never downloads and executes shell code.
- Attribution: separate `CREDITS.md`, `THIRD_PARTY_NOTICES.md`, GPL-3.0/ MIT notices, rule-source metadata, and no direct copying of unlicensed first-upstream scripts.

---

### Task 1: Create the module skeleton and test harness

**Files:**
- Create: `module.prop`
- Create: `customize.sh`
- Create: `service.sh`
- Create: `action.sh`
- Create: `uninstall.sh`
- Create: `boot-completed.sh`
- Create: `scripts/lib/common.sh`
- Create: `scripts/lib/atomic.sh`
- Create: `scripts/lib/process.sh`
- Create: `scripts/lib/log.sh`
- Create: `tests/run.sh`
- Create: `tests/fixtures/README.md`
- Create: `tests/static/check-shell.sh`

- [ ] **Step 1: Write static shell checks before implementation.**

`tests/static/check-shell.sh` must enumerate every `*.sh` under the project excluding `.git`, run `/usr/bin/busybox ash -n`, and fail on Bash-only constructs:

```sh
#!/usr/bin/env sh
set -eu
root=${1:?project root required}
busybox_bin=${BUSYBOX_BIN:-busybox}
status=0
for file in $(find "$root" -type f -name '*.sh' -not -path '*/.git/*' | sort); do
  "$busybox_bin" ash -n "$file" || status=1
  if grep -nE '(^|[^[:alnum:]_])(<<<|\[\[|declare |local |[A-Za-z_][A-Za-z0-9_]*\+=\(|\$\{[^}]*//)' "$file"; then
    printf '%s\n' "Bash-only syntax found in $file" >&2
    status=1
  fi
done
exit "$status"
```

- [ ] **Step 2: Write the fixture runner.**

`tests/run.sh` must run static checks, library tests, state transition fixtures, firewall command-recording fixtures, migration fixtures, and package-layout checks. It must create a temporary directory with `mktemp -d`, install a cleanup trap, and return nonzero on any failure.

- [ ] **Step 3: Add the minimal module metadata and entrypoint stubs.**

Use an explicit module ID `AdGuardHome`, a semver-like module version, `minMagisk=20400`, and a description that does not expose a password. `customize.sh`, `service.sh`, `action.sh`, `uninstall.sh`, and `boot-completed.sh` must start with `#!/system/bin/sh` and source only project-local libraries.

- [ ] **Step 4: Run the failing baseline.**

Run:

```sh
BUSYBOX_BIN=busybox sh tests/static/check-shell.sh .
```

Expected: failure because the entrypoint and library behavior tests are not implemented yet. Record the failure as the baseline for this task.

- [ ] **Step 5: Implement common libraries.**

`common.sh` defines `MODDIR`, `AGH_ROOT`, `AGH_CONFIG_DIR`, `AGH_STATE_DIR`, `AGH_RUN_DIR`, `AGH_LOG_DIR`, and safe path helpers. `atomic.sh` writes to a same-directory temporary file, calls `sync`, and renames only after the write succeeds. `process.sh` provides `pid_is_ours`, `stop_pid_bounded`, and `wait_for_file`. `log.sh` provides timestamped component logs with a 256 KiB rotation threshold.

- [ ] **Step 6: Run the harness again.**

Run:

```sh
sh tests/run.sh
```

Expected: static shell checks pass for all current scripts; unimplemented behavior tests are not yet included in the pass criteria for later tasks.

---

### Task 2: Implement architecture, binary, port, and credential validation

**Files:**
- Create: `scripts/lib/platform.sh`
- Create: `scripts/lib/credentials.sh`
- Create: `tests/platform_test.sh`
- Create: `tests/credentials_test.sh`
- Modify: `customize.sh`
- Modify: `scripts/lib/common.sh`

- [ ] **Step 1: Write platform fixture tests.**

Test `normalize_arch` for `arm64`, `aarch64`, `arm`, `armv7`, unsupported `x86`, and empty input. Test `elf_matches_arch` with fixture metadata rather than executing an Android binary. Test that a missing binary, mismatched ELF machine, or failed checksum returns an error.

- [ ] **Step 2: Implement exact architecture selection.**

`platform.sh` must normalize only these values:

```sh
case "$raw_arch" in
  arm64|aarch64) AGH_ARCH=arm64 ;;
  arm|armv7|armeabi-v7a) AGH_ARCH=armv7 ;;
  *) die "Unsupported architecture: $raw_arch" ;;
esac
```

The installer must select `bin/arm64/AdGuardHome` or `bin/armv7/AdGuardHome`, verify it exists, verify the ELF machine with an Android-compatible helper or precomputed release metadata, and verify SHA-256 before installation. A failed copy or missing asset must abort.

- [ ] **Step 3: Write port allocation tests.**

Test deterministic reuse of an existing valid port, rejection of ports below 1024, rejection of a port reported as occupied by the injectable `port_is_free` function, and retry when DNS and Web ports collide.

- [ ] **Step 4: Implement persistent port allocation.**

Store `web_port` and `dns_port` in `/data/adb/agh/state/ports.conf` with mode `0600`. Use a bounded range, check that the two ports differ, and never rewrite ports during a soft restart when the core is still healthy.

- [ ] **Step 5: Write credential tests.**

Test first-install generation, root-only file mode, preservation on upgrade, and non-disclosure in `module.prop`, logs, and normal action output.

- [ ] **Step 6: Implement random credential generation.**

Read entropy from `/dev/urandom` through BusyBox utilities, generate a password without shell-evaluating it, write only to a `0600` state file, and render the password only from an explicit privileged action. Existing valid credentials must be retained during migration.

- [ ] **Step 7: Run targeted tests.**

Run:

```sh
sh tests/platform_test.sh
sh tests/credentials_test.sh
sh tests/static/check-shell.sh .
```

Expected: all tests pass and no unsupported architecture is accepted.

---

### Task 3: Implement configuration storage and legacy migration

**Files:**
- Create: `scripts/migrate.sh`
- Create: `scripts/config.sh`
- Create: `tests/migration_test.sh`
- Create: `tests/fixtures/legacy-a/AdGuardHome.yaml`
- Create: `tests/fixtures/legacy-a/mode.conf`
- Create: `tests/fixtures/legacy-b/bin/AdGuardHome.yaml`
- Create: `tests/fixtures/legacy-b/scripts/config.prop`
- Modify: `customize.sh`

- [ ] **Step 1: Write migration tests for both upstream layouts.**

The tests must cover: first install, first-upstream module data under `/data/adb/modules/AdGuardHome`, maintained-upstream data under `/data/adb/agh`, both paths present, malformed YAML, missing configuration, failed copy, and already-migrated state. Assertions must verify that the old source remains unchanged after success and failure.

- [ ] **Step 2: Implement source discovery.**

`migrate.sh` must return a single source record with type `legacy-a`, `legacy-b`, or `new`. It must never delete or mark another module for removal. If both old layouts exist, prefer the newest valid user configuration only after comparing modification times and recording the choice; never silently overwrite one source with the other.

- [ ] **Step 3: Implement temporary migration.**

Copy source files into `$AGH_ROOT/.migration-<pid>`, validate regular files and path boundaries, translate `mode.conf`/`config.prop` keys, copy filters, and write a migration manifest containing source path, file hash, and schema version. Abort and remove only the temporary directory on any validation failure.

- [ ] **Step 4: Implement field-preserving configuration merge.**

Keep user accounts, upstreams, filters, custom rules, cache settings, and query settings. Add only missing new defaults. Do not replace the complete YAML with a template. Write the merged output through `atomic_write` and preserve the old configuration until the new file passes validation.

- [ ] **Step 5: Implement migration commit and rollback.**

After every destination file validates, rename the temporary migration directory into place and write `schema.version`. If the commit fails, keep the old destination and write a migration failure record. Do not report installation complete after a partial migration.

- [ ] **Step 6: Run migration tests.**

Run:

```sh
sh tests/migration_test.sh
```

Expected: both legacy layouts migrate without modifying source fixtures; malformed or incomplete input leaves the destination unchanged and returns nonzero.

---

### Task 4: Implement the AdGuard Home core worker and supervisor control plane

**Files:**
- Create: `scripts/core-worker.sh`
- Create: `scripts/supervisor.sh`
- Create: `scripts/control.sh`
- Create: `tests/core_worker_test.sh`
- Create: `tests/supervisor_test.sh`
- Modify: `service.sh`
- Modify: `boot-completed.sh`

- [ ] **Step 1: Write core state-machine tests.**

Test transitions `missing -> error`, `stopped -> starting -> ready`, `ready -> unhealthy`, `unhealthy -> backoff`, and `disabled -> stopped`. Use fake `AdGuardHome`, `pid_is_ours`, and port probes. Assert that a non-ready core never authorizes firewall installation.

- [ ] **Step 2: Implement core-worker.**

The worker must use explicit `--config`, `--work-dir`, and `--no-check-update`, write a PID file atomically, verify `/proc/<pid>/exe` and command arguments, probe both Web and DNS ports, and write `ready`, `degraded`, or `failed` state. It must use bounded exponential backoff capped at 60 seconds.

- [ ] **Step 3: Write supervisor isolation tests.**

Start fake workers that independently exit with failures. Assert that a proxy or file worker failure leaves the core state unchanged, a firewall failure leaves the core running, and a core failure produces a firewall removal request.

- [ ] **Step 4: Implement supervisor.**

Supervisor starts only enabled workers, checks their PID and state directories separately, restarts each worker using its own backoff file, and aggregates status without collapsing a component failure into a core failure. It must not contain iptables commands, direct proxy YAML editing, or application file deletion.

- [ ] **Step 5: Implement control requests.**

`control.sh` writes atomic request files for `pause`, `resume`, `enable`, `disable`, `restart-core`, and `status`. Supervisor consumes requests exactly once by renaming them into a processed directory and records the result.

- [ ] **Step 6: Implement entrypoints.**

`service.sh` waits for the module runtime directories and starts supervisor once. `boot-completed.sh` is used only for actions that require the Android boot-completed property; it must not duplicate supervisor startup.

- [ ] **Step 7: Run worker tests.**

Run:

```sh
sh tests/core_worker_test.sh
sh tests/supervisor_test.sh
```

Expected: independent component failures do not stop unrelated workers; core failure removes DNS authorization before retry.

---

### Task 5: Implement network modes and firewall worker

**Files:**
- Create: `scripts/network-worker.sh`
- Create: `scripts/firewall-worker.sh`
- Create: `tests/network_test.sh`
- Create: `tests/firewall_test.sh`
- Create: `tests/fixtures/iptables-recording-bin/`
- Modify: `scripts/supervisor.sh`
- Modify: `config/mode.conf`

- [ ] **Step 1: Write network-mode tests.**

Use recorded network snapshots for Wi-Fi, mobile, VPN, Ethernet, no-network, IPv4-only, and IPv6-only cases. Test all three modes and assert that network-worker produces structured state without issuing firewall commands.

- [ ] **Step 2: Implement network-worker.**

Use injectable discovery commands and validate every parsed address. Emit a state file only after all required fields are valid. On invalid or changing input, keep the last known good state and write a reason. Do not parse fixed line numbers or assume a third DNS entry.

- [ ] **Step 3: Write firewall command-recording tests first.**

The fake `iptables`, `ip6tables`, and `iptables-save` commands must record arguments and return configured success/failure values. Tests must assert: unique chain ownership, one jump only, no duplicate rules after repeated `ensure`, complete removal after repeated `remove`, no rules before core readiness, and no deletion of foreign chains.

- [ ] **Step 4: Implement owned chain naming and cleanup.**

Define constants for module-owned IPv4 NAT, IPv4 filter, and IPv6 filter chains. `ensure` must create or verify only those chains, delete all module-owned jumps before inserting one current jump, flush only owned chains, and verify the resulting command set. `remove` must repeatedly delete matching owned jumps until absent and then flush/delete owned chains.

- [ ] **Step 5: Implement rule generation.**

Generate rules from core readiness, network state, mode configuration, and independent 53/853 switches. Use `-w` where supported, detect unsupported lock options, and record the backend limitation instead of retrying infinitely. Do not switch airplane mode.

- [ ] **Step 6: Implement firewall health and safe failure.**

If rule verification fails, mark firewall degraded and remove any partially installed redirect. If core becomes unhealthy, remove DNS redirects before core restart. Keep independent 853 and IPv6 states visible.

- [ ] **Step 7: Run network and firewall tests.**

Run:

```sh
sh tests/network_test.sh
sh tests/firewall_test.sh
```

Expected: repeated ensure/remove is idempotent; injected command failures do not stop core-worker; foreign rules remain untouched.

---

### Task 6: Implement proxy and file adapters as isolated, disabled-by-default workers

**Files:**
- Create: `scripts/adapters/proxy-worker.sh`
- Create: `scripts/adapters/file-worker.sh`
- Create: `scripts/adapters/backup.sh`
- Create: `config/proxy-adapter.conf`
- Create: `config/file-adapter.conf`
- Create: `targets/file-ad-targets.conf`
- Create: `tests/proxy_adapter_test.sh`
- Create: `tests/file_adapter_test.sh`
- Modify: `scripts/supervisor.sh`
- Modify: `action.sh`

- [ ] **Step 1: Write proxy fixture tests.**

Test an allowed Box/Mihomo/Clash path, an unknown path, malformed YAML, a file changed after module modification, a service restart failure, and `--clean`. Assert that the original file bytes are restorable only when the post-modification hash still matches.

- [ ] **Step 2: Implement proxy path allowlisting and backup.**

Store one backup manifest per file with path, original hash, modified hash, mode, owner, and timestamp. Reject paths outside configured prefixes, symlinks unless explicitly allowed, and files above the configured size limit. Never execute a command assembled from configuration text.

- [ ] **Step 3: Write file-adapter target tests.**

Test directory and file targets, missing targets, symlinks, traversal strings, protected paths, failed backup, user-modified target, and repeated enable/disable. Assert no operation touches `/data/system/ifw`, database paths, shared preferences, or an application `files` root unless a future explicit policy enables it.

- [ ] **Step 4: Implement file target manifest and reversible actions.**

Each target must declare a stable ID, absolute path, type, risk, and restore policy. Back up metadata before changes, perform only the declared operation, record before/after hashes, and stop the worker after the first unsafe or failed target. Do not use unconditional `chattr +i`.

- [ ] **Step 5: Implement adapter control.**

Adapters start only when enabled in their config. `action.sh` must expose separate commands for core, firewall, proxy adapter, and file adapter. Adapter failures must appear independently in status output.

- [ ] **Step 6: Run adapter tests.**

Run:

```sh
sh tests/proxy_adapter_test.sh
sh tests/file_adapter_test.sh
```

Expected: adapter failure cannot stop or alter the core worker; user-modified files are never silently overwritten.

---

### Task 7: Implement diagnostics, action interface, uninstall, and rollback

**Files:**
- Create: `scripts/diagnostics.sh`
- Create: `scripts/restore.sh`
- Create: `tests/uninstall_test.sh`
- Create: `tests/diagnostics_test.sh`
- Modify: `action.sh`
- Modify: `uninstall.sh`

- [ ] **Step 1: Write uninstall fixture tests.**

Test uninstall with missing state, malformed config, duplicate owned rules, foreign rules, running and stopped workers, changed proxy files, unchanged proxy files, and failed file restoration. Assert cleanup continues and reports every unresolved item.

- [ ] **Step 2: Implement bounded component shutdown.**

Uninstall must send stop requests, wait for each PID with a deadline, then terminate only verified module-owned processes. It must never use a broad process-name kill.

- [ ] **Step 3: Implement complete firewall cleanup.**

Call firewall remove repeatedly until owned jumps and chains are absent. Treat already-absent objects as success. Record command failures but continue to proxy/file restoration and directory cleanup.

- [ ] **Step 4: Implement conditional restore.**

Restore only when current hash equals the module's recorded modified hash. If not, preserve current user content and write a restoration warning with the backup path.

- [ ] **Step 5: Implement redacted diagnostics.**

Diagnostics must report component states, ports, architecture, core PID, rule ownership and errors. It must not print passwords, serial numbers, tokens, full user DNS histories, or raw private network identifiers by default.

- [ ] **Step 6: Run uninstall and diagnostics tests.**

Run:

```sh
sh tests/uninstall_test.sh
sh tests/diagnostics_test.sh
```

Expected: repeated uninstall is safe, foreign rules remain, unresolved restores are explicit, and diagnostics contain no secret values.

---

### Task 8: Add documentation, licenses, provenance, and release metadata

**Files:**
- Create: `README.md`
- Create: `README.en.md`
- Create: `CREDITS.md`
- Create: `THIRD_PARTY_NOTICES.md`
- Create: `LICENSE`
- Create: `licenses/AdGuardHome-GPL-3.0.txt`
- Create: `licenses/anti-AD-MIT.txt`
- Create: `CHANGELOG.md`
- Create: `SECURITY.md`
- Create: `SHA256SUMS`
- Create: `sbom/SPDX.json`
- Modify: `docs/DESIGN.md`

- [ ] **Step 1: Document installation and supported environments.**

README must state Magisk/KernelSU, arm64/armv7, no Recovery installation guarantee, three DNS modes, default protection rules, random credential behavior, optional adapters, migration paths, and known effects on IPv6/DoT/DoQ/VPN.

- [ ] **Step 2: Document safe operation and rollback.**

Explain pause, resume, disable, adapter enablement, diagnostics, uninstall, conditional restoration, and what to do when a file was modified after the adapter touched it.

- [ ] **Step 3: Write attribution and third-party notices.**

CREDITS must identify `410154425/AdGuardHome_magisk` as the original reference and `liuzq2002/Adguard-Home-For-Magisk-Mod` as the continued-development reference, with pinned commits and clear distinction between behavioral inspiration and copied code. THIRD_PARTY_NOTICES must identify AdGuard Home version/source/license, rule sources, hashes, and any actually reused MIT code.

- [ ] **Step 4: Add security policy.**

SECURITY must explicitly prohibit runtime remote shell execution, describe checksum/signature verification, explain local Web UI exposure, and provide a redacted diagnostic procedure.

- [ ] **Step 5: Generate release metadata.**

The release process must generate SHA256SUMS, SPDX JSON, module manifest, asset provenance, and a list of included licenses. No credential or private path may appear in these files.

---

### Task 9: Add reproducible packaging and GitHub Actions

**Files:**
- Create: `.github/workflows/test.yml`
- Create: `.github/workflows/release.yml`
- Create: `build/package.sh`
- Create: `build/fetch-adguardhome.sh`
- Create: `build/manifest.sh`
- Create: `build/known-good-assets.json`
- Create: `tests/package_test.sh`

- [ ] **Step 1: Write package-layout tests.**

Assert the release ZIP contains root module files, exactly one selected architecture binary per package, config defaults, scripts, licenses, notices, and checksums; assert it does not contain `.git`, private project state, logs, backup data, or both architecture binaries in a device-specific package.

- [ ] **Step 2: Implement fixed-asset fetching.**

`fetch-adguardhome.sh` accepts an explicit upstream version and architecture, downloads only the configured official URL, checks the expected SHA-256 from `known-good-assets.json`, and exits before writing a final asset when verification fails. It must not execute downloaded content.

- [ ] **Step 3: Implement deterministic packaging.**

`package.sh` stages files in a clean directory, sets fixed permissions, injects the verified binary, copies license/provenance files, creates a ZIP with stable ordering and timestamps where supported, and emits a package checksum.

- [ ] **Step 4: Implement CI checks.**

`test.yml` runs shell syntax checks, fixture tests, dangerous-command scans, package-layout tests, and documentation/provenance checks on every push and pull request. `release.yml` runs only from a versioned tag, fetches pinned assets, packages arm64 and armv7 assets, generates checksums/SBOM, and uploads them as release assets.

- [ ] **Step 5: Run package tests locally.**

Run:

```sh
sh build/package.sh --arch arm64 --version <pinned-version>
sh tests/package_test.sh dist/arm64/*.zip
```

Expected: the package contains only the selected architecture, verified core binary, required notices, and no private project files.

---

### Task 10: Verification, independent review, and local delivery checkpoint

**Files:**
- Modify: `PROJECT_STATE.json` through the project-state helper only
- Modify: `PROJECT_STATUS.md` through the project-state helper only

- [ ] **Step 1: Capture a clean baseline.**

Run the full test harness before the final implementation changes and record the exit status and failure count. Existing upstream audit artifacts are read-only evidence and are not treated as implementation tests.

- [ ] **Step 2: Run complete local static verification.**

Run:

```sh
sh tests/run.sh
sh tests/static/check-shell.sh .
git diff --check
```

Scan added lines for remote shell execution, broad process kills, unsafe `rm -rf`, hardcoded credentials, unbounded command substitution, and path traversal.

- [ ] **Step 3: Run independent review.**

Dispatch a fresh reviewer with only the final diff and static scan results. The reviewer must fail closed on security concerns, logic errors, unparseable shell, unsafe cleanup, incomplete rollback, or any violation of the A+ isolation rule.

- [ ] **Step 4: Fix only reported blocking findings.**

Allow at most two fix-and-reverify cycles. Do not broaden scope or refactor unrelated files during the fix cycle.

- [ ] **Step 5: Write a verified local commit.**

After tests and independent review pass, stage only project files and commit with a `[verified]` prefix. Do not commit `PROJECT_STATE.json` manually; update it through the continuity helper before the commit if the project protocol requires the state change.

- [ ] **Step 6: Record the local artifact evidence.**

Record package paths, SHA-256 values, test commands, review result, known limitations, and the fact that Android device validation is still pending unless a real device test has been performed.

---

### Task 11: Create and publish the public GitHub repository

**Files / external targets:**
- External: `snowzlmbot/AdGuardHome-Android-Module`
- Local: `README.md`, `LICENSE`, `CREDITS.md`, `THIRD_PARTY_NOTICES.md`, release assets

- [ ] **Step 1: Verify the final local target and visibility.**

Confirm the exact owner, repository name, public visibility, default branch, current commit, and absence of secrets/private project state in the staged tree. This is a required preflight before creation.

- [ ] **Step 2: Create the public repository only after the local artifact passes.**

Create `snowzlmbot/AdGuardHome-Android-Module` with the prepared README and no unrelated template files. Do not create releases before the default branch read-back succeeds.

- [ ] **Step 3: Push the verified branch and read back remote state.**

Verify the remote URL, default branch, pushed commit SHA, visibility, and exact contents of the attribution and license files. A successful push without read-back is not completion evidence.

- [ ] **Step 4: Create the first release only after CI passes.**

Use a version tag, wait for the hosted workflow, read back the run ID and artifacts, compare uploaded asset SHA-256 values to the locally retained package bytes, and publish the release only when they match.

- [ ] **Step 5: Report the public handles.**

Final delivery must include the repository URL, commit SHA, release URL, asset names, asset SHA-256 values, CI run URL/ID, and known gaps such as pending real-device validation. Never claim device compatibility from shell tests alone.

---

## Plan self-review

- Spec coverage: architecture, Magisk/KernelSU, arm64/armv7, three DNS modes, random credentials, migration of both upstream layouts, isolated proxy/file adapters, firewall defaults, update policy, licensing, attribution, packaging, CI, and public repository publication each have dedicated tasks.
- Placeholder scan: the plan contains no unspecified implementation steps; commands, paths, interfaces, and expected outcomes are specified.
- Isolation check: only core failure is allowed to trigger firewall rule removal, because leaving a dead DNS redirect would be unsafe. Proxy, file, network, firewall, and diagnostics failures otherwise remain component-local.
- Verification boundary: local shell and fixture checks do not claim real Android, Magisk, KernelSU, iptables backend, or SELinux compatibility; those remain explicit validation gaps until exercised.
