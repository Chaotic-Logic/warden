---
description: "Diagnose a specific host fault — a crash, hang, slowness, OOM, disk-full, or failed boot"
argument-hint: "[host] [symptom]"
---

Run the warden **triage** skill on: `$ARGUMENTS`

- Read a leading hostname as the target if one's given, and confirm scope before connecting to a remote box; the rest is the symptom. No host: ask, or work the local box if that's clearly meant.
- triage is for operating-system and server faults — a service that won't start, a hang, a box gone slow, an OOM kill, a full disk, a failed boot — not application-code bugs, failing tests, or CI. Method: reproduce, read the logs, one hypothesis at a time, isolate, then the smallest fix.
- Diagnosis runs loose and fast; the moment a fix would change the box it flips to structured and gets confirmed first.
