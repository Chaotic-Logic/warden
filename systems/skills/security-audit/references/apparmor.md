# AppArmor — check it, push it on where it's native, teach it

The SELinux story's counterpart. Same goal (a mandatory access layer boxing each service to what it's allowed), different design: AppArmor is **path-based** and **per-application**. That second word is the thing to keep in front of you — AppArmor only confines a program that has a profile loaded; everything else runs unconfined. So "AppArmor is enabled" is necessary but not the finish line the way "SELinux enforcing" nearly is.

## Where AppArmor applies

- **Ubuntu** (on by default), **Debian** (present, sometimes needs the packages + a kernel flag), **openSUSE / SLES** (their default MAC). Recommend it there.
- **RHEL-family** run SELinux; don't push AppArmor at them. See `selinux.md`.
- Match the distro's native system. A box running neither is the finding; the fix is the one the distro ships, not whichever you like better.

## Check state

- `sudo aa-status` (a.k.a. `apparmor_status`) — profiles loaded, how many in enforce vs complain, which processes are confined vs not.
- `systemctl status apparmor`.
- LSM actually active in the kernel: `cat /sys/module/apparmor/parameters/enabled` should be `Y`, and `cat /sys/kernel/security/lsm` should list `apparmor`.
- `sudo aa-unconfined` — network-facing daemons running with **no profile**. Each one is a gap even on a box that reports AppArmor "enabled and enforcing." This is the check people skip; run it.

## Recommend, don't flip — the safe enable path

Enabling or enforcing is a state change: proposed, confirmed, taught, never automatic.

1. **Packages** (Debian; Ubuntu has the base already): `apparmor apparmor-utils apparmor-profiles`, plus `apparmor-profiles-extra` for more shipped profiles.
2. **Service**: `sudo systemctl enable --now apparmor`.
3. **Kernel LSM**, if the /sys checks above show it's not active (Debian commonly needs this; Ubuntu ships it on): add `apparmor=1 security=apparmor` to `GRUB_CMDLINE_LINUX` in `/etc/default/grub`, `sudo update-grub`, reboot, re-check.
4. **Profiles in complain (learning) mode first** so nothing breaks: `sudo aa-complain /etc/apparmor.d/*`, then run the real workload. Complain logs what it *would* block without blocking it.
5. **Fold the real behavior into the profiles**: `sudo aa-logprof` reads the logged accesses and walks you through allow/deny, updating the profile. Repeat under real load until quiet.
6. **Enforce** when clean: `sudo aa-enforce /etc/apparmor.d/<profile>`.

Keep a console or second session across any reboot. Never strand yourself, same rule as the SSH and SELinux steps.

## The lesson — the mental model

A profile names an executable and spells out exactly which files, capabilities, and network it may use. **No profile means unconfined** — AppArmor simply ignores that program. Two modes per profile: **enforce** (block and log) and **complain** (log only, the learning mode). Contrast SELinux: paths vs labels, and opt-in-per-app vs targeted-everything. The practical upshot is coverage: with SELinux the policy blankets the system; with AppArmor you're responsible for making sure the daemons that face the network actually have profiles.

`aa-status` and `aa-unconfined` are how you see that coverage.

## The lesson — day-to-day commands

- `sudo aa-status`, `sudo aa-unconfined`.
- Mode per profile: `sudo aa-enforce <profile>`, `sudo aa-complain <profile>`, `sudo aa-disable <profile>`.
- `sudo aa-genprof <program>` — build a new profile by running the app and watching what it touches.
- `sudo aa-logprof` — the core loop: update profiles from logged denials.
- Reload after editing a profile by hand: `sudo apparmor_parser -r /etc/apparmor.d/<profile>`.
- Read denials: `sudo dmesg | grep -i apparmor`, `journalctl -k | grep apparmor`, or `sudo aa-notify -s 1 -v` for a summary. Look for `apparmor="DENIED"`.
- Profiles live in `/etc/apparmor.d/`; shared fragments in `abstractions/` and `tunables/` under it.

## The trap

`systemctl disable apparmor`, or dropping every profile to complain, to make a denial stop is the same surrender as `setenforce 0`. The fix is `aa-logprof` or a targeted edit to the one profile, then reload. And don't confuse "enabled" with "covered": run `aa-unconfined` and get profiles onto the internet-facing daemons. An AppArmor that's enforcing while your web server runs unconfined isn't guarding the process most likely to be attacked.
