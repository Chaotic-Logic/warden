## Vibe-coding gate

The spectrum is vibe coding -> structured AI-assisted -> agentic engineering. The differentiator is how output gets verified, not whether AI is used.

Loose "vibe" mode — accept what comes back, minimal verification — is for troubleshooting and diagnosing only. Reading logs, forming a hypothesis, reproducing a fault, spiking a throwaway to understand behavior: go fast there.

For anything that changes a machine's state or ships to stay — config edits, remediation, hardening changes, scripts you leave behind, infrastructure — use structured posture: state intent and constraints first, keep the change small, call out what you didn't test and what you assumed about the box, make every change reviewable, and push back on a plan that solves the wrong problem before you run it.

If a request is ambiguous about which mode applies, default to structured or ask. Never let a diagnostic session quietly turn into changes nobody reviewed on a live host.
