# Hardening review checklist

Config-level review, command per line. All read-only. Findings feed the Security Report; fixes are proposed and confirmed, never applied inline. This is the human-judgment layer on top of what Lynis/OpenSCAP flag automatically — a scanner catches the letter, you catch whether it matters for this box's role.

## SSH (the front door)

`sshd -T` dumps the effective running config (better than reading `sshd_config`, which misses defaults and `Match` blocks). Check:

- `permitrootlogin` — should be `no` (or `prohibit-password` at most).
- `passwordauthentication` / `kbdinteractiveauthentication` — `no` on any box that has keys set up. Password auth is brute-force surface.
- `pubkeyauthentication yes`.
- `permitemptypasswords no`.
- `x11forwarding no` unless actually needed.
- `allowusers` / `allowgroups` — scoping who can SSH at all is cheap and strong.
- Non-default port is obscurity, not security; don't count it as a control, but note it so it isn't mistaken for a closed port.
- Ciphers/MACs/KEX: flag known-weak (CBC ciphers, `hmac-md5`, SHA-1 KEX) only if you're held to a compliance baseline; otherwise the distro defaults are usually fine.

## Accounts + authentication

- UID-0 accounts: `awk -F: '($3==0){print $1}' /etc/passwd` — should be only `root`.
- Empty passwords: `awk -F: '($2==""){print $1}' /etc/shadow` — none.
- Login shells on system accounts: service accounts should be `nologin`/`false`, not a real shell.
- Stale accounts: `lastlog | awk '$2=="**Never**"'` — accounts that never log in but could.
- Failed logins / brute force: `lastb | head`, `journalctl -u ssh --no-pager | grep -i fail`. Repeated hits from one source = fail2ban's job; check it's running.
- Password aging policy: `/etc/login.defs` (`PASS_MAX_DAYS`, `PASS_MIN_LEN` era) and PAM `pam_pwquality`/`pam_faillock` config for lockout on repeated failures.

## sudo / privilege

- `sudo -ll` and the contents of `/etc/sudoers` + `/etc/sudoers.d/*` — who has what.
- `NOPASSWD` grants: enumerate them, each one is a standing risk; justify or flag.
- Broad grants (`ALL=(ALL) ALL` to a wide group) vs. scoped command lists — least privilege applies here hardest.

## Firewall + network

- Backend in use and its ruleset: `nft list ruleset` / `iptables -S` / `ufw status verbose` / `firewall-cmd --list-all`.
- Default inbound policy: default-deny or not. Fail closed.
- Only intended ports open; cross-check against `ss -tulpn` from the health/audit pass.
- IPv6: same rules apply. A box firewalled on v4 and wide open on v6 is a common miss — check both.

## Kernel hardening (sysctl)

`sysctl -a` (or read the effective values); the ones worth checking on a server:

- `net.ipv4.conf.all.rp_filter=1` (reverse-path filtering).
- `net.ipv4.tcp_syncookies=1`.
- `net.ipv4.conf.all.accept_redirects=0`, `send_redirects=0`, `accept_source_route=0`.
- `kernel.randomize_va_space=2` (full ASLR).
- `kernel.kptr_restrict>=1`, `kernel.dmesg_restrict=1`, `kernel.yama.ptrace_scope>=1` — limit info leaks and cross-process ptrace.
- `fs.protected_hardlinks=1`, `fs.protected_symlinks=1`.

Don't cargo-cult a giant sysctl blob; check these, justify anything you'd change, and know it persists via `/etc/sysctl.d/` not a live `sysctl -w` that dies on reboot.

## Filesystem

- SUID/SGID inventory: `find / -xdev \( -perm -4000 -o -perm -2000 \) -type f 2>/dev/null` — compare against a known-good baseline for the distro; investigate anything unusual.
- World-writable files without sticky: `find / -xdev -type f -perm -0002 2>/dev/null` and dirs `find / -xdev -type d -perm -0002 ! -perm -1000 2>/dev/null`.
- Mount options: `/tmp`, `/var/tmp`, `/dev/shm` with `noexec,nosuid,nodev` where the workload allows; `findmnt` to read them.
- Unowned files (deleted user left them): `find / -xdev -nouser -o -nogroup 2>/dev/null`.

## Services + surface reduction

- `systemctl list-unit-files --state=enabled` — everything set to start. Anything enabled that this box doesn't need is surface; question it.
- Legacy/cleartext services (telnet, rsh, vsftpd anon, unauth NFS) — should not be present on a modern server.
- Time sync running (chrony/systemd-timesyncd) — cert validation and log correlation depend on it.

## Mandatory access control

- Is a MAC actually enforcing? SELinux on RHEL-family: `getenforce` (want `Enforcing`), `sestatus`. AppArmor on Debian/Ubuntu/SUSE: `aa-status` (profiles loaded, in enforce mode).
- A box with no MAC active is a finding. On a SELinux-native distro, `Disabled`/`Permissive` is the finding and the fix is to enable it — safely, and taught, not flipped. Full runbook and the day-to-day lessons in `selinux.md`.
- Don't recommend SELinux on an AppArmor distro (or vice versa); check whichever the distro ships.

## Updates + patch discipline

- Automatic security updates configured? (`unattended-upgrades` on debian, `dnf-automatic` on rhel). Note whether it's on and whether it's set to security-only.
- Pending reboot for a kernel/glibc update — a patched-but-not-rebooted box is still vulnerable. Cross-check with the CVE reference.

## Logging + audit

- `journald` persistent (`Storage=persistent` in `journald.conf`) or logs vanish on reboot right when you need them.
- `auditd` running if the box needs an audit trail; check it's actually capturing, not just installed.
- Logs shipping off-box somewhere, or at least rotating and not filling the disk (ties back to the disk-capacity check in health-check).
