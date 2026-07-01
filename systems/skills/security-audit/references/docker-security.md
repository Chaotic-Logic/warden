# Docker / container security

Only relevant when `recon` found a container runtime up. A Docker host stacks a second attack surface on the OS underneath — the daemon runs as root, so a container escape or an exposed socket is a full host compromise, not a sandbox nuisance. All commands here are read-only inspection. Fixes (rebuild an image, restart a container with dropped caps, lock the socket) are proposed and confirmed, never applied live.

Most of this is Docker-worded. Podman is the rootless daemonless cousin — the image-scan and runtime-flag checks apply the same; the daemon-socket and root-daemon findings mostly don't, which is the point of podman. Note which one you're on.

## The host-takeover findings — check these first

These are not "harden later," they're "the box is already owned if present":

- **Daemon exposed over TCP unencrypted.** `ss -tulpn | grep -E ':2375|:2376'`, and check `daemon.json` / the systemd unit `-H tcp://` flags. `2375` is plaintext, unauthenticated, full root-equivalent control of the host to anyone who can reach it. `2376` should be TLS with client-cert auth (`--tlsverify`); confirm it actually is, not just that it's the "secure" port number.
- **`docker.sock` bind-mounted into a container.** `docker ps -q | xargs -r docker inspect -f '{{.Name}}: {{range .Mounts}}{{.Source}} {{end}}' | grep docker.sock`. A container with the socket mounted can spawn a privileged container on the host and walk right out. Common in CI runners and "management" containers; rarely justified.
- **`--privileged` containers.** `docker ps -q | xargs -r docker inspect -f '{{.Name}} privileged={{.HostConfig.Privileged}}'`. Privileged drops nearly every isolation boundary — device access, all caps, no seccomp. Each one needs a hard justification or it's a finding.

## Runtime posture, per container

`docker inspect` on each running container; the fields that matter:

- `.HostConfig.Privileged` — see above, should be `false`.
- `.HostConfig.CapAdd` — added Linux capabilities. `SYS_ADMIN`, `NET_ADMIN`, `SYS_PTRACE` are escape-adjacent; enumerate and justify.
- `.HostConfig.PidMode` / `.HostConfig.NetworkMode` — `host` means no PID/network namespace isolation. Flag `host`.
- `.Config.User` — empty or `0`/`root` means the container process runs as root; a UID compromise is a root compromise inside the container. Prefer a non-root `USER`.
- `.HostConfig.ReadonlyRootfs` — `true` is the hardened default for anything that doesn't need to write its own fs.
- `.HostConfig.Binds` / `.Mounts` — sensitive host paths mounted in: `/`, `/etc`, `/var/run/docker.sock`, `/proc`, `/sys`. Each is a hole.
- `.HostConfig.SecurityOpt` — is seccomp/AppArmor still on, or was it disabled with `seccomp=unconfined` / `apparmor=unconfined`? Disabling them is a finding.

One-liner to sweep the obvious ones:
```
for c in $(docker ps -q); do
  docker inspect -f '{{.Name}} priv={{.HostConfig.Privileged}} user={{.Config.User}} net={{.HostConfig.NetworkMode}} caps={{.HostConfig.CapAdd}}' "$c"
done
```

## Image vulnerabilities

Scan the images, not just the host's OS packages — every image ships its own OS layer plus app dependencies, each with its own CVEs.

- **Trivy** — the standard: `trivy image <image>` (OS + language deps), `trivy image --severity HIGH,CRITICAL <image>` to cut noise. Also `trivy config <dir>` to lint Dockerfiles/compose for misconfig.
- **Grype** — `grype <image>`, own DB (`grype db update`).
- **Docker Scout** — built into recent Docker: `docker scout cves <image>`, `docker scout quickview`. No extra install if the CLI's current.
- Scan everything in play, not just what's running:
```
docker images --format '{{.Repository}}:{{.Tag}}' | grep -v '<none>' | while read img; do
  echo "== $img =="; trivy image --quiet --severity HIGH,CRITICAL "$img"
done
```
- Rank findings by whether the image is actually running and exposed, same as OS-package CVEs — a CRITICAL in a stopped image nobody runs is not the emergency a scanner's summary count implies.

## Image provenance + hygiene

- Unpinned `latest` tags: `docker ps --format '{{.Image}}'` — `latest` (or no digest) means you can't reason about what's actually deployed or reproduce it. Pin to a digest for anything that matters.
- Base image age: a years-old base carries years of unpatched CVEs no matter how clean your app layer is.
- Secrets baked into layers: `docker history --no-trunc <image>` can reveal build args / env with credentials; Trivy's secret scanning catches some too. A secret in a layer is committed forever, same as one in git — rotate it.

## Daemon + host hardening

- **docker-bench-security** — Docker's own script for the CIS Docker Benchmark. Run it (`docker run` the official image, or the shell script) and read the WARN/INFO lines; covers daemon config, container defaults, and image/build guidance in one pass. Treat like Lynis: it flags, you judge.
- `daemon.json` (`/etc/docker/daemon.json`) worth checking:
  - `"userns-remap"` set — maps container root to an unprivileged host UID, big blast-radius reduction.
  - `"no-new-privileges": true` as a default.
  - `"icc": false` — no unrestricted inter-container traffic on the default bridge.
  - `"live-restore": true` — containers survive a daemon restart (availability, not security, but ops-relevant).
  - `"userland-proxy": false` where the setup allows.
- Socket ownership: `/var/run/docker.sock` should be `root:docker`, `660`. Membership in the `docker` group is root-equivalent on the host — audit who's in it (`getent group docker`), least-privilege applies hard here.
- **Rootless mode** is the strong move where the workload tolerates it: the daemon runs as a normal user, so an escape lands as that user, not root. Note whether it's in use.

## Reporting

Group container findings under the Security Report by class: host-takeover (socket/tcp/privileged) at the top, then runtime posture, then image CVEs, then hygiene. For each: what, which container/image, why it matters on this host, and the proposed fix — as a proposal. Redact any secrets surfaced by history/secret scanning; report that one exists and where, never its value.
