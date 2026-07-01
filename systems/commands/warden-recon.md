---
description: "Reach a host and take stock: connectivity, inventory, and OS version-currency"
argument-hint: "[host]"
---

Run the warden **recon** skill against the target: `$ARGUMENTS`

- A named host is the target; it's likely remote, so confirm scope before connecting — name the box and the read-only sweep, and wait for a go. No host given: ask which box, or run against the local machine if that's clearly what's meant (a local read-only check just runs).
- recon reaches the box (public-key SSH only), builds the host profile (distro, kernel, hardware, package manager), and runs the version-currency check the moment the OS is identified — warning up front if the release is end-of-life.
- Read-only throughout. Hand off to health-check, security-audit, or triage as the follow-up warrants.
