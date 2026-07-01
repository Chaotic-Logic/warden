# SELinux — check it, recommend enforcing where it belongs, teach it

Mandatory access control is a real hardening layer: even a compromised root-running service is boxed to what policy allows. warden checks it's on where it should be, recommends turning it on when it's off on an applicable box, and (because that's a state change) teaches the safe path rather than flipping it.

## Where SELinux applies — don't cargo-cult it

- **RHEL-family** (RHEL, Rocky, Alma, CentOS, Fedora, Oracle) ships SELinux as the native MAC. On these, `Disabled` or `Permissive` is a genuine gap; recommend `Enforcing`.
- **Debian / Ubuntu / SUSE** ship **AppArmor** instead. Do not push SELinux there — installing it is a migration project, not a quick win, and you'd be fighting the distro. Check the MAC they *do* ship is enabled: `aa-status` (AppArmor should be loaded with profiles in enforce mode).
- The rule: recommend SELinux only where the distro already ships and supports it as default. Everywhere else, verify the shipped MAC is on and enforcing. A box with *no* MAC active is the finding, whichever system it should be running.

## Check state (SELinux)

- `getenforce` -> `Enforcing` / `Permissive` / `Disabled`.
- `sestatus` -> live mode, mode from config, loaded policy, mount status.
- `/etc/selinux/config` -> `SELINUX=` (persistent setting) and `SELINUXTYPE=` (normally `targeted`).

`Permissive` logs what it *would* block but enforces nothing — a tuning state, not a secure end state. `Disabled` means off and the filesystem isn't labeled.

## Recommend, don't flip — the safe enable path

Turning SELinux on is a state change on a live host: proposed and confirmed, never automatic. And going `Disabled` -> `Enforcing` in one step is how you get an unbootable or broken box, because nothing on disk has a security label yet. The path that doesn't bite:

1. Set `SELINUX=permissive` in `/etc/selinux/config` (permissive first, not enforcing).
2. Schedule a full relabel on next boot: `sudo fixfiles onboot` (or `sudo touch /.autorelabel`).
3. Reboot. On a large filesystem the relabel takes a while; expect it and don't panic at the pause.
4. Run the real workload in permissive and watch what *would* be denied: `sudo ausearch -m avc -ts recent`, `sudo aureport -a`. Nothing's blocked yet, so nothing breaks, but you see the shape of it.
5. Clear the denials (booleans, file contexts, or a custom module — below). When it's quiet under real load, set `SELINUX=enforcing` and reboot. `setenforce 1` flips the live mode first if you want to test before committing the reboot.

Keep a console or second session through any reboot, same discipline as the SSH-hardening step: never strand yourself.

## The lesson — the mental model

Every process and file carries a **context**: `user:role:type:level`. Day to day the **type** is what matters; this is *type enforcement*. A process running as `httpd_t` is allowed to read files labeled `httpd_sys_content_t` and is not allowed to touch `shadow_t`, regardless of Unix perms. Policy is a big allowlist of "this type may do this to that type." An AVC denial means "no rule allows that," not "the file mode is wrong."

See contexts with `ls -Z`, `ps -Z`, `id -Z`. A service misbehaving under SELinux is usually a mislabeled file, not a policy that needs loosening.

## The lesson — day-to-day commands

- **Booleans** — prebuilt on/off switches for the common cases. `getsebool -a`, then e.g. `sudo setsebool -P httpd_can_network_connect on` (`-P` persists across reboot). Reach for a boolean before writing any custom policy; the common need usually already has one.
- **File contexts** — right label, right behavior. `sudo semanage fcontext -a -t httpd_sys_content_t "/srv/web(/.*)?"` then `sudo restorecon -Rv /srv/web`. `semanage fcontext` changes what policy *says* the label should be; `restorecon` applies it. `restorecon -Rv` is the first thing to try when "it works with SELinux off."
- **Ports** — a daemon on a nonstandard port needs that port labeled: `sudo semanage port -a -t http_port_t -p tcp 8443`.
- **Reading denials** — `sudo ausearch -m avc -ts recent` for the raw AVCs; pipe to `audit2why` for the plain reason; `audit2allow` to build a policy module only when a custom rule is genuinely warranted (`sudo ausearch -m avc | audit2allow -M mymod && sudo semodule -i mymod.pp`). With setroubleshoot installed, `sealert` turns denials into readable suggestions.

## The trap — teach this first

`setenforce 0`, or `SELINUX=disabled`, "fixes" a broken service by switching the guard off. That's not a fix, it's surrender, and it's the single most common bad habit around SELinux. When a service breaks under enforcing, the answer is almost always a boolean or a `restorecon`, occasionally a small custom module — not disabling it. Lead with that whenever you're teaching someone who's been burned by it before.
