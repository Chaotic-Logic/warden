---
name: health-check
description: Whole-box health check for a Linux host — the "let me know the health of my server" runbook. Connects (via recon), then walks a fixed checklist: distro and hardware specs, hardware health where it applies (SMART/NVMe, sensors, RAID, ECC), memory and swap pressure, disk and inode usage, running processes and listening sockets, failed units and OOM/kernel events. Produces a Device Health report and hands the security half to security-audit and any live fault to triage. Use whenever the user asks how their server/box/host is doing, wants a health report, a status once-over, or a "check my server" sweep. This is OS and hardware health of a host, not application/service uptime monitoring or a codebase's health. Triggers on "how is my server", "health of my server", "check my server/box", "server health report", "is this host ok", "device health". Not for app-level metrics, endpoint monitoring, or code health.
---

## health-check — the whole-box once-over

Entry point for "let me know the health of my server." Start on the base skill `recon`: get connectivity, carry the safe-ops posture (read-only, confirm before any change, redact secrets), and build the host profile. Everything below is inspection — none of it changes state on a live box.

The output splits into two reports, the way the user framed it:
- **Device Health** — this skill owns it (hardware, capacity, processes, kernel/service state).
- **Security Report** — hand off to `security-audit`; don't duplicate its checks here.

If the sweep turns up something actively broken (a unit crash-looping, a disk at 100%, OOM kills in the log), stop the survey and route that thread to `triage` for real root-cause instead of just noting it.

### The checklist

Run it in order. First get the profile from `recon` (distro, kernel, arch, CPU, memory, disks, virt/container). `systemd-detect-virt` decides how much of the hardware section applies — SMART/sensors/RAID are meaningless inside most VMs and containers; say so and skip rather than inventing numbers.

**1. Distro + specs** — from `recon`: `os-release`, `uname -srm`, `lscpu`, `free -h`, `lsblk`. This is the header of the report. Run the version-currency check `recon` sets up: installed vs what the box's repos offer, and running kernel vs newest installed. Behind-on-updates and a pending reboot into a newer kernel are Device Health findings; an out-of-support release is the headline, not a footnote — warn the user up front (top of the report, not buried in a table), then hand it to `security-audit` for the rebuild call (regenerate, don't resurrect). Establish "current" from the box and an authoritative lifecycle source, never from memory.

**2. Hardware health (bare metal / passthrough only)**
- Disks (SMART): `smartctl -H /dev/sdX` for the one-line verdict, `smartctl -a /dev/sdX` for the detail. NVMe: `smartctl -a /dev/nvmeX` or `nvme smart-log /dev/nvmeX`. Watch reallocated/pending sectors, media errors, wear level, and the overall PASSED/FAILED. Needs `smartmontools`; note if it's absent rather than skipping silently.
- Temps / fans / voltages: `sensors` (lm_sensors). Flag anything near its high/crit threshold.
- RAID: software — `cat /proc/mdstat`, `mdadm --detail /dev/mdX`. Hardware — vendor tool (`storcli`/`perccli`, `MegaCli`). A degraded array is a Device Health finding, not a footnote.
- ECC memory: `ras-mc-ctl --summary` / `edac-util` if EDAC is present. Correctable errors climbing = a DIMM on the way out.

**3. Memory + swap pressure** — `free -h`, `/proc/meminfo` (MemAvailable is the honest number, not "free"). Heavy swap-in/out or near-zero available is a finding. `vmstat 1 3` for a quick read on si/so.

**4. Disk + inode capacity** — `df -hT` for space, `df -iT` for inodes (a full inode table looks like a mystery "disk full" with space to spare). Flag anything over ~85%. Check the busy filesystems: `/`, `/var`, `/var/log`, and wherever the workload writes.

**5. Running processes** — `ps aux --sort=-%cpu | head`, then `--sort=-%mem`. `top -bn1` / `uptime` for load average against core count (from `lscpu`). Note the top consumers and anything obviously wrong (a runaway, a zombie pile, a process eating all of RAM).

**6. Listening sockets** — `ss -tulpn`. What's bound to `0.0.0.0`/`::` vs localhost. This is the seam into the Security Report — anything unexpectedly public gets flagged and carried into `security-audit`.

**7. Services + kernel events**
- Failed units: `systemctl --failed`, `systemctl is-system-running`.
- OOM kills and hardware/filesystem errors: `journalctl -k -p err -b --no-pager`, `dmesg -l err,crit,alert,emerg`. OOM kills, I/O errors, filesystem remounts read-only, MCE — all Device Health findings.
- Pending reboot (kernel patched but not booted into): compare `uname -r` against the newest installed kernel from the package manager, or check `/var/run/reboot-required` on debian-family.

**8. Containers (only if `recon` found a runtime)**
- What's running and what died: `docker ps -a` — note anything `Exited (non-zero)` or stuck restarting. Restart count per container: `docker inspect -f '{{.Name}} {{.RestartConfig.Name}} restarts={{.RestartCount}}' $(docker ps -aq)` — a climbing count is a crash-loop, same as a failed unit; route it to `triage`.
- Healthchecks: containers with a `HEALTHCHECK` reporting `unhealthy` are a finding even while "up". `docker ps --filter health=unhealthy`.
- Resource use: `docker stats --no-stream` — a container pinning CPU or against its memory limit.
- Docker's own disk footprint: `docker system df` — reclaimable image/volume/build-cache bloat is a common "why is `/var` full" answer. Ties back to the disk-capacity check.
- Image vulns and daemon hardening are the Security Report's job, not here — hand off to `security-audit`.

### The report

Two sections, plain and skimmable. Lead with the verdict, not the raw dump.

- **Device Health** — Healthy / Degraded / At-risk up top, then findings grouped: hardware, capacity, load, services. Each finding says what's wrong, where it is, and what it means. Cite the number (temp, sector count, % full), not "looks high."
- **Security Report** — produced by `security-audit`; summarize its verdict here and link the detail rather than re-running its checks.

Redact anything sensitive that showed up in output (tokens in a process list, hostnames the user wants kept private) per the safe-ops rules in `recon`. If a check couldn't run (tool missing, no privilege, VM with no SMART), say so — a skipped check is not a passing check.
