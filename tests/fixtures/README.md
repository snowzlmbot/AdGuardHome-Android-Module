# Test fixtures

Fixtures are deterministic and contain no device data, credentials, tokens, or downloaded binaries.

Android-specific commands are represented by command-recording shims in later tests. A passing fixture test proves shell logic and command ordering only; it does not prove behavior on a real Magisk, KernelSU, APatch, iptables backend, or SELinux policy.
