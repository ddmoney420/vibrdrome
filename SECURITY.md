# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in Vibrdrome, please report it privately. Do NOT open a public GitHub issue.

**Email:** vibrdrome@gmail.com

Include:
- Description of the vulnerability
- Steps to reproduce
- Affected version/build number
- Any relevant screenshots or logs

We will acknowledge receipt within 48 hours and provide a fix timeline.

## Scope

Security issues we care about:
- Credential exposure (server passwords, API keys, tokens)
- Data leakage (user data sent to unintended destinations)
- Path traversal in file operations
- Authentication bypass
- Insecure data storage

## Current Measures

- Server passwords stored in iOS Keychain (KeychainAccess)
- Last.fm/ListenBrainz credentials stored in Keychain
- No analytics, tracking, or crash reporting SDKs
- No hardcoded credentials in source code
- App Transport Security intentionally broad for user-supplied servers — see note below
- Download file paths sanitized against traversal
- Cookie storage and credential caching disabled on all URLSessions

### App Transport Security

`NSAllowsArbitraryLoads` is enabled so Vibrdrome can connect to user-supplied, self-hosted Navidrome/Subsonic servers — including LAN servers reachable only over HTTP. Because the server URL is arbitrary and unknown at build time, TLS cannot be fully enforced via ATS without breaking those setups.

As a runtime mitigation, the app warns on non-local HTTP connections and requires an explicit one-time confirmation before saving a public (non-local) HTTP server (`ServerConfigView`). LAN/private HTTP and HTTPS connect without prompting. HTTPS — for example via a reverse proxy — is recommended.
