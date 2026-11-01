# Project Wycheproof test vectors

Test vectors of [Project Wycheproof](https://github.com/C2SP/wycheproof)
(C2SP, formerly Google), copied unchanged from its `testvectors_v1`
directory at commit `d17cc89fa5c8f4f4d378b5385ebf75da5d0926c9`
(2026-10-23). Each file is
`https://raw.githubusercontent.com/C2SP/wycheproof/d17cc89fa5c8f4f4d378b5385ebf75da5d0926c9/testvectors_v1/<file>`.

Used by wycheproof_jws_test.dart (ECDSA P1363, RSA PKCS#1 v1.5, RSA-PSS and HMAC through the JWS verifier) and wycheproof_ec_points_test.dart (the ECDH public points: invalid-curve keys through the JWK and DPoP code).

Only the files the tests read are here; to update them, fetch the same
names at a newer commit, change the commit above and the counts in the
tests (they fail when a file changes).

## Files
- `ecdh_secp256r1_ecpoint_test.json`: 355 cases (1 acceptable, 24 invalid, 330 valid)
- `ecdh_secp384r1_ecpoint_test.json`: 790 cases (1 acceptable, 18 invalid, 771 valid)
- `ecdh_secp521r1_ecpoint_test.json`: 661 cases (1 acceptable, 28 invalid, 632 valid)
- `ecdsa_secp256r1_sha256_p1363_test.json`: 262 cases (89 invalid, 173 valid)
- `ecdsa_secp384r1_sha384_p1363_test.json`: 280 cases (87 invalid, 193 valid)
- `ecdsa_secp521r1_sha512_p1363_test.json`: 318 cases (87 invalid, 231 valid)
- `hmac_sha256_test.json`: 174 cases (108 invalid, 66 valid)
- `hmac_sha384_test.json`: 174 cases (108 invalid, 66 valid)
- `hmac_sha512_test.json`: 174 cases (108 invalid, 66 valid)
- `rsa_pss_2048_sha256_mgf1_32_test.json`: 108 cases (45 invalid, 63 valid)
- `rsa_pss_2048_sha384_mgf1_48_test.json`: 141 cases (46 invalid, 95 valid)
- `rsa_pss_3072_sha256_mgf1_32_test.json`: 108 cases (45 invalid, 63 valid)
- `rsa_pss_4096_sha512_mgf1_64_test.json`: 179 cases (47 invalid, 132 valid)
- `rsa_signature_2048_sha256_test.json`: 259 cases (1 acceptable, 249 invalid, 9 valid)
- `rsa_signature_2048_sha384_test.json`: 258 cases (1 acceptable, 250 invalid, 7 valid)
- `rsa_signature_2048_sha512_test.json`: 259 cases (1 acceptable, 250 invalid, 8 valid)
- `rsa_signature_3072_sha256_test.json`: 259 cases (1 acceptable, 250 invalid, 8 valid)
- `rsa_signature_4096_sha256_test.json`: 258 cases (1 acceptable, 250 invalid, 7 valid)

## License

The vectors are licensed under the Apache License, Version 2.0 (the file
`LICENSE` here is upstream's copy). Upstream has no `NOTICE` file. The
rest of this repository is under its own license (see the `LICENSE` file
at its root).
