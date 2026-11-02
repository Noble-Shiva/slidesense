# Security policy

## Supported versions

SlideSense is a local macOS app with no network access. Only the latest release
is supported.

## Reporting a vulnerability

Please email **shashvat@clueso.io** with:

- the SlideSense version (`swift run SlideSense --diagnose` prints it),
- your macOS version and Mac model,
- what the issue lets an attacker do, and the steps to reproduce it.

Do not open a public issue for anything that could be exploited. You will get an
acknowledgement within a few days, and credit in the release notes if you want it.

## What is in scope

- Code execution or privilege escalation beyond the Accessibility permission the
  user granted.
- Sandbox or TCC bypass, or anything that writes outside the app's own settings.
- Unintended network traffic (there should be none).

## What is not in scope

- The use of private Apple frameworks (`MultitouchSupport`, `DisplayServices`).
  They are used deliberately, feature-detected, and documented in the README; a
  macOS update breaking them is a bug report, not a vulnerability.
- Gatekeeper warnings. Builds are unsigned and not notarised; right-click → Open
  the first time, or build it yourself.
