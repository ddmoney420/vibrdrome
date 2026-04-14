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
- ATS exceptions only for self-hosted HTTP servers (with user warning)
- Download file paths sanitized against traversal
- Cookie storage and credential caching disabled on all URLSessions
