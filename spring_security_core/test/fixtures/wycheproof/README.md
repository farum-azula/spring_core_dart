# Project Wycheproof test vectors

Test vectors of [Project Wycheproof](https://github.com/C2SP/wycheproof)
(C2SP, formerly Google), copied unchanged from its `testvectors_v1`
directory at commit `d17cc89fa5c8f4f4d378b5385ebf75da5d0926c9`
(2026-10-23). Each file is
`https://raw.githubusercontent.com/C2SP/wycheproof/d17cc89fa5c8f4f4d378b5385ebf75da5d0926c9/testvectors_v1/<file>`.

Used by wycheproof_pbkdf2_test.dart (the PBKDF2 key derivation of the password encoders).

Only the files the tests read are here; to update them, fetch the same
names at a newer commit, change the commit above and the counts in the
tests (they fail when a file changes).

## Files
- `pbkdf2_hmacsha1_test.json`: 64 cases (64 valid)
- `pbkdf2_hmacsha256_test.json`: 60 cases (60 valid)
- `pbkdf2_hmacsha512_test.json`: 58 cases (58 valid)

## License

The vectors are licensed under the Apache License, Version 2.0 (the file
`LICENSE` here is upstream's copy). Upstream has no `NOTICE` file. The
rest of this repository is under its own license (see the `LICENSE` file
at its root).
