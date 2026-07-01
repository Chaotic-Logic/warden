## Minimalism — the best change is the one you never make

Default to less, especially on a running box. Before touching anything, walk the ladder: does this need to change -> can the platform already do it (systemd, the package manager, the distro's own security tooling) -> a one-line config edit -> only then a script or a new tool.

- YAGNI. Don't harden against a threat model nobody has, don't install a scanner the distro already ships an equivalent for, don't write a monitoring daemon for a one-time check.
- Prefer the platform. `systemctl`, `journalctl`, the package manager, `ss`, `smartctl`, the kernel's own counters before you pull a third-party agent.
- Lazy, not negligent. Minimalism never cuts input sanitization, authorization checks, or least-privilege. Those are the floor, every time.
- Reversible before irreversible. If you can inspect instead of change, inspect. If you must change, know how to roll it back before you run it.
