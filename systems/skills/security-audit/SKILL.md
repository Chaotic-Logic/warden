---
name: security-audit
description: Security posture and hardening audit for a Linux host — the Security Report half of a warden sweep. Covers a hardening scan (Lynis, OpenSCAP/oscap against a CIS or STIG profile), attack-surface review (listening ports, firewall state, exposed services), account and auth hygiene (SSH config, sudoers, failed logins, stale/empty-password accounts), filesystem risk (SUID/SGID, world-writable, package integrity), rootkit checks, and matching installed packages against known CVEs using the distro's own security tooling. Read-only and non-destructive; remediation is proposed, shown, and confirmed separately. Use for "run a security scan", "audit my server's security", "check for CVEs / vulnerable packages", "is this box hardened", "security report", "check hardening", or the security half of a health check. Triggers on "security scan", "security audit", "harden", "hardening", "CVE", "vulnerable packages", "open ports audit", "is my server secure", "compliance scan", "lynis", "openscap".
---

## security-audit — the Security Report

The hardening + exposure half of a warden sweep. Start on `recon` for connectivity, the safe-ops posture, and the host profile — the distro `ID`/`VERSION_ID` from there decides which CVE and audit tooling applies. Everything in this skill is read-only. Finding a hole is not permission to patch it: remediation gets written up, shown, and confirmed as its own structured step (vibe-gate), never run silently on a live box.

Depth lives in `references/`:
- `references/cve-by-distro.md` — the exact CVE/patch-status commands per package manager (apt/debsecan, dnf updateinfo, arch-audit, zypper), plus scanner options (Grype/Trivy) and integrity checks.
- `references/hardening-checklist.md` — the config-review checklist (SSH, sudo/PAM, kernel sysctls, firewall, file perms, accounts) with the command for each line.
- `references/docker-security.md` — for hosts running Docker/a container runtime: image CVE scanning, daemon and CIS-benchmark hardening, and the runtime red flags (exposed socket, tcp daemon, `--privileged`, host namespaces).
- `references/selinux.md` — mandatory access control: checking it's on, recommending `enforcing` SELinux where the distro ships it (and AppArmor elsewhere), the safe enable path, and the basics of using it.

Don't re-derive those inline; read the reference and work from it.

### What the audit covers

**1. Automated hardening scan** — the fast broad pass.
- `lynis audit system` — host-level hardening audit, produces a hardening index and specific warnings/suggestions. Read the report at `/var/log/lynis-report.dat`; the warnings are the actionable part.
- OpenSCAP where compliance matters: `oscap xccdf eval --profile <cis|stig> --results ... /usr/share/xml/scap/ssg/content/ssg-<distro>-ds.xml` against the SCAP Security Guide content. Gives pass/fail per rule tied to a benchmark.
- Treat these as input, not gospel — they flag; you judge which findings actually matter for this box's role.

**2. Attack surface**
- Listening sockets: `ss -tulpn` — every `0.0.0.0`/`::` bind is a question ("does this need to face the network?"). Cross-reference the process.
- Firewall state: whichever backend is live — `nft list ruleset`, `iptables -S`, `ufw status verbose`, `firewall-cmd --list-all`. Default-deny inbound or not? Is anything wide open that shouldn't be?
- External view (only against hosts you're authorized to scan, and only when asked): a light `nmap` from outside shows what the world actually sees vs. what the host thinks it exposes. No aggressive/intrusive scan flags on production.
- `fail2ban-client status` and per-jail status if it's running.

**3. Accounts + auth** — see the checklist reference for commands.
- SSH: root login, password auth, protocol/cipher config in `sshd_config`.
- sudo/PAM: who has sudo, `NOPASSWD` grants, password policy.
- Accounts: UID-0 accounts other than root, empty-password accounts, stale/never-logged-in accounts, failed-login patterns (`lastb`, `journalctl -u ssh`), `/etc/shadow` sanity.

**4. Filesystem risk**
- SUID/SGID: `find / -xdev -perm -4000 -o -perm -2000 -type f 2>/dev/null` — enumerate and eyeball for anything nonstandard.
- World-writable files/dirs, especially without the sticky bit: `find / -xdev -perm -0002 -type f 2>/dev/null`.
- Package integrity: `rpm -Va` (rpm distros) / `debsums -c` (debian) — files that drift from what the package shipped. See the reference.

**5. Mandatory access control** — is SELinux/AppArmor actually guarding this box. On RHEL-family (SELinux-native): `getenforce` / `sestatus` — `Enforcing` is the goal; `Permissive` or `Disabled` is a finding, and warden recommends turning it on and offers to walk the user through it. On Debian/Ubuntu/SUSE (AppArmor): `aa-status` — profiles loaded and enforcing. A box with no MAC active at all is the finding regardless of which system it should run. Don't recommend SELinux on an AppArmor distro; that's a migration, not a hardening step. Enabling it is a state change, so it's proposed and taught, never flipped automatically. Depth and the safe enable path in `references/selinux.md`.

**6. CVEs vs installed packages** — the real "am I running something known-bad" check. Distro-specific; the commands are in `references/cve-by-distro.md`. In short: use the distro's own security-update feed first (`dnf updateinfo list security`, `apt` + `debsecan`, `arch-audit`, `zypper list-patches`), because it maps CVEs to the exact patched package version for your release. Reach for Grype/Trivy on top when you want a scanner's view or you're auditing container images.

**7. Containers (only if `recon` found Docker/a runtime)** — a Docker host has a whole second attack surface on top of the OS. Full depth in `references/docker-security.md`; the shape:
- Image CVEs: scan every image in play, not just the OS packages — `trivy image <img>` / `grype <img>` / `docker scout cves <img>`. Container images carry their own vulnerable OS and app-dependency layers.
- Daemon + host config: `docker-bench-security` runs the CIS Docker Benchmark. Check `daemon.json`, socket ownership, whether rootless/userns-remap is in play.
- The high-severity runtime flags, worth checking first because they're host-takeover class: the daemon socket exposed over tcp (`2375` unencrypted) or bind-mounted into a container, and any `--privileged` container. Then host namespaces (`--pid=host`, `--net=host`), added capabilities, and containers running as root.

### The report

Lead with a verdict — Hardened / Needs work / Exposed — then findings ranked by real risk, not by scanner severity alone. Each finding: what it is, where, why it matters on this box, and the proposed fix (as a proposal — not applied). Redact secrets per `recon`'s safe-ops rules; log the audit was run and what it found, never the credentials it saw. A check that couldn't run (tool missing, no privilege) is called out, not counted as a pass — failing closed applies to reporting too.
