# Security policy

Only the latest release is supported with security fixes.

Please report vulnerabilities privately through
[GitHub private vulnerability reporting](https://github.com/alisoliman/openlist/security/advisories/new).
Include the affected version, reproduction steps and likely impact. Do not
include personal lists, credentials or sensitive attachments in public issues.

Openlist stores data locally. Release binaries are built by GitHub Actions,
signed with Developer ID and notarized by Apple. Verify downloads using the
`SHA256SUMS.txt` attached to the same release.

The optional MCP server is disabled by default, binds only to IPv4 loopback,
and requires a Keychain-backed bearer token. Read-only access and write access
are separate settings. Configured AI clients can access all lists; their own
providers may receive that content. Keep MCP configuration files and clipboard
tokens private. Turn MCP off to disconnect clients or reset the token to revoke
old credentials. Do not proxy or tunnel this local endpoint to a network.
See [MCP access and privacy](README.md#ai-clients-through-mcp) for details.
