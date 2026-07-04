# Security Policy

## Supported Versions

Every package in this suite is pre-1.0 and independently versioned. Only the
**latest published version of each package** is supported with security
fixes:

| Package | Supported |
|---|---|
| `radarscope` | latest only |
| `flutter_leak_radar` | latest only |
| `flutter_perf_radar` | latest only |
| `flutter_leak_radar_lint` | latest only |
| `leak_graph` | latest only |
| `radar_trace` | latest only |
| `radar_ui` | latest only |

Radar is a **debug/profile-only observability tool** — it is a complete
no-op in release builds, which limits the blast radius of most classes of
issue to development-time usage. That said, we still take reports seriously,
particularly around the DevTools/VM Service connection paths, since those
accept host-side input.

## Reporting a Vulnerability

Please **do not open a public GitHub issue** for security vulnerabilities.

Instead, report privately using one of:

1. **GitHub Security Advisories** (preferred) — open a [private security
   advisory](https://github.com/tp9imka/flutter-leak-radar/security/advisories/new)
   on this repository.
2. **Email the maintainer** — reach `tp9imka` via the contact info on their
   [GitHub profile](https://github.com/tp9imka) if the advisory workflow
   isn't accessible to you.

Please include:

- The affected package(s) and version(s)
- A description of the vulnerability and its potential impact
- Steps to reproduce, or a minimal repro if possible

We aim to acknowledge reports within a few days and to follow up with a
fix timeline once the issue is confirmed. We'll credit reporters in the
release notes unless you'd prefer to remain anonymous.
