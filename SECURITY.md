# Security Policy

## Supported Versions

| Version | Supported |
| ------- | --------- |
| 1.1.x   | ✅        |
| 1.0.x   | ✅        |
| < 1.0   | ❌        |

Security fixes ship in the latest release on the App Store and Homebrew.
Older versions are not patched individually.

## Reporting a Vulnerability

Please **do not** open a public issue for security problems.

Report vulnerabilities privately through GitHub's security advisory form:

**[Report a vulnerability](https://github.com/codybrom/Blankie/security/advisories/new)**

Include what you found, steps to reproduce, and the Blankie version and OS you tested.
You can expect an acknowledgment within a few days. Fixes are prioritized by severity
and credited in release notes unless you prefer otherwise.

## Scope

### In Scope

- Blankie apps for macOS and iOS (including CarPlay) and iPadOS
- Exported `.blankie` files
- Build/release tooling in this repository.

### Out of scope

- `https://blankie.rest` - Blankie's website (static content)
- Vulnerabilities in Apple frameworks or third-party services
  - Reports that Blankie *uses* them insecurely are still very welcome
