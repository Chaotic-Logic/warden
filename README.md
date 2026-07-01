# Warden

> *"The walls don't keep themselves. Someone has to walk them in the dark, put a hand on the stone, and know which crack is settling and which one's about to let the cold in."*

A warden keeps the watch over a holding — not the counsel that rules it or the trades that build it, but the quieter work of knowing every machine's health, keeping its defenses sound, and finding the rot before it spreads. This one does that for Linux hosts: reach the box, take its measure, report what ails it, harden what's soft, and run down what's broken.

## The watch

- **`recon`** — the groundwork. Reach the host, confirm it's the right one, and take stock: distro, kernel, hardware, what package manager it speaks. Carries the posture every other skill inherits — read before you touch, confirm before you change anything, never run what you can't undo.
- **`health-check`** — the rounds. The whole-box once-over behind "let me know the health of my server": specs, hardware health where it applies, memory and disk pressure, running processes, failed services and kernel complaints. Splits into a Device Health report and hands the security half to the audit.
- **`security-audit`** — the walls. Hardening scan, attack surface, account and auth hygiene, filesystem risk, and installed packages checked against known CVEs with the distro's own tooling. Reads only; every fix is proposed and waits for a yes.
- **`triage`** — the alarm. When something's actually broken — a service crash-looping, a box gone slow, an OOM kill, a disk that filled — the method work of reproducing it, reading the logs, and finding the real cause instead of the symptom.

Nothing here changes a machine's state on its own. Inspection is the default; anything that writes, installs, restarts, or kills is shown and confirmed first.

## Raising the watch

See the Vizier's `bootstrap/BOOTSTRAP.md`. Add the marketplace and enable the plugin; the skills are summoned when the work calls for a host.

## Standing alone

When the Vizier holds court beside it, the warden defers — the counsel keeps the standing law, and the warden does not repeat it. Left on its own (raised on a box without the Vizier), the warden carries enough of that law — the vibe gate, the bias toward the smallest change — to keep its own house in order. The safe-ops posture rides in the skills themselves, so it stands whether the Vizier is there or not. `WARDEN_DISABLE=1` stills the fallback for a session.

---
*Shareable. Set it to watch wherever a machine needs keeping.*
