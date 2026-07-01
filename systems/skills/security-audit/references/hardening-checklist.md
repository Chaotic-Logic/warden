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
- **First-match-wins.** sshd keeps the first value it sees for a key, and the `sshd_config.d/*.conf` drop-ins are read in alphabetical order. A setting only wins if it appears before anything that already set it (an earlier file, or a `Match` block), so name a hardening drop-in to sort ahead, and trust `sshd -T` over the file you wrote.
- **Hardware-backed keys** (`ed25519-sk`/`ecdsa-sk`, a FIDO2 token) where the user has one; the private half never leaves the device, so a stolen disk image yields nothing. A strong split is SSH keys for login and a hardware-backed one-time code for privilege escalation (sudo), so getting in and stepping up to root lean on different mechanisms.

## Accounts + authentication

- UID-0 accounts: `awk -F: '($3==0){print $1}' /etc/passwd` — should be only `root`.
- Empty passwords: `awk -F: '($2==""){print $1}' /etc/shadow` — none.
- Login shells on system accounts: service accounts should be `nologin`/`false`, not a real shell.
- Stale accounts: `lastlog | awk '$2=="**Never**"'` — accounts that never log in but could.
- Failed logins / brute force: `lastb | head`, `journalctl -u ssh --no-pager | grep -i fail`. Repeated hits from one source = the intrusion-banning layer's job (fail2ban across all these families, or CrowdSec for a modern cross-distro take); check one's running. Keep it even on a key-only box: turning off password auth doesn't make it pointless, it still bans the noise, shrinks log volume, and leaves an evidence trail of who's knocking. "Brute-force protection is useless once passwords are off" is wrong.
- Password aging policy: `/etc/login.defs` (`PASS_MAX_DAYS`, `PASS_MIN_LEN` era) and PAM `pam_pwquality`/`pam_faillock` config for lockout on repeated failures.

## sudo / privilege

- `sudo -ll` and the contents of `/etc/sudoers` + `/etc/sudoers.d/*` — who has what.
- `NOPASSWD` grants: enumerate them, each one is a standing risk; justify or flag.
- Broad grants (`ALL=(ALL) ALL` to a wide group) vs. scoped command lists — least privilege applies here hardest.

## Firewall + network

- Backend in use and its ruleset: `nft list ruleset` / `iptables -S` / `ufw status verbose` / `firewall-cmd --list-all`.
- Default inbound policy: default-deny or not. Fail closed.
- Only intended ports open; cross-check against `ss -tulpn` from the health/audit pass.
- Public ports earn their place: SSH, HTTP/HTTPS, and the app/game ports you actually serve. Management surfaces (databases, RCON, telnet, web dashboards, the Docker API, monitoring) belong on a mesh/VPN interface, not `0.0.0.0`. If it's admin, it shouldn't face the internet.
- A near-closed inbound firewall is not automatically a misconfig. An **outbound tunnel** (cloudflared / Cloudflare Tunnel, Tailscale Funnel) or an off-box reverse proxy delivers ingress over an established outbound connection, so web services can run with no matching open port — that's the intended design (origin IP hidden, traffic forced through the edge). Don't flag a default-DROP firewall with services listening as a hole when a tunnel explains the ingress. Do verify the tunnel is the *only* ingress: on a Docker host a `-p` published port bypasses the firewall (see `docker-security.md`), so a service can end up reachable both through the tunnel and directly, which defeats the point.
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

- Is a MAC actually enforcing? SELinux on RHEL-family: `getenforce` (want `Enforcing`), `sestatus`. AppArmor on Debian/Ubuntu/SUSE: `aa-status` (profiles loaded, in enforce mode), and `aa-unconfined` for network daemons with no profile at all.
- A box with no MAC active is a finding, and so is an enabled AppArmor with the exposed daemons unprofiled (its coverage is per-app, not one switch). The fix is to enable and enforce it safely and taught, not flipped.
- Match the distro's native system: recommend SELinux where it ships, AppArmor where it ships, never cross them. Runbooks and the day-to-day lessons in `selinux.md` and `apparmor.md`.

## Updates + patch discipline

- Automatic security updates configured, per family? `unattended-upgrades` (Debian/Ubuntu), `dnf-automatic` (RHEL/Rocky/Alma/Fedora), the `zypper` patch timer or YaST online-update (SUSE). Arch is rolling with no security-only channel, so there's no unattended-security concept — the discipline there is a regular hands-on `pacman -Syu`, and auto-updating Arch unattended is discouraged. Check whether it's on and scoped to security where the family supports that split.
- Read the transaction before you apply it, whichever package manager. No blind auto-yes on a box that matters (`apt -y`, `dnf -y`, `zypper -n`, `pacman --noconfirm`); look at what's added, upgraded, and especially **removed** — dependency resolution will cheerfully pull a package you wanted (removing an old mail server that takes `fail2ban` down with it is a real way to un-harden yourself by accident). Preview first: `apt -s` / `apt full-upgrade`, `dnf` prints the transaction before the prompt, `zypper --dry-run`, `pacman -Syu` lists it (and `pacman -Rns` removals bite hardest). Read it, then say yes.
- Pending reboot for a kernel/glibc update — a patched-but-not-rebooted box is still vulnerable. Cross-check with the CVE reference.

## Logging + audit

- `journald` persistent (`Storage=persistent` in `journald.conf`) or logs vanish on reboot right when you need them.
- `auditd` running if the box needs an audit trail; check it's actually capturing, not just installed.
- Logs shipping off-box somewhere, or at least rotating and not filling the disk (ties back to the disk-capacity check in health-check).
