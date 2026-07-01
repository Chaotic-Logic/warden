---
name: recon
description: Base skill for reaching a Linux host and taking stock of it before any system-engineering or security work. Covers getting connectivity (SSH, jump/bastion hops, confirming the target), the safe-ops posture every warden skill inherits (read-only by default, confirm before changing state, least privilege, redact secrets, never destructive), and building a host profile — distro, kernel, arch, CPU, memory, disks, virt/container, package manager — then, once the OS is identified, a version-currency check (installed vs available, running vs newest kernel, and whether the release is still supported). Use as the shared groundwork the health-check, security-audit, and triage skills build on; invoke directly when the task is "get me onto the box and tell me what it is." Triggers on "connect to my server", "ssh into", "what distro/kernel/hardware is this box", "take stock of this host", "inventory the machine", or any warden work that needs a live host first.
---

## recon — reach the box, take stock, touch nothing you didn't have to

Groundwork for every warden skill. `health-check`, `security-audit`, and `triage` all start here: get onto the host, figure out exactly what it is, and carry the safe-ops posture below into whatever comes next. Those three lean on this for the parts that don't change; they add their own work on top.

### Safe-ops posture — this governs every command warden runs

Running commands on someone's machine is an outward-facing action with real blast radius. Every warden skill inherits these; they are not optional.

- **Confirm the target before the first command.** Which host, which user, whose box, and do we have authorization to touch it. Never assume `localhost` when the ask names a server; never guess a hostname. If the box isn't yours, get explicit go-ahead first, and log that you're operating on it.
- **Public-key SSH only, no exceptions.** warden reaches a host with key auth and nothing else. If a box offers only password or keyboard-interactive auth, it stops rather than connect (fail closed). The exact flags are in Getting connectivity below.
- **Read before you touch. Read-only is the default mode.** Inventory, health, and audit work is all inspection — it must not change state. Anything that writes, installs, restarts, edits config, or kills a process is a separate step that gets shown and confirmed first (see the vibe-gate: diagnosis runs loose, changes run structured).
- **Least privilege.** Prefer an unprivileged account. Reach for `sudo` only for the specific commands that need it (SMART reads, some log paths, firewall state), and say why. Don't hand yourself root for a job a normal user can do.
- **Never destructive, never noisy.** No fork bombs, no `dd` onto a live disk, no stress tools that starve a production box, no aggressive scans against hosts you weren't asked to scan. Health/audit reads are cheap and safe; keep them that way.
- **Redact on the way out.** Reports and pasted output never carry passwords, private keys, tokens, or full credentials. Mask them. Log security-relevant findings with enough context to act, never the secret itself.
- **Fail closed.** Can't verify authorization, can't confirm the target, command needs a privilege you weren't granted -> stop and ask. Don't fall through to "close enough."

### Getting connectivity

- SSH is the path, and it's **public-key auth only**. Disable the fallbacks explicitly so ssh can never drop to a password prompt: `ssh -o PreferredAuthentications=publickey -o PasswordAuthentication=no -o KbdInteractiveAuthentication=no user@host`. A passphrase on the *local* key is fine (the agent unlocks it); password or keyboard-interactive auth *to the server* is forbidden. No key present, or the key's rejected -> stop, don't fall back to a password, and never ask for one in chat or put it on a command line or in a file. Then hand the user the setup runbook below instead of leaving them stuck. The strong form of key auth is a hardware-backed key (`ed25519-sk`/`ecdsa-sk`, a FIDO2 token like a YubiKey): the private half never leaves the silicon, so a copied disk image gets an attacker nothing. Recommend it wherever the user has a token.

**No key yet? Walk the user through it.** warden won't do the one-time password login that seeds a key (that would break the key-only rule) — that step is the user's; warden takes over the moment key auth works. Give them this:

1. **Make a key** (skip if `ls ~/.ssh/id_*` already shows one): `ssh-keygen -t ed25519 -a 100 -C "you@purpose"`. ed25519 over RSA; set a passphrase so a stolen key file is useless on its own. With a hardware token, `ssh-keygen -t ed25519-sk` binds the key to the device so the secret never leaves it — the strong default when they have one.
2. **Put the public key on the server** — `~/.ssh/authorized_keys` on the target, one of:
   - Still have a password login of your own? `ssh-copy-id -i ~/.ssh/id_ed25519.pub user@host` (this is you authenticating with the password once, not warden).
   - Cloud/VM: paste the contents of `id_ed25519.pub` into the provider's SSH-key field or cloud-init; it lands in `authorized_keys` on boot.
   - Console/existing access: append the `.pub` line yourself, then fix perms — `chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys`, and the file must be owned by that user.
3. **Verify key login works before anything else:** `ssh -o PreferredAuthentications=publickey user@host` should get you in with no password prompt. Now warden can connect.
4. **Then close the door** (recommend it; it's a state change, so it's confirmed, not automatic). Escape pod before engines: before you kill password auth, make sure there's an out-of-band way back that doesn't depend on the thing you're changing — a mesh/VPN interface (Tailscale, WireGuard) or console access — plus a break-glass account that isn't tied to your token or the mesh. Then keep your working session open, set `PasswordAuthentication no` and `KbdInteractiveAuthentication no` in a `/etc/ssh/sshd_config.d/` drop-in (sshd is first-match-wins and reads the drop-ins alphabetically, so name it to sort ahead of anything that already sets those keys, and confirm the result with `sudo sshd -T`, not the file you wrote), `sudo sshd -t` to check syntax, `sudo systemctl reload ssh`, and confirm a fresh key login in a *second* terminal before you let go of the first. Never lock yourself out to look secure.

**No access at all, and none to be had? Manual mode.** Air-gapped box, a host that isn't warden's to log into, or the user genuinely can't set up a key right now — warden still works, it just doesn't hold the keyboard. It hands over the commands and reads the output the user pastes back.

- Give **read-only**, copy-pasteable commands, labeled so it's obvious which output answers which check. The safe-ops posture still holds: nothing that changes state goes in the list without being called out and confirmed, even though the user is the one typing it.
- Batch them into as few pastes as makes sense; a human copy-pasting doesn't want forty round-trips. One block per section (profile, health, audit) is usually the right size.
- Flag which commands need `sudo`, and why.
- If a command can spill secrets — a config dump, an env list, a process table with tokens in the args — say so before handing it over, scope it tighter, or tell the user what to redact first. Output pasted into chat has already left their box; warden can redact it in the report, but it can't un-see it.
- Parse what comes back and produce the same Device Health / Security Report. A check the user couldn't or didn't run is reported as skipped, not passed.
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

### Version currency — check it the moment the OS is identified

Identifying the OS is the trigger, not the finish line: right away, establish how current the box is against what's actually current for its family. Two sources feed that, and neither is warden's memory — the model's idea of "the latest release" is frozen at its training cutoff and drifts, so treat any version number it recalls as *verify this*, not fact.

- **What the box's own repos offer** (authoritative for "am I behind on my release"): refresh the package metadata and list what's upgradable. `sudo apt update && apt list --upgradable`; `dnf check-update`; `zypper ref && zypper lu`; on Arch use `checkupdates` (from `pacman-contrib`, it syncs to a temp db) rather than `pacman -Sy`, which arms a partial-upgrade trap. These are metadata refreshes — safe reads, they install nothing.
- **Kernel**: running vs newest installed — `uname -r` against the newest kernel package (`rpm -q kernel`, `dpkg -l 'linux-image-*'`, `pacman -Q linux`). Running older than what's installed is a pending-reboot finding.
- **Is the release itself still supported** (the EOL question): check `/etc/os-release` against an authoritative lifecycle source, not memory. `endoflife.date` has an API — `curl -s https://endoflife.date/api/<product>.json` (ubuntu, debian, rhel, almalinux, rockylinux, fedora, opensuse, sles, amazon-linux, and `linux` for kernel LTS lines) — or the vendor's own lifecycle page. Where warden has web access, verify there; where it doesn't, report the release as looking EOL/behind *pending verification* and name the source to check.

Hand the numbers to `health-check` (pending updates, kernel reboot) and `security-audit` (EOL -> the rebuild call, CVE exposure). Flag confidence on anything not pulled live from the box or an authoritative source.

**If the release is EOL, warn immediately.** Don't hold it for the final report. An out-of-support OS is piling up unpatched CVEs with no fix ever coming, so the moment the currency check shows it — or shows it *likely*, pending verification when there's no live source to confirm — say so plainly and up front. Lead with the warning, name the source that confirms it (`endoflife.date` / the vendor page), state your confidence, and carry the regenerate-don't-resurrect rebuild call from `security-audit`. Verified EOL is a stop-and-flag, not a quiet line item in a table. Stop-and-flag means warn loudly, not down tools: the rebuild is the recommendation, and warden still goes on to secure the box as best it can — that harm-reduction pass (surface reduction, extended-support channels, MAC, firewall) is `security-audit`'s job.

### Handoff

- Whole-box health, "is my server ok" -> `health-check` (runs this profile, then Device Health + the Security Report).
- Just the security posture, hardening, CVEs -> `security-audit`.
- Something specific is broken/crashing/slow -> `triage`.
