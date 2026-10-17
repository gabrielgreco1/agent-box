# T2-10 Vault, catalog and legacy JSON importer

Files in this folder come from `AGENTBOX_EVIDENCE_DIR=<this folder> swift test --filter T210EvidenceTests`, run against the real user data, read-only.

- `catalog-dry-run.md`: real `~/.claude`, `~/.agents`, `~/.codex` and installed plugins; names and counts only.
- `legacy-importer-dry-run.md`: real `~/Library/Application Support/AgentBox` JSONs; counts only, with source hash before and after (unchanged).

## Verification (2026-10-17)

- `scripts/gen.sh`, `scripts/build.sh`, `scripts/lint.sh`: OK.
- `swift test`: 944 tests; the only failures in the full run were two timing tests under load (`TooltipPolicyTests`, `LoginShellEnvTests`), which pass when run alone.
- No test touches the login Keychain: the vault uses `InMemoryMasterKeyBackend`; the real `SystemKeychainBackend` is compiled but not exercised.

## Decisions

- Migration `v4_vault_catalog` only adds columns (secret kind/scope/delivery/expires_at/imported_from; catalog_item scope/mtime/frontmatter_json/parse_error/shadowed_by).
- Key rotation re-derives a new HKDF version (`secret-v<N>`) from the same master key and re-encrypts all rows in one transaction, so the Keychain item never changes.
- Env injection accepts only `profileEnv` secrets; `sidecarOnly` and `boxFileReadOnly` secrets can only be written as a `0400` file.
- The catalog watch uses kqueue per directory (rebuilt after each refresh) with 1 s debounce; an in-place write to an existing file without a rename is only seen on the next refresh.

## Not done

- No UI. No wiring of the vault into `LaunchService`/terminal create yet (`LaunchPlan.injectingSecrets` and `SecretVault.injection(profileID:sessionID:)` are ready).
- Importer: worktree mapping for imported sessions (git cwd becomes a `folder` session in a `git` project), `browser-computers.json` to orphan `computer` rows (counted as `computers.deferred`, T3-01), skills outside the standard roots (counted, not indexed).
- No `TODO` for T2-10 or a Zyte key store existed in the code at this base (proxy `secret_id` is a plain column); the Vault exposes `create(kind: .proxyCredential, delivery: .sidecarOnly)` for T3-02 to use.
- OpenCode agent folders and `commands/` of plugins are not indexed.
