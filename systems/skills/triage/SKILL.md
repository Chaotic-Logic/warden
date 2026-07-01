---
name: triage
description: Diagnose and run down a specific fault on a Linux host — a service that won't start or keeps crashing, a process hanging or eating resources, a box gone slow, disk-full mysteries, OOM kills, port conflicts, failed boots. Method-driven root-cause work: reproduce, read the logs, form a hypothesis, isolate, then propose the smallest fix. Diagnosis runs in loose/fast mode (the vibe-gate allows it); the moment a fix changes state it flips to structured and gets confirmed. Use when something is actually broken and needs figuring out, not a routine sweep. Triggers on "service won't start", "keeps crashing", "why is my server slow", "process hung", "out of memory / OOM", "disk full", "port already in use", "failed to start", "journalctl", "coredump", "debug this service", "troubleshoot", "root cause".
---

## triage — figure out what's actually broken

For a specific fault, not a routine once-over (that's `health-check`). Start on `recon` for connectivity and the safe-ops posture. This is the one warden skill where the vibe-gate lets you run loose: reading logs, forming and probing a hypothesis, reproducing the fault, spiking a throwaway to understand behavior — go fast. The line is state change. The second a fix edits config, restarts a service, kills a process, or installs something, it's structured: show it, say what it does and how to undo it, confirm, then run it. Don't let a diagnosis quietly become an unreviewed change on a live box.

### Method — don't skip to the fix

1. **Reproduce / observe.** Get the actual symptom and the actual error text. "It's broken" isn't a fault; an exit code, a log line, a timestamp is. Note when it started and what changed around then (a deploy, an update, a config edit, a disk filling).
2. **Read the logs before touching anything.** The answer is usually already written down (see below). Read to the real error, not the first scary line — the root cause often precedes the cascade.
3. **Form one hypothesis at a time.** State it, find the cheapest read-only check that would confirm or kill it, run that. Don't shotgun five changes at once — you'll never know which one mattered.
4. **Isolate.** Narrow it: does it fail on start or under load? For every user or one? Since a specific change? Bisect the surface.
5. **Smallest fix, then verify.** Fix the cause, not the symptom — a restart that "fixes" a crash-loop is a snooze button, not a repair. After the change, confirm the fault is actually gone and nothing else broke.

### Where to look

**Service won't start / keeps crashing**
- `systemctl status <svc>` — state, last exit code/signal, the recent journal tail.
- `journalctl -u <svc> -b --no-pager` — this boot's logs for the unit; add `-e` to jump to the end, `-f` to follow a live restart.
- Exit code / signal tells you a lot: `SIGSEGV` (crash), `SIGKILL` + OOM in `dmesg` (killer took it), non-zero exit = it failed its own checks — read *its* log, not just systemd's.
- Crash-loop: `systemctl` will show `Restart=` throttling. Look at *why* each start dies, don't just bump the restart limit.
- Coredumps: `coredumpctl list`, `coredumpctl info <pid/exe>`, `coredumpctl gdb` for a backtrace if debuginfo's around.
- Dependency/ordering: `systemctl list-dependencies <svc>`, and check `After=`/`Requires=` — a service starting before its DB or its mount is a classic.
- Config: validate before restarting into another failure. Most daemons have a check mode (`nginx -t`, `sshd -t`, `named-checkconf`, `visudo -c`). Use it.

**Out of memory**
- `journalctl -k -b | grep -i "killed process"` / `dmesg | grep -i oom` — who got killed and when.
- `free -h`, `/proc/meminfo` (MemAvailable), per-process `ps aux --sort=-%mem`. A leak climbs over time; a spike is workload.
- cgroup memory limits (`systemctl show <svc> -p MemoryMax`, or the container's limit) — the box has RAM but the unit was capped.

**Box is slow / high load**
- `uptime` load vs. core count (`nproc`). Load high but CPU idle = usually I/O wait or lock contention.
- `top -bn1`, `vmstat 1 5` (watch `wa` for I/O wait, `si/so` for swap thrash), `iostat -x 1 3` (device `%util`, await) if sysstat's there.
- `ss -s` for socket pileups; a service leaking connections looks like a slow box.

**Disk full / can't write**
- `df -hT` for space, `df -iT` for inodes (full inodes = "no space" with space free).
- Biggest offenders: `du -xhd1 /var 2>/dev/null | sort -h | tail`. Runaway logs, an unrotated journal (`journalctl --disk-usage`, `journalctl --vacuum-size=`), a core-dump pile.
- Deleted-but-held files (space not freed because a process still holds the fd): `lsof +L1` — the fix is restarting the holder, not `rm`.

**Port already in use / can't bind**
- `ss -tulpn | grep :<port>` — who owns it. Stale process, a second instance, or a genuine conflict.

**Process hung**
- `cat /proc/<pid>/status` (State: `D` = uninterruptible I/O sleep, often a stuck mount/disk), `cat /proc/<pid>/wchan` for where it's blocked.
- `lsof -p <pid>` for what it has open; `strace -p <pid>` briefly to see what syscall it's spinning or blocked on (attach read-only, detach fast on a production process).

**Won't boot / degraded boot**
- `systemctl --failed`, `systemctl is-system-running`.
- `journalctl -b -p err` for this boot, `journalctl -b -1` for the previous one if it rebooted on you.
- `systemd-analyze blame` / `critical-chain` if boot is slow rather than failed.

### Closing out

When it's fixed: say what the root cause was, what change fixed it (the exact command/edit, applied only after confirmation), and how to tell it's staying fixed. If the fix was a workaround and the real cause is deeper, name that plainly — don't dress a band-aid as a cure. If the fault exposed something worth hardening or a health finding worth tracking, hand it to `security-audit` or `health-check` rather than letting it drop.
