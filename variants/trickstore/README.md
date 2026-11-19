# Trick Store build variant

The Trick Store build is the Normal build plus the built-in Tricky Store OSS backend. It uses only that
backend: external Tricky Store, OhMyKeymint and TEESimulator are not used. The Normal build is untouched.

- `overlay/Jerry/` – `ts/` and `sepolicy.rule`, copied byte-for-byte from the v4.7.4 reference ZIP.
  `SHA256SUMS` lists their hashes; `apply.sh` and `verify-zip.sh` check them.
- `patches/` – four small patches (`paths.sh`, `lib/keystore.sh`, `customize.sh`, `service.sh`), applied with
  `patch --fuzz=0`. If `main` changes one of those spots the workflow fails instead of building a wrong ZIP.
- Other keystore modules found at install/boot are **disabled** (reversible), never removed.

Local build: `git clone` a fresh copy, `sh variants/trickstore/apply.sh`, `sh build.sh`.
CI: `.github/workflows/build.yml` (manual `workflow_dispatch`).
