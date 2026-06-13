# Real Fixtures Catalog (No Mocks)

This catalog lists **existing** files used as real fixtures for tests. Do not
introduce synthetic mocks for core behavior; prefer these artifacts.

## Manifests
- `gtbi.manifest.yaml` — Canonical module manifest (full real data set).

## Generated Artifacts (Real outputs)
- `scripts/generated/manifest_index.sh` — Deterministic module index used by selection logic.
- `scripts/generated/install_base.sh` — Generated module functions (base).
- `scripts/generated/install_shell.sh` — Generated module functions (shell).
- `scripts/generated/install_lang.sh` — Generated module functions (languages).
- `scripts/generated/install_cli.sh` — Generated module functions (CLI tools).
- `scripts/generated/install_agents.sh` — Generated module functions (agents).
- `scripts/generated/install_cloud.sh` — Generated module functions (cloud).
- `scripts/generated/install_db.sh` — Generated module functions (db).
- `scripts/generated/install_stack.sh` — Generated module functions (stack).
- `scripts/generated/install_tools.sh` — Generated module functions (tools).
- `scripts/generated/install_users.sh` — Generated module functions (users).
- `scripts/generated/install_gtbi.sh` — Generated module functions (gtbi).
- `scripts/generated/doctor_checks.sh` — Generated doctor checks list.

## Installer + Libs (Real logic under test)
- `install.sh` — Orchestrator entrypoint and CLI parsing.
- `scripts/lib/install_helpers.sh` — Selection + run helpers.
- `scripts/lib/contract.sh` — Module contract enforcement.
- `scripts/lib/security.sh` — Checksum verification logic.
- `scripts/preflight.sh` — Preflight validation script.

## E2E Harnesses (Real integration scripts)
- `tests/vm/test_install_ubuntu.sh` — Installer E2E (Docker).
- `tests/vm/test_gtbi_update.sh` — Update E2E (Docker).
- `tests/vm/resume_checks.sh` — Resume logic checks.

## Notes
- Generated artifacts should be regenerated via `bun run generate` before tests when manifest changes.
- Avoid “fake” YAMLs; if smaller fixtures are needed, derive them from real manifest subsets and commit them as real files.
