# Release provenance checklist

For every release, record:

- module version and commit SHA;
- AdGuard Home upstream version/tag and source URL;
- architecture for every binary asset;
- SHA-256 for every binary, rule snapshot, and final ZIP;
- license/notice files included in the ZIP;
- migration compatibility boundary;
- device validation matrix and known gaps.

Do not publish a release while any binary or rule snapshot lacks a source, checksum, and applicable license record.
