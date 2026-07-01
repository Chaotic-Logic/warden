---
name: recon
description: Base skill for reaching a Linux host and taking stock of it before any system-engineering or security work. Covers getting connectivity (SSH, jump/bastion hops, confirming the target), the safe-ops posture every warden skill inherits (read-only by default, confirm before changing state, least privilege, redact secrets, never destructive), and building a host profile — distro, kernel, arch, CPU, memory, disks, virt/container, package manager. Use as the shared groundwork the health-check, security-audit, and triage skills build on; invoke directly when the task is "get me onto the box and tell me what it is." Triggers on "connect to my server", "ssh into", "what distro/kernel/hardware is this box", "take stock of this host", "inventory the machine", or any warden work that needs a live host first.
---

## recon — reach the box, take stock, touch nothing you didn't have to

Groundwork for every warden skill. `health-check`, `security-audit`, and `triage` all start here: get onto the host, figure out exactly what it is, and carry the safe-ops posture below into whatever comes next. Those three lean on this for the parts that don't change; they add their own work on top.

### Safe-ops posture — this governs every command warden runs

Running commands on someone's machine is an outward-facing action with real blast radius. Every warden skill inherits these; they are not optional.

- **Confirm the target before the first command.** Which host, which user, whose box, and do we have authorization to touch it. Never assume `localhost` when the ask names a server; never guess a hostname. If the box isn't yours, get explicit go-ahead first, and log that you're operating on it.
- **Read before you touch. Read-only is the default mode.** Inventory, health, and audit work is all inspection — it must not change state. Anything that writes, installs, restarts, edits config, or kills a process is a separate step that gets shown and confirmed first (see the vibe-gate: diagnosis runs loose, changes run structured).
- **Least privilege.** Prefer an unprivileged account. Reach for `sudo` only for the specific commands that need it (SMART reads, some log paths, firewall state), and say why. Don't hand yourself root for a job a normal user can do.
- **Never destructive, never noisy.** No fork bombs, no `dd` onto a live disk, no stress tools that starve a production box, no aggressive scans against hosts you weren't asked to scan. Health/audit reads are cheap and safe; keep them that way.
- **Redact on the way out.** Reports and pasted output never carry passwords, private keys, tokens, or full credentials. Mask them. Log security-relevant findings with enough context to act, never the secret itself.
- **Fail closed.** Can't verify authorization, can't confirm the target, command needs a privilege you weren't granted -> stop and ask. Don't fall through to "close enough."

### Getting connectivity

- SSH is the path. Prefer key auth; if a password or passphrase is needed, let the user's agent/ssh handle it — don't ask for it in chat and never put it in a command line or a file.
- Multi-hop: if the target sits behind a bastion, use `ssh -J bastion user@target` (ProxyJump) rather than agent-forwarding into an untrusted middle box.
- Confirm you're on the right machine before anything else: `hostname -f` and check it against what the user named. Wrong-box commands are how outages start.
- Run non-interactive, read-only commands. Batch the inventory into one round-trip where you can; a live box doesn't need forty separate SSH sessions.
- Local host (the ask is about this machine): same commands, no SSH. Still confirm it's the box they mean.

### Host profile — build this first, the other skills consume it

One compact pass. Everything here is read-only and safe on a live box.

| What | Command | Note |
|------|---------|------|
| Hostname / FQDN | `hostname -f`, `hostnamectl` | confirm against the named target |
| Distro + version | `cat /etc/os-release` | the `ID` and `VERSION_ID` drive which package/CVE tooling to use later |
| Kernel + arch | `uname -srm`, `uname -a` | kernel version matters for CVE relevance |
| Uptime / boot | `uptime`, `who -b` | long uptime = pending-reboot kernel patches |
| Virt / container | `systemd-detect-virt`, `/proc/1/cgroup` | bare metal vs VM vs container changes what "hardware health" even means |
| Container runtime | `command -v docker podman nerdctl`, `systemctl is-active docker`, `docker info 2>/dev/null` | if Docker (or podman) is running, health-check and security-audit branch into container checks |
| CPU | `lscpu` | cores, model, flags (virt, mitigations) |
| Memory | `free -h`, `/proc/meminfo` | total, available, swap |
| Disks / layout | `lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE`, `df -hT` | physical devices feed the SMART checks in health-check |
| Package manager | infer from distro `ID` | `apt` (debian/ubuntu), `dnf`/`yum` (rhel/fedora/rocky/alma), `pacman` (arch), `zypper` (suse) |
| Init / services | `systemctl --version`, `systemctl is-system-running` | most of this is systemd; note if it isn't |

Record `ID`/`VERSION_ID` and the package manager explicitly — `security-audit` and `health-check` both branch on them, and container vs bare-metal decides whether SMART/sensors/RAID checks even apply. Note whether a container runtime (docker/podman) is up too; that turns on the container health and image-scan checks in the other two skills.

### Handoff

- Whole-box health, "is my server ok" -> `health-check` (runs this profile, then Device Health + the Security Report).
- Just the security posture, hardening, CVEs -> `security-audit`.
- Something specific is broken/crashing/slow -> `triage`.
