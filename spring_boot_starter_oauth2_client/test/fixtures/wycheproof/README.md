# Project Wycheproof test vectors

Test vectors of [Project Wycheproof](https://github.com/C2SP/wycheproof)
(C2SP, formerly Google), copied unchanged from its `testvectors_v1`
directory at commit `d17cc89fa5c8f4f4d378b5385ebf75da5d0926c9`
(2026-10-23). Each file is
`https://raw.githubusercontent.com/C2SP/wycheproof/d17cc89fa5c8f4f4d378b5385ebf75da5d0926c9/testvectors_v1/<file>`.

Used by wycheproof_test.dart (the ES256 and RS256 verification of ID tokens, the DER to R || S conversion of platform keys, and the signing paths).

Only the files the tests read are here; to update them, fetch the same
names at a newer commit, change the commit above and the counts in the
tests (they fail when a file changes).

## Files
- `ecdsa_secp256r1_sha256_p1363_test.json`: 262 cases (89 invalid, 173 valid)
- `ecdsa_secp256r1_sha256_test.json`: 484 cases (310 invalid, 174 valid)
- `rsa_signature_2048_sha256_test.json`: 259 cases (1 acceptable, 249 invalid, 9 valid)

## License

The vectors are licensed under the Apache License, Version 2.0 (the file
`LICENSE` here is upstream's copy). Upstream has no `NOTICE` file. The
rest of this repository is under its own license (see the `LICENSE` file
at its root).
