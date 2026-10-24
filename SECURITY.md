# Security policy

roc-font reads font files, which are untrusted input. A font that makes a
successful read or any later query or shaping call crash, hang, use
unbounded memory or time, or return non-finite numbers is a defect, and one
that an attacker could trigger with a crafted file may be a vulnerability.

## Supported versions

Fixes are made on `main` and included in the next release. Only the latest
release and `main` are supported.

## Report a vulnerability privately

Do not report a suspected vulnerability in a public issue, discussion or
pull request. Use
[GitHub private vulnerability reporting](https://github.com/lukewilliamboswell/roc-font/security/advisories/new),
so the details stay private while they are investigated.

Include the affected version or commit, the Roc nightly you used, the
impact, and the smallest font bytes and calls that reproduce the problem
(attach the font file, or the bytes as a Roc list). Say whether the bytes
may be published as a regression test once the issue is fixed.
