/**
 * Tests for GTBI Manifest Generator outputs
 * Related: bead dvt.2
 *
 * Validates that generated scripts match expected content from real fixtures.
 * Uses actual gtbi.manifest.yaml and validates against generated outputs.
 */

import { describe, test, expect, beforeAll } from 'bun:test';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { readFileSync, existsSync } from 'node:fs';
import { parseManifestFile } from './parser.js';
import {
  isOptionalVerifyCommand,
  stripOptionalVerifySuffix,
} from './generate.js';
import {
  getCategories,
  getModuleCategory,
  sortModulesByInstallOrder,
  getTransitiveDependencies,
} from './utils.js';
import type { Manifest, Module } from './types.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = resolve(__dirname, '../../..');
const MANIFEST_PATH = resolve(PROJECT_ROOT, 'gtbi.manifest.yaml');
const GENERATED_DIR = resolve(PROJECT_ROOT, 'scripts/generated');
const MANIFEST_INDEX_PATH = resolve(GENERATED_DIR, 'manifest_index.sh');

describe('Generator optional verify parsing', () => {
  test('strips optional true suffixes with trailing comments', () => {
    const command = 'ms doctor || true # optional until credentials are configured';

    expect(isOptionalVerifyCommand(command)).toBe(true);
    expect(stripOptionalVerifySuffix(command)).toBe('ms doctor');
  });

  test('leaves non-optional commands unchanged', () => {
    const command = 'if tool --version; then true; fi';

    expect(isOptionalVerifyCommand(command)).toBe(false);
    expect(stripOptionalVerifySuffix(command)).toBe(command);
  });
});

describe('Generated manifest_index.sh content', () => {
  let manifestIndexContent: string;
  let manifest: Manifest;

  beforeAll(() => {
    // Parse the real manifest
    const parseResult = parseManifestFile(MANIFEST_PATH);
    expect(parseResult.success).toBe(true);
    if (!parseResult.success || !parseResult.data) {
      throw new Error(`Failed to parse manifest: ${parseResult.error?.message}`);
    }
    manifest = parseResult.data;

    // Read the generated manifest_index.sh
    expect(existsSync(MANIFEST_INDEX_PATH)).toBe(true);
    manifestIndexContent = readFileSync(MANIFEST_INDEX_PATH, 'utf-8');
  });

  test('manifest_index.sh exists and is non-empty', () => {
    expect(manifestIndexContent.length).toBeGreaterThan(0);
  });

  test('contains auto-generated header', () => {
    expect(manifestIndexContent).toContain('AUTO-GENERATED FROM gtbi.manifest.yaml');
    expect(manifestIndexContent).toContain('DO NOT EDIT');
  });

  test('contains GTBI_MANIFEST_SHA256', () => {
    expect(manifestIndexContent).toContain('GTBI_MANIFEST_SHA256=');
    // SHA256 is 64 hex characters
    const sha256Match = manifestIndexContent.match(/GTBI_MANIFEST_SHA256="([a-f0-9]{64})"/);
    expect(sha256Match).not.toBeNull();
  });

  test('contains GTBI_MODULES_IN_ORDER array', () => {
    expect(manifestIndexContent).toContain('GTBI_MODULES_IN_ORDER=(');
  });

  test('all modules are in GTBI_MODULES_IN_ORDER', () => {
    for (const module of manifest.modules) {
      expect(manifestIndexContent).toContain(`"${module.id}"`);
    }
  });

  test('modules are in dependency-respecting order', () => {
    // Extract the order from the file
    const orderMatch = manifestIndexContent.match(
      /GTBI_MODULES_IN_ORDER=\(\s*([\s\S]*?)\s*\)/
    );
    expect(orderMatch).not.toBeNull();

    const orderContent = orderMatch![1];
    const moduleIds = orderContent
      .split('\n')
      .map((line) => line.trim())
      .filter((line) => line.startsWith('"') && line.endsWith('"'))
      .map((line) => line.slice(1, -1));

    // Verify each module appears after its dependencies
    const moduleIndex = new Map(moduleIds.map((id, idx) => [id, idx]));

    for (const module of manifest.modules) {
      if (module.dependencies) {
        const moduleIdx = moduleIndex.get(module.id);
        expect(moduleIdx).toBeDefined();

        for (const dep of module.dependencies) {
          const depIdx = moduleIndex.get(dep);
          expect(depIdx).toBeDefined();
          expect(depIdx!).toBeLessThan(moduleIdx!);
        }
      }
    }
  });

  test('contains GTBI_MODULE_PHASE associative array', () => {
    expect(manifestIndexContent).toContain('declare -gA GTBI_MODULE_PHASE=(');
  });

  test('all modules have phase entries', () => {
    for (const module of manifest.modules) {
      const expectedPhase = module.phase ?? 1;
      // Generator emits associative-array keys as `[module.id]` (unquoted, safe for our IDs).
      expect(manifestIndexContent).toContain(`['${module.id}']="${expectedPhase}"`);
    }
  });

  test('contains GTBI_MODULE_DEPS associative array', () => {
    expect(manifestIndexContent).toContain('declare -gA GTBI_MODULE_DEPS=(');
  });

  test('dependencies are correctly formatted', () => {
    for (const module of manifest.modules) {
      const deps = module.dependencies?.join(',') ?? '';
      // Generator emits associative-array keys as `[module.id]` (unquoted, safe for our IDs).
      expect(manifestIndexContent).toContain(`['${module.id}']="${deps}"`);
    }
  });

  test('contains GTBI_MODULE_FUNC associative array', () => {
    expect(manifestIndexContent).toContain('declare -gA GTBI_MODULE_FUNC=(');
  });

  test('function names follow convention', () => {
    for (const module of manifest.modules) {
      const expectedFunc = `install_${module.id.replace(/\./g, '_')}`;
      // Generator emits associative-array keys as `[module.id]` (unquoted, safe for our IDs).
      expect(manifestIndexContent).toContain(`['${module.id}']="${expectedFunc}"`);
    }
  });

  test('contains GTBI_MODULE_CATEGORY associative array', () => {
    expect(manifestIndexContent).toContain('declare -gA GTBI_MODULE_CATEGORY=(');
  });

  test('categories are correctly derived from module IDs', () => {
    for (const module of manifest.modules) {
      const category = module.category ?? getModuleCategory(module.id);
      // Generator emits associative-array keys as `[module.id]` (unquoted, safe for our IDs).
      expect(manifestIndexContent).toContain(`['${module.id}']="${category}"`);
    }
  });

  test('contains GTBI_MODULE_TAGS associative array', () => {
    expect(manifestIndexContent).toContain('declare -gA GTBI_MODULE_TAGS=(');
  });

  test('contains GTBI_MODULE_DEFAULT associative array', () => {
    expect(manifestIndexContent).toContain('declare -gA GTBI_MODULE_DEFAULT=(');
  });

  test('default values match manifest', () => {
    for (const module of manifest.modules) {
      const expectedDefault = module.enabled_by_default ? '1' : '0';
      // Generator emits associative-array keys as `[module.id]` (unquoted, safe for our IDs).
      expect(manifestIndexContent).toContain(`['${module.id}']="${expectedDefault}"`);
    }
  });

  test('contains GTBI_MANIFEST_INDEX_LOADED flag', () => {
    expect(manifestIndexContent).toContain('GTBI_MANIFEST_INDEX_LOADED=true');
  });
});

describe('Generated category scripts exist', () => {
  let manifest: Manifest;

  beforeAll(() => {
    const parseResult = parseManifestFile(MANIFEST_PATH);
    if (parseResult.success && parseResult.data) {
      manifest = parseResult.data;
    }
  });

  test('category install scripts exist for each category', () => {
    const categories = getCategories(manifest);

    for (const category of categories) {
      const categoryPath = resolve(GENERATED_DIR, `install_${category}.sh`);
      expect(existsSync(categoryPath)).toBe(true);
    }
  });

  test('doctor_checks.sh exists', () => {
    const doctorPath = resolve(GENERATED_DIR, 'doctor_checks.sh');
    expect(existsSync(doctorPath)).toBe(true);
  });

  test('install_all.sh exists', () => {
    const installAllPath = resolve(GENERATED_DIR, 'install_all.sh');
    expect(existsSync(installAllPath)).toBe(true);
  });
});

describe('Generated verified installer args', () => {
  test('generated scripts detect the target user instead of hardcoding ubuntu', () => {
    const stackPath = resolve(GENERATED_DIR, 'install_stack.sh');
    expect(existsSync(stackPath)).toBe(true);
    const stackContent = readFileSync(stackPath, 'utf-8');

    expect(stackContent).toContain('_GTBI_DETECTED_USER="${SUDO_USER:-}"');
    expect(stackContent).toContain('_GTBI_DETECTED_USER="$(gtbi_generated_resolve_current_user 2>/dev/null || true)"');
    expect(stackContent).not.toContain('_GTBI_DETECTED_USER="${SUDO_USER:-$(whoami)}"');
    expect(stackContent).not.toContain('TARGET_USER="${TARGET_USER:-ubuntu}"');
  });

  test('verified-installer guards do not depend on external grep', () => {
    const stackPath = resolve(GENERATED_DIR, 'install_stack.sh');
    const agentsPath = resolve(GENERATED_DIR, 'install_agents.sh');
    expect(existsSync(stackPath)).toBe(true);
    expect(existsSync(agentsPath)).toBe(true);
    const generatedContent = [
      readFileSync(stackPath, 'utf-8'),
      readFileSync(agentsPath, 'utf-8'),
    ].join('\n');

    expect(generatedContent).toContain('known_installers_decl="$(declare -p KNOWN_INSTALLERS 2>/dev/null || true)"');
    expect(generatedContent).toContain('if [[ "$known_installers_decl" == declare\\ -A* ]]; then');
    expect(generatedContent).not.toContain("declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'");
  });

  test('generated direct-exec headers resolve TARGET_HOME via helpers and fail closed', () => {
    const stackPath = resolve(GENERATED_DIR, 'install_stack.sh');
    expect(existsSync(stackPath)).toBe(true);
    const stackContent = readFileSync(stackPath, 'utf-8');

    expect(stackContent).toContain('if declare -f _gtbi_resolve_target_home >/dev/null 2>&1; then');
    expect(stackContent).toContain('TARGET_HOME="$(_gtbi_resolve_target_home "${TARGET_USER}" "$_GTBI_EXPLICIT_TARGET_HOME" || true)"');
    expect(stackContent).toContain(
      'log_error "Invalid TARGET_HOME for \'${TARGET_USER}\': ${TARGET_HOME:-<empty>} (must be an absolute path and cannot be \'/\')"'
    );
    expect(stackContent).not.toContain('TARGET_HOME="/home/${TARGET_USER}"');
    expect(stackContent).not.toContain('TARGET_HOME="/home/${TARGET_USER:-ubuntu}"');
    expect(stackContent).toContain("printf '%s\\n'");
    expect(stackContent).not.toContain("printf '%s\n'");
  });

  test('stack.dolt verified installer pipes through run_as_root_shell (not bare bash)', () => {
    const stackPath = resolve(GENERATED_DIR, 'install_stack.sh');
    expect(existsSync(stackPath)).toBe(true);
    const stackContent = readFileSync(stackPath, 'utf-8');

    // Must use run_as_root_shell for sudo elevation, not bare bash
    expect(stackContent).toContain(
      'verify_checksum "$url" "$expected_sha256" "$tool" | run_as_root_shell'
    );
    expect(stackContent).not.toContain(
      'verify_checksum "$url" "$expected_sha256" "$tool" | bash'
    );
  });

  test('agent wrapper/link install heredocs include primary-bin helpers in child shell', () => {
    const agentsPath = resolve(GENERATED_DIR, 'install_agents.sh');
    expect(existsSync(agentsPath)).toBe(true);
    const agentsContent = readFileSync(agentsPath, 'utf-8');

    const generatedPreludeIndex = agentsContent.indexOf('# Generated helper functions used by this child shell.');
    const preludeIndex = agentsContent.indexOf('# Primary-bin helper functions used by this child shell.');
    const linkIndex = agentsContent.indexOf('gtbi_link_primary_bin_command "$claude_candidate" "claude"');
    const installIndex = agentsContent.indexOf('gtbi_install_executable_into_primary_bin "$wrapper_tmp" "codex"');

    expect(generatedPreludeIndex).toBeGreaterThanOrEqual(0);
    expect(preludeIndex).toBeGreaterThanOrEqual(0);
    expect(preludeIndex).toBeGreaterThan(generatedPreludeIndex);
    expect(linkIndex).toBeGreaterThan(preludeIndex);
    expect(installIndex).toBeGreaterThan(preludeIndex);
    expect(agentsContent).toContain('gtbi_generated_system_binary_path() {');
    expect(agentsContent).toContain('gtbi_child_primary_bin_dir() {');
    expect(agentsContent).toContain('gtbi_child_primary_bin_tool_path() {');
    expect(agentsContent).toContain('mkdir_bin="$(gtbi_child_primary_bin_tool_path mkdir)" || return 1');
    expect(agentsContent).toContain('ln_bin="$(gtbi_child_primary_bin_tool_path ln)" || return 1');
    expect(agentsContent).toContain('install_bin="$(gtbi_child_primary_bin_tool_path install)" || return 1');
    expect(agentsContent).toContain('Root primary bin command must be an absolute trusted path');
    expect(agentsContent).toContain('GTBI_BIN_DIR is unset and HOME is not a usable absolute path');
    expect(agentsContent).not.toContain('${GTBI_BIN_DIR:-${HOME:-}/.local/bin}');
    expect(agentsContent).not.toContain('gtbi_child_run_root_bin_command mkdir -p');
    expect(agentsContent).not.toContain('gtbi_child_run_root_bin_command ln -sf');
    expect(agentsContent).not.toContain('gtbi_child_run_root_bin_command install -m 0755');
    expect(agentsContent).toContain('gtbi_install_executable_into_primary_bin() {');
    expect(agentsContent).toContain('gtbi_link_primary_bin_command() {');
  });

  test('multi-line install summaries skip leading helper function bodies', () => {
    const shellPath = resolve(GENERATED_DIR, 'install_shell.sh');
    expect(existsSync(shellPath)).toBe(true);
    const shellContent = readFileSync(shellPath, 'utf-8');

    expect(shellContent).not.toContain('dry-run: install: profile_path_has_fragment() {');
    expect(shellContent).not.toContain('install command failed: profile_path_has_fragment() {');
    expect(shellContent).toContain('dry-run: install: if [[ ! -f ~/.profile ]]; then');
    expect(shellContent).toContain('install command failed: if [[ ! -f ~/.profile ]]; then');
    expect(shellContent).toContain('dry-run: install: if [[ ! -f ~/.zprofile ]]; then');
    expect(shellContent).toContain('install command failed: if [[ ! -f ~/.zprofile ]]; then');
    expect(shellContent).not.toContain('dry-run: install: exit 1 (target_user)');
    expect(shellContent).not.toContain('shell.omz: install command failed: exit 1');
    expect(shellContent).toContain(
      'dry-run: install: if [[ -f ~/.zshrc ]] && ! gtbi_zshrc_is_managed_loader ~/.zshrc; then'
    );
    expect(shellContent).toContain(
      'shell.omz: install command failed: if [[ -f ~/.zshrc ]] && ! gtbi_zshrc_is_managed_loader ~/.zshrc; then'
    );
  });

  test('network modules emit post-install messages into generated installers', () => {
    const networkPath = resolve(GENERATED_DIR, 'install_network.sh');
    expect(existsSync(networkPath)).toBe(true);
    const networkContent = readFileSync(networkPath, 'utf-8');

    expect(networkContent).toContain(
      'log_info "Tailscale installed! To connect your VPS to your Tailscale network:"'
    );
    expect(networkContent).toContain(
      'log_info "SSH keepalive configured! Your connections will now survive VPN/NAT timeouts."'
    );
  });

  test('workspace agents alias checks require active alias lines', () => {
    const gtbiPath = resolve(GENERATED_DIR, 'install_gtbi.sh');
    expect(existsSync(gtbiPath)).toBe(true);
    const gtbiContent = readFileSync(gtbiPath, 'utf-8');

    expect(gtbiContent).toContain('gtbi_has_active_agents_alias() {');
    expect(gtbiContent).not.toContain('grep -q "alias agents=" ~/.zshrc.local');
    expect(gtbiContent).toContain(
      'dry-run: install: if ! gtbi_has_active_agents_alias ~/.zshrc.local; then'
    );
    expect(gtbiContent).toContain(
      'dry-run: verify: gtbi_has_active_agents_alias ~/.zshrc.local || gtbi_has_active_agents_alias ~/.zshrc'
    );
  });
});

describe('Generated filesystem script hardening', () => {
  let filesystemContent: string;

  beforeAll(() => {
    const filesystemPath = resolve(GENERATED_DIR, 'install_filesystem.sh');
    expect(existsSync(filesystemPath)).toBe(true);
    filesystemContent = readFileSync(filesystemPath, 'utf-8');
  });

  test('fails closed when TARGET_HOME cannot be resolved instead of guessing /home/$TARGET_USER', () => {
    expect(filesystemContent).not.toContain('target_home="/home/${TARGET_USER:-ubuntu}"');
    expect(filesystemContent).toContain(
      "ERROR: Unable to resolve TARGET_HOME for '${TARGET_USER:-ubuntu}'; export TARGET_HOME explicitly"
    );
  });

  test('prefers trusted passwd home and rejects inherited TARGET_HOME fallback', () => {
    const trustedHomeIndex = filesystemContent.indexOf(
      'target_home="$(gtbi_generated_passwd_home_from_entry "$_gtbi_passwd_entry" 2>/dev/null || true)"'
    );

    expect(filesystemContent).toContain('target_home=""');
    expect(filesystemContent).toContain('explicit_target_home="${TARGET_HOME:-}"');
    expect(filesystemContent).not.toContain('if [[ -z "$target_home" && -n "$explicit_target_home" ]]; then');
    expect(filesystemContent).not.toContain('target_home="$explicit_target_home"');
    expect(filesystemContent).not.toContain('target_home="${TARGET_HOME:-}"\nif [[ -z "$target_home" ]]; then');
    expect(filesystemContent).not.toContain('target_home="${TARGET_HOME%/}"');
    expect(trustedHomeIndex).toBeGreaterThanOrEqual(0);
  });

  test('direct generated installers repair TARGET_HOME without inherited fallback', () => {
    const resolvedHomeIndex = filesystemContent.indexOf(
      '_GTBI_RESOLVED_TARGET_HOME="$(_gtbi_resolve_target_home "${TARGET_USER}" "$_GTBI_EXPLICIT_TARGET_HOME" || true)"'
    );

    expect(filesystemContent).toContain('_GTBI_EXPLICIT_TARGET_HOME="${TARGET_HOME:-}"');
    expect(filesystemContent).toContain('_GTBI_RESOLVED_TARGET_HOME=""');
    expect(filesystemContent).toContain('if [[ -n "$_GTBI_RESOLVED_TARGET_HOME" ]]; then');
    expect(filesystemContent).toContain('TARGET_HOME="${_GTBI_RESOLVED_TARGET_HOME%/}"');
    expect(filesystemContent).not.toMatch(/^\s*elif \[\[ -n "\$_GTBI_EXPLICIT_TARGET_HOME" \]\]; then$/m);
    expect(filesystemContent).not.toMatch(/^\s*TARGET_HOME="\$_GTBI_EXPLICIT_TARGET_HOME"$/m);
    expect(filesystemContent).not.toMatch(/^\s*TARGET_HOME="\$\{TARGET_HOME%\/}"$/m);
    expect(resolvedHomeIndex).toBeGreaterThanOrEqual(0);
  });

  test('does not recursively chown /data (avoid over-broad ownership changes)', () => {
    expect(filesystemContent).not.toContain('chown -R');
    expect(filesystemContent).not.toMatch(/chown\s+-R[^\n]*\s\/data\b/);
  });

  test('refuses symlinked /data paths (hardening against symlink tricks)', () => {
    expect(filesystemContent).toContain('Refusing to use symlinked path');
    expect(filesystemContent).toContain('for p in /data /data/projects /data/cache; do');
    expect(filesystemContent).toContain('if [[ -e "$p" && -L "$p" ]]; then');
  });

  test('uses no-dereference recursive chown for the GTBI dir', () => {
    expect(filesystemContent).toContain('chown -hR');
  });

  test('generated helper functions are in scope for child-shell heredocs', () => {
    expect(filesystemContent).toContain('# Generated helper functions used by this child shell.');
    expect(filesystemContent).toContain('gtbi_generated_system_binary_path() {');
    expect(filesystemContent).toContain('*[!A-Za-z0-9._+-]*)');
    expect(filesystemContent).toContain(
      '_gtbi_passwd_entry="$(gtbi_generated_getent_passwd_entry "${TARGET_USER:-ubuntu}" 2>/dev/null || true)"'
    );
  });
});

describe('doctor_checks.sh content', () => {
  let doctorContent: string;
  let manifest: Manifest;

  beforeAll(() => {
    const parseResult = parseManifestFile(MANIFEST_PATH);
    if (parseResult.success && parseResult.data) {
      manifest = parseResult.data;
    }

    const doctorPath = resolve(GENERATED_DIR, 'doctor_checks.sh');
    doctorContent = readFileSync(doctorPath, 'utf-8');
  });

  test('contains MANIFEST_CHECKS array', () => {
    expect(doctorContent).toContain('declare -a MANIFEST_CHECKS=(');
  });

  test('contains run_manifest_checks function', () => {
    expect(doctorContent).toContain('run_manifest_checks()');
  });

  test('all modules have at least one verify check', () => {
    for (const module of manifest.modules) {
      // Each module should have entries in the checks
      expect(doctorContent).toContain(module.id);
    }
  });

  test('uses tab delimiter for check entries', () => {
    // The format is: ID<TAB>DESCRIPTION<TAB>CHECK_COMMAND<TAB>REQUIRED/OPTIONAL<TAB>RUN_AS
    // Tab character should be present in the entries
    expect(doctorContent).toContain('\\t');
  });

  test('multiline verify commands are encoded as single-line records', () => {
    // lang.nvm verify is a YAML literal block (multi-line). The generator must encode it
    // so the MANIFEST_CHECKS record stays on one line and can be parsed via read/IFS.
    const nvmLine = doctorContent.match(/^    "lang\.nvm[^\n]*"$/m);
    expect(nvmLine).not.toBeNull();
    expect(nvmLine![0]).toContain('\\\\n');
  });

  test('includes run_as context for generated checks', () => {
    expect(doctorContent).toMatch(/lang\.bun[^\n]*\ttarget_user"/);
    expect(doctorContent).toMatch(/base\.system\.1[^\n]*\troot"/);
  });

  test('generated manifest-check helper uses hardened target PATH ordering', () => {
    expect(doctorContent).toContain('local system_path_prefix="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin"');
    expect(doctorContent).toContain('local -a target_path_entries=()');
    expect(doctorContent).toContain('target_path_prefix=$(IFS=:; echo "${target_path_entries[*]}")');
    expect(doctorContent).toContain('target_path="$target_path_prefix${PATH:+:$PATH}"');
  });

  test('run_manifest_check_command resolves target homes without /home guesses', () => {
    expect(doctorContent).toContain('resolved_target_home="$(_gtbi_resolve_target_home "$target_user" "$explicit_target_home" || true)"');
    expect(doctorContent).not.toContain('target_home="/home/$target_user"');
    expect(doctorContent).toContain(
      'log_error "Invalid TARGET_HOME for \'$target_user\': ${target_home:-<empty>} (must be an absolute path and cannot be \'/\')"'
    );
  });

  test('run_manifest_check_command repairs target_home without inherited fallback', () => {
    const resolvedHomeIndex = doctorContent.indexOf(
      'resolved_target_home="$(_gtbi_resolve_target_home "$target_user" "$explicit_target_home" || true)"'
    );

    expect(doctorContent).toContain('local explicit_target_home=""');
    expect(doctorContent).toContain('local resolved_target_home=""');
    expect(doctorContent).toContain('explicit_target_home="$target_home"');
    expect(doctorContent).toContain('if [[ -n "$resolved_target_home" ]]; then');
    expect(doctorContent).toContain('target_home="${resolved_target_home%/}"');
    expect(doctorContent).not.toContain('elif [[ -n "$explicit_target_home" ]]; then');
    expect(doctorContent).not.toContain('target_home="$explicit_target_home"');
    expect(doctorContent).not.toContain('target_home="${target_home%/}"');
    expect(doctorContent).not.toContain('if [[ -z "$target_home" ]]; then\n        if declare -f _gtbi_resolve_target_home');
    expect(resolvedHomeIndex).toBeGreaterThanOrEqual(0);
  });

  test('target_user doctor checks receive TARGET_USER and TARGET_HOME env', () => {
    expect(doctorContent).toContain(
      '"$env_bin" TARGET_USER="$target_user" TARGET_HOME="$target_home" HOME="$target_home" PATH="$target_path" "$bash_bin" -o pipefail -c "$cmd"'
    );
  });

  test('root doctor checks still run when TARGET_HOME is unresolved', () => {
    expect(doctorContent).toContain(
      '"$sudo_bin" -n "$env_bin" TARGET_USER="$target_user" PATH="$system_path_prefix" "$bash_bin" -o pipefail -c "$cmd"'
    );
    expect(doctorContent).not.toContain(
      'root)\n            if [[ -z "$target_home" ]] || [[ "$target_home" != /* ]] || [[ "$target_home" == "/" ]]; then'
    );
  });

  test('doctor checks inject generated helpers into child bash commands that need them', () => {
    expect(doctorContent).toContain('if [[ "$cmd" == *"gtbi_generated_"* ]]; then');
    expect(doctorContent).toContain(
      'helper_prelude="$(declare -f gtbi_generated_system_binary_path gtbi_generated_resolve_current_user gtbi_generated_getent_passwd_entry gtbi_generated_passwd_home_from_entry 2>/dev/null || true)"'
    );
    expect(doctorContent).toContain('cmd="${helper_prelude}"$\'\\n\'"${cmd}"');
  });
});

describe('Utils: sortModulesByInstallOrder', () => {
  let manifest: Manifest;

  beforeAll(() => {
    const parseResult = parseManifestFile(MANIFEST_PATH);
    if (parseResult.success && parseResult.data) {
      manifest = parseResult.data;
    }
  });

  test('returns all modules', () => {
    const sorted = sortModulesByInstallOrder(manifest);
    expect(sorted.length).toBe(manifest.modules.length);
  });

  test('dependencies come before dependents', () => {
    const sorted = sortModulesByInstallOrder(manifest);
    const indexMap = new Map(sorted.map((m, i) => [m.id, i]));

    for (const module of manifest.modules) {
      if (module.dependencies) {
        const moduleIdx = indexMap.get(module.id)!;
        for (const dep of module.dependencies) {
          const depIdx = indexMap.get(dep);
          expect(depIdx).toBeDefined();
          expect(depIdx!).toBeLessThan(moduleIdx);
        }
      }
    }
  });

  test('respects phase ordering', () => {
    const sorted = sortModulesByInstallOrder(manifest);

    // Group by phase
    const phaseGroups = new Map<number, Module[]>();
    for (const module of sorted) {
      const phase = module.phase ?? 1;
      const group = phaseGroups.get(phase) ?? [];
      group.push(module);
      phaseGroups.set(phase, group);
    }

    // Phases should appear in order
    let lastPhase = 0;
    for (const module of sorted) {
      const phase = module.phase ?? 1;
      expect(phase).toBeGreaterThanOrEqual(lastPhase);
      lastPhase = phase;
    }
  });
});

describe('Utils: getTransitiveDependencies', () => {
  let manifest: Manifest;

  beforeAll(() => {
    const parseResult = parseManifestFile(MANIFEST_PATH);
    if (parseResult.success && parseResult.data) {
      manifest = parseResult.data;
    }
  });

  test('returns empty for module with no dependencies', () => {
    const deps = getTransitiveDependencies(manifest, 'base.system');
    // base.system typically has no dependencies
    const baseModule = manifest.modules.find((m) => m.id === 'base.system');
    if (!baseModule?.dependencies?.length) {
      expect(deps.length).toBe(0);
    }
  });

  test('includes all transitive dependencies', () => {
    // Find a module with nested dependencies
    // agents.codex -> lang.bun -> base.system
    const codexDeps = getTransitiveDependencies(manifest, 'agents.codex');

    // Should include lang.bun and base.system
    const depIds = codexDeps.map((d) => d.id);
    expect(depIds).toContain('lang.bun');
    expect(depIds).toContain('base.system');
  });

  test('handles diamond dependencies without duplicates', () => {
    // Find any module that has shared dependencies
    const allDeps = getTransitiveDependencies(manifest, 'stack.ultimate_bug_scanner');
    const depIds = allDeps.map((d) => d.id);

    // No duplicates
    const uniqueIds = new Set(depIds);
    expect(uniqueIds.size).toBe(depIds.length);
  });

  test('returns empty for non-existent module', () => {
    const deps = getTransitiveDependencies(manifest, 'nonexistent.module');
    expect(deps.length).toBe(0);
  });
});

describe('Utils: getCategories', () => {
  let manifest: Manifest;

  beforeAll(() => {
    const parseResult = parseManifestFile(MANIFEST_PATH);
    if (parseResult.success && parseResult.data) {
      manifest = parseResult.data;
    }
  });

  test('returns all unique categories', () => {
    const categories = getCategories(manifest);

    // Expected categories based on manifest
    const expectedCategories = ['base', 'users', 'filesystem', 'shell', 'cli', 'network', 'lang', 'tools', 'agents', 'stack', 'gtbi'];

    for (const cat of expectedCategories) {
      expect(categories).toContain(cat);
    }
  });

  test('returns no duplicates', () => {
    const categories = getCategories(manifest);
    const uniqueCategories = new Set(categories);
    expect(uniqueCategories.size).toBe(categories.length);
  });
});

describe('Generated script headers', () => {
  test('all generated scripts have consistent header', () => {
    const categories = ['base', 'lang', 'agents', 'stack'];

    for (const category of categories) {
      const scriptPath = resolve(GENERATED_DIR, `install_${category}.sh`);
      if (existsSync(scriptPath)) {
        const content = readFileSync(scriptPath, 'utf-8');

        // Check for standard header elements
        expect(content).toContain('#!/usr/bin/env bash');
        expect(content).toContain('AUTO-GENERATED');
        expect(content).toContain('set -euo pipefail');
      }
    }
  });

  test('generated scripts source logging.sh', () => {
    const scriptPath = resolve(GENERATED_DIR, 'install_lang.sh');
    if (existsSync(scriptPath)) {
      const content = readFileSync(scriptPath, 'utf-8');
      expect(content).toContain('source "$GTBI_GENERATED_SCRIPT_DIR/../lib/logging.sh"');
    }
  });

  test('generated scripts source install_helpers.sh', () => {
    const scriptPath = resolve(GENERATED_DIR, 'install_agents.sh');
    if (existsSync(scriptPath)) {
      const content = readFileSync(scriptPath, 'utf-8');
      expect(content).toContain('source "$GTBI_GENERATED_SCRIPT_DIR/../lib/install_helpers.sh"');
    }
  });
});
