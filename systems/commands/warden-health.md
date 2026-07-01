---
description: "Run warden's whole-box health check on a host (Device Health + Security Report)"
argument-hint: "[host]"
---

Run the warden **health-check** skill against the target: `$ARGUMENTS`

- A named host is the target; it's likely remote, so confirm scope before connecting — name the box and the read-only sweep, and wait for a go. No host given: ask which box, or run against the local machine if that's clearly meant.
- health-check starts on `recon` (connect, inventory, OS version-currency), walks the Device Health checklist (hardware, capacity, load, services, containers), warns up front if the release is end-of-life, and hands the security half to `security-audit`.
- Read-only throughout; anything that would change the box waits for confirmation.
