# Warden

> *"The walls don't keep themselves. Someone walks them in the dark, puts a hand on the stone, and knows which crack is settling and which one's about to let the cold in."*

A warden keeps the watch over a holding. Not the counsel that rules it (that's the Vizier) or the trades that build it (that's the Steading), but the quieter work of knowing every machine's health, keeping its defenses sound, and finding the rot before it spreads. This plugin does that for Linux hosts: reach the box, take its measure, report what ails it, harden what's soft, run down what's broken.

It's four skills that Claude Code pulls in on its own when the work calls for a host. You don't invoke them by name; you describe the job.

## What it holds

| Skill | The work | Ask it something like |
|-------|----------|-----------------------|
| **recon** | Reach the host, confirm it's the right one, take stock: distro, kernel, hardware, package manager. The groundwork the other three stand on. | *"ssh into web-01 and tell me what it is"* |
| **health-check** | The whole-box rounds behind "how's my server." Specs, hardware health (SMART, sensors, RAID, ECC), memory and disk pressure, processes, failed services, kernel complaints, container health. Splits into a Device Health report and hands the security half to the audit. | *"let me know the health of my server"* |
| **security-audit** | The walls. Hardening scan (Lynis, OpenSCAP), attack surface, account and auth hygiene, filesystem risk, installed packages checked against known CVEs, and Docker/container scanning when a runtime is present. | *"run a security scan on this box"* · *"any vulnerable packages?"* |
| **triage** | The alarm. When something's actually broken: a service crash-looping, a box gone slow, an OOM kill, a disk that filled. The method work of reproducing it, reading the logs, finding the real cause instead of the symptom. | *"nginx won't start on prod-db"* · *"why is this box slow?"* |

## The one rule that matters: it reads before it touches

Running commands on a machine is not free, and warden treats it that way. Every skill inherits one posture, and it isn't optional:

- **Read-only is the default.** Inventory, health, and audit work is all inspection. It does not change state.
- **Anything that changes a box waits for a yes.** Writing a file, installing a package, restarting a service, killing a process, applying a fix: each is shown to you first, with what it does and how to undo it, and runs only on confirmation.
- **Never destructive, never noisy.** No stress tools on a live box, no aggressive scans against hosts you didn't name, nothing that can't be walked back.
- **Least privilege.** Prefer an unprivileged account; reach for `sudo` only on the specific reads that need it, and say why.
- **Secrets get redacted.** Reports never carry passwords, keys, or tokens. A finding says one exists and where, never its value.
- **It fails closed.** Can't confirm the target, can't verify authorization, needs a privilege it wasn't granted: it stops and asks.

Diagnosis in **triage** is the one place it moves fast and loose (reading logs, chasing a hypothesis). The moment a fix would change the box, it slows back down to the rule above.

## What it needs

- **SSH to the target by public key** (or run it against the local box). Key auth only: warden disables password fallback on the connection, and if a box offers only password auth it stops rather than connect. A passphrase on your local key is fine; your agent unlocks it. It never asks for a password in chat or puts one on a command line. No key set up yet? It walks you through generating one and getting it onto the server (you do the one-time seeding; warden takes over once key login works).
- **The host's own tooling, where it's there.** warden leans on standard packages for the deep checks: `smartmontools` and `lm_sensors` for hardware, `lynis` / `openscap` for hardening, `debsecan` / `arch-audit` / `dnf updateinfo` for CVEs, `trivy` or `grype` and `docker-bench-security` for containers. None are required. When one's missing, warden says so and works with what's there; a check it couldn't run is reported as skipped, never counted as a pass.

## Seating the watch

Part of the same setup as the Vizier and the Steading; see the Vizier's `bootstrap/BOOTSTRAP.md`. On its own:

```
claude plugin marketplace add /path/to/warden      # or the git URL
claude plugin install warden@warden
```

Or merge `enabledPlugins` + `extraKnownMarketplaces` into `~/.claude/settings.json` alongside the others. The skills load from the next session; they're summoned when a task needs a host.

## Standing alone

When the Vizier holds court beside it, the warden defers: the counsel keeps the standing law (the voice, the security and quality rules, the vibe gate), and the warden doesn't repeat it. Raised on a box without the Vizier, warden carries enough of that law itself (the vibe gate, the bias toward the smallest change) to keep its own house in order. That fallback rides a SessionStart hook, guarded so it no-ops the moment the Vizier is present.

The safe-ops posture above lives in the skills themselves, not the hook, so it stands whether the Vizier is there or not.

`WARDEN_DISABLE=1` stills the standalone fallback for a shell or session.

---
*Shareable. Set it to watch wherever a machine needs keeping.*
