# Implementation Plan

## Overview

TEE Simulator Plus モジュールの実装計画。KernelSU/Magisk モジュール構造、シェルスクリプトバックエンド、KSU WebUI フロントエンド、ネイティブ Attestation Hook、遅延プロファイラ/イコライザ、およびプロパティベーステストを含む。

## Tasks

- [ ] 1. Create module directory structure with all required directories (META-INF/, webroot/, libs/, scripts/, keyboxes/, config/, logs/, docs/) and META-INF/com/google/android/update-binary and updater-script
- [ ] 2. Create `module.prop` with id=tee-simulator-plus, name=TEE Simulator Plus, version, versionCode, author, description, updateJson fields
- [ ] 3. Create `customize.sh` with environment detection (KernelSU/Magisk, abort if neither), API level check (>=29, abort if lower), architecture detection (arm64-v8a/armeabi-v7a), library placement, permission setup (0600 for keyboxes/config), and existing config preservation on update
- [ ] 4. Create `post-fs-data.sh` with Attestation Hook native library injection preparation via Zygisk/LSPlt registration
- [ ] 5. Create `service.sh` with Configuration_Store loading and Latency_Equalizer pre-warming logic (read referenceProfile, execute 50 dummy calls if profile exists)
- [ ] 6. Create `sepolicy.rule` with required SELinux policy rules for module operation in enforcing mode
- [ ] 7. Create `config/config.json` with default schema (schemaVersion=1, empty activeKeyboxId, empty targetList, detectionThreshold=1.1, sampleCount=500, latencyEqualizerEnabled=true, logLevel=INFO, null referenceProfile, empty keyboxMetadata array)
- [ ] 8. Create shared logging library `scripts/lib/logger.sh` with log_error, log_warn, log_info, log_debug functions, timestamp formatting (YYYY-MM-DD HH:MM:SS [LEVEL] component: message), log level filtering, log rotation at 5MB (rename to module.log.1), and logcat fallback (tag=TEESimulatorPlus) on write failure
- [ ] 9. Create `scripts/config_manager.sh` with config_get (return full config JSON), config_set (update individual keys with validation: detectionThreshold 1.01-2.0, sampleCount 100-5000, logLevel ERROR|WARN|INFO|DEBUG), log_tail (return last N lines), schema migration (detect version mismatch, backup to .bak, migrate), parse failure handling (return defaults), and 0600 permission enforcement on writes
- [ ] 10. Create `scripts/lib/keybox_parser.sh` with XML structure validation (check AndroidAttestation/Keybox/Key hierarchy, PrivateKey, CertificateChain elements), PEM validation via openssl, error codes (INVALID_KEYBOX_SCHEMA with missing element name, INVALID_PEM_ENCODING), metadata extraction (algorithm from Key@algorithm, certificate subject via openssl x509), and SHA-256 hash calculation for filename generation
- [ ] 11. Create `scripts/keybox_manager.sh` with command dispatcher and implementations: keybox_validate (call parser, return valid/invalid), keybox_add (validate, compute SHA-256, copy to keyboxes/<hash>.xml with 0600, add metadata to config, reject duplicates), keybox_list (read metadata, mark active), keybox_select (verify exists, update activeKeyboxId), keybox_delete (remove file, remove metadata, clear activeKeyboxId if was active)
- [ ] 12. Create `scripts/target_manager.sh` with command dispatcher and implementations: target_list_installed (pm list packages -3 with app name, merge isTarget flags), target_add (validate RFC 1035 format, add to set, no duplicates), target_remove (remove from set), target_import (parse target.txt skipping # comments and empty lines, add each to set), target_export (write header comment + one package per line in Tricky-Addon format)
- [ ] 13. Create Shell Bridge entry point with command whitelist validation (keybox_add/list/select/delete/validate, target_list_installed/add/remove/import/export, profiler_run/reference/calibrate, config_get/set, log_tail), JSON input parsing, routing to appropriate backend script, JSON response wrapping (status+data or status+message), unknown command 400 response, 30-second timeout with 408 response, and error catching with 500 response
- [ ] 14. Create `webroot/index.html` with Material Design 3 dark theme layout, tab navigation (Keybox, Targets, Diagnostics, Logs), status panel (module status, active keybox, target count, timing side-channel warning), and responsive structure
- [ ] 15. Create `webroot/style.css` with Material Design 3 dark theme tokens, responsive layout, status indicator colors (green=Negative, red=Positive), tab styles, card components, form inputs, and KernelSU Manager visual harmony
- [ ] 16. Create `webroot/app.js` with execCommand function (ksu.exec() wrapper with whitelist check), tab switching logic, initialization, and error display utilities
- [ ] 17. Implement Keybox panel in WebUI: list view with active indicator badge, file upload via input[type=file], select/delete action buttons, validation feedback display, and upload progress indication
- [ ] 18. Implement Target panel in WebUI: installed app list with toggle switches for target status, search/filter input with partial match on package name and app name, import button (file input for target.txt), export button, and target count display
- [ ] 19. Implement Diagnostics panel in WebUI: run profiler button, sample count input (100-5000 range), threshold input (1.01-2.0 range), result display (T_a, T_n, diff, ratio, filteredBadSamples, judgment with color coding), calibrate reference profile button, and Positive judgment advisory (risk explanation + recommended actions)
- [ ] 20. Implement Logs panel in WebUI: log viewer showing last 200 lines with monospace formatting, 5-second polling interval for updates, log level selector dropdown, and auto-scroll to bottom
- [ ] 21. Create `scripts/latency_profiler.sh` with profiler_run (CPU pinning via taskset, 50 pre-warming calls, Sample_Count measurement loop for attested/non-attested paths, outlier removal top/bottom 5%, statistics calculation T_a/T_n/diff/ratio, judgment vs threshold, log entry in specified format), profiler_reference (return stored profile), profiler_calibrate (measure hardware-backed timing, compute mean/stddev, save to config)
- [ ] 22. Implement Latency Equalizer logic in native hook: read config (latencyEqualizerEnabled, referenceProfile, detectionThreshold), calculate target_time = T_n / detection_threshold, compute wait = max(0, target_time - elapsed), add jitter within [-stddev, +stddev], apply CPU pinning for precision, nanosleep wait time, skip if disabled or no profile (log warning)
- [ ] 23. Set up native build configuration (CMakeLists.txt or Android.mk) for arm64-v8a and armeabi-v7a targets with Zygisk module structure
- [ ] 24. Implement Zygisk module entry point with process fork callback, target list check against config, and conditional hook registration
- [ ] 25. Implement LSPlt hook registration for keystore2 attestKey and generateKey, hook removal for non-target processes (restore original function pointers), and passthrough when activeKeyboxId is empty
- [ ] 26. Implement attestKey interception: read active keybox XML, construct certificate chain from CertificateChain, derive AttestationApplicationId extension from calling process package signature, integrate Latency_Equalizer wait before response return
- [ ] 27. Implement conditional debug logging in native hook: only log package name and elapsed time per attestation call when logLevel=DEBUG
- [ ] 28. Create `docs/TIMING_SIDE_CHANNEL.md` with detection principle (attested vs non-attested timing comparison), detection example (attested 0.932ms non-attested 1.068ms ratio 1.146x threshold > 1.1x → Positive), fundamental limitations (software cannot achieve perfect indistinguishability), and mitigation strategies (Jitter_Injection, CPU_Pinning, Pre_Warming, Latency_Equalizer) with effectiveness and limitations
- [ ] 29. Initialize test project: create package.json with vitest and fast-check dependencies, vitest.config.ts, and test utility generators (valid/invalid keybox XML generator, package name generator, config object generator, measurement array generator)
- [ ] 30. Write property test for CP-1 (Keybox Parser Round-Trip): for any valid keybox XML, parse(print(parse(xml))) equals parse(xml), minimum 100 iterations `[pbt]`
- [ ] 31. Write property test for CP-2 (Target_List Set Invariant): for any list and package name, adding results in size change of 0 or 1 and package is member, minimum 100 iterations `[pbt]`
- [ ] 32. Write property test for CP-3 (Latency_Equalizer Ratio Guarantee): for any T_n > 0 and threshold >= 1.01, adjusted T_a_simulated satisfies T_n/T_a_simulated <= threshold, minimum 100 iterations `[pbt]`
- [ ] 33. Write property test for CP-4 (Configuration_Store Idempotence): for any valid config, write twice produces same output as write once, minimum 100 iterations `[pbt]`
- [ ] 34. Write property test for CP-5 (Shell_Bridge Response Structure): for any command string, response has numeric status field, status=0 implies data field, status!=0 implies message field, minimum 100 iterations `[pbt]`
- [ ] 35. Write property test for CP-6 (Keybox_Store Filename Consistency): for any keybox content, stored filename equals SHA-256 hex digest of content, minimum 100 iterations `[pbt]`
- [ ] 36. Write property test for CP-7 (Target_List Import/Export Round-Trip): for any target list, export to target.txt then import into empty list equals original, minimum 100 iterations `[pbt]`
- [ ] 37. Write property test for CP-8 (Profiler Judgment Correctness): for any ratio and threshold, judgment is Positive iff ratio > threshold, minimum 100 iterations `[pbt]`
- [ ] 38. Write property test for CP-9 (Outlier Removal Correctness): for any array of N>=20 measurements, filtered result has size N - 2*floor(N*0.05) and contains only values between 5th and 95th percentiles, minimum 100 iterations `[pbt]`
- [ ] 39. Write property test for CP-10 (Jitter Injection Bounds): for any reference profile with stddev > 0, generated jitter absolute value is <= stddev, minimum 100 iterations `[pbt]`
- [ ] 40. Write property test for CP-11 (Keybox Parser Error Classification): for any XML missing required elements returns INVALID_KEYBOX_SCHEMA, for any XML with invalid PEM returns INVALID_PEM_ENCODING, minimum 100 iterations `[pbt]`
- [ ] 41. Write unit tests for config schema migration (v0→v1 field mapping, backup creation, missing fields get defaults)
- [ ] 42. Write unit tests for log rotation (size threshold detection, file rename, new file creation)
- [ ] 43. Write unit tests for command router (whitelist acceptance, unknown command rejection, JSON parsing, timeout handling)

## Task Dependency Graph

```json
{
  "waves": [
    [1],
    [2, 3, 4, 5, 6, 7, 14, 15, 23, 28, 29],
    [8, 9, 10, 24],
    [11, 12, 21, 41, 42],
    [13, 25],
    [16, 22, 26, 43],
    [17, 18, 19, 20, 27],
    [30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40]
  ]
}
```

## Notes

- ネイティブ Hook (Tasks 23-27) は TEESimulator の既存コードをベースとし、上流互換性を維持する構造とする
- シェルスクリプトは POSIX 互換を基本とするが、Android の `/system/bin/sh` (mksh) で動作確認する
- WebUI は Vanilla JavaScript で実装し、外部フレームワーク依存を排除する
- Property-based tests は JavaScript でロジックをモデル化し、fast-check で検証する
- `[pbt]` タグ付きタスクは property-based test タスクを示す
