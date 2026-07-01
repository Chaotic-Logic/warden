---
description: "Run warden's security + hardening audit on a host (the Security Report)"
argument-hint: "[host]"
---

Run the warden **security-audit** skill against the target: `$ARGUMENTS`

- A named host is the target; it's likely remote, so confirm scope before connecting — name the box and the read-only sweep, and wait for a go. No host given: ask which box, or run against the local machine if that's clearly meant.
- Covers the hardening scan, attack surface, account and auth hygiene, filesystem risk, mandatory access control (SELinux/AppArmor — recommend and teach where native), CVEs vs installed packages, and Docker/container checks when a runtime is present. An end-of-life OS is the headline finding: recommend the rebuild while still hardening what's there.
- Read-only and non-destructive; every proposed fix is shown and confirmed, never applied on its own.
