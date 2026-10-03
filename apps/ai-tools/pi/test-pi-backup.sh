#!/usr/bin/env bash
# Test the backup command only. Never run install.sh or use live Pi config.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

for command in python3 rsync jq; do
  command -v "$command" >/dev/null || fail "required command missing: $command"
done

[[ -x "$SCRIPT_DIR/backup.sh" ]] || fail "missing executable backup.sh"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

new_fixture() {
  local name="$1"
  fixture="$test_root/$name"
  module="$fixture/repo/apps/ai-tools/pi"
  home="$fixture/home"
  agent="$home/.pi/agent"
  config="$module/config"
  log="$fixture/backup.log"
  mkdir -p "$module" "$agent"
  cp "$REPO_ROOT/_helpers.sh" "$fixture/repo/_helpers.sh"
  cp "$SCRIPT_DIR/backup.sh" "$SCRIPT_DIR/prepare-backup.py" "$module/"
}

put() {
  mkdir -p "$(dirname "$agent/$1")"
  printf '%s\n' "$2" > "$agent/$1"
}

run_backup() {
  HOME="$home" PI_CODING_AGENT_DIR="$agent" /bin/bash "$module/backup.sh" > "$log" 2>&1
}

backup_succeeds() {
  if ! run_backup; then
    while IFS= read -r line; do printf '%s\n' "$line" >&2; done < "$log"
    fail "backup failed unexpectedly"
  fi
}

backup_fails() {
  if run_backup; then fail "unsafe backup succeeded"; fi
}

assert_file() {
  [[ -f "$1" ]] || fail "expected file: $1"
}

assert_absent() {
  [[ ! -e "$1" && ! -L "$1" ]] || fail "unexpected path: $1"
}

assert_json() {
  jq -e "$2" "$1" >/dev/null || fail "unexpected JSON in $1"
}

assert_no_text() {
  if grep -Fq -- "$2" "$1"; then fail "unexpected text in $1"; fi
}

captures_reusable_config() {
  put settings.json '{"defaultModel":"example","deviceId":"private-device","lastChangelogVersion":"1.0.0"}'
  put keybindings.json '{"app.session.new":"ctrl+n"}'
  local name
  for name in AGENTS.override.md AGENTS.md AGENTS.MD CLAUDE.md CLAUDE.MD SYSTEM.md APPEND_SYSTEM.md; do
    put "$name" 'user instructions'
  done
  for name in extensions/footer.ts skills/example/SKILL.md skills/example/references/guide.md prompts/review.md tests/footer.test.mjs; do
    put "$name" 'custom resource'
  done
  put extensions/footer/package.json '{}'
  put themes/custom.json '{}'
  for name in auth.json mcp-auth.json trust.json models-store.json sessions/session.jsonl install/runtime bin/pi backups/old.ts extensions/node_modules/dependency/index.js extensions/.env skills/example/.git/config prompts/.DS_Store; do
    put "$name" 'must not be committed'
  done
  backup_succeeds
  assert_json "$config/settings.json" '. == {"defaultModel":"example"}'
  assert_json "$config/keybindings.json" '. == {"app.session.new":"ctrl+n"}'
  for name in AGENTS.override.md AGENTS.md AGENTS.MD CLAUDE.md CLAUDE.MD SYSTEM.md APPEND_SYSTEM.md extensions/footer.ts extensions/footer/package.json skills/example/SKILL.md skills/example/references/guide.md prompts/review.md themes/custom.json tests/footer.test.mjs; do
    assert_file "$config/$name"
  done
  if grep -rq 'must not be committed' "$config"; then fail "runtime or dependency files leaked"; fi
}

redacts_model_credentials() {
  put models.json '{"providers":{"example":{"baseUrl":"https://example.com/v1","api":"openai-completions","apiKey":"sk-private-literal","headers":{"Authorization":"Bearer sk-header-literal"},"models":[{"id":"demo"}]}}}'
  backup_succeeds
  assert_json "$config/models.json" '.providers.example | .apiKey == "REDACTED_SET_THIS_SECRET_ON_RESTORE" and .headers.Authorization == "REDACTED_SET_THIS_SECRET_ON_RESTORE" and .baseUrl == "https://example.com/v1" and .models == [{"id":"demo"}]'
  assert_no_text "$config/models.json" 'sk-'
}

redacts_settings_credentials() {
  put settings.json '{"apiKey":"sk-settings-literal"}'
  backup_succeeds
  assert_json "$config/settings.json" '. == {"apiKey":"REDACTED_SET_THIS_SECRET_ON_RESTORE"}'
}

preserves_snapshot_on_invalid_json() {
  put settings.json '{"defaultModel":"good"}'
  backup_succeeds
  cp "$config/settings.json" "$fixture/previous.json"
  put models.json '{"invalid":"sensitive-value",'
  backup_fails
  cmp -s "$config/settings.json" "$fixture/previous.json" || fail "failed backup changed snapshot"
  assert_absent "$config/models.json"
  assert_no_text "$log" 'sensitive-value'
}

redacts_mcp_credentials() {
  put mcp.json '{"mcpServers":{"remote":{"url":"https://alice:url-password@example.com/mcp?api_key=query-secret&mode=tools","headers":{"X-Custom":"opaque-header","Authorization":"Bearer ${MCP_TOKEN}"},"oauth":{"clientSecret":"oauth-secret","clientId":"client-id"}},"local":{"command":"npx","args":["server","--api-key","argument-secret","--token=inline-secret","API_KEY=assignment-secret","--header","X-Custom: argument-header"],"env":{"CUSTOM_AUTH":"env-secret","API_KEY":"${TOOLS_KEY}"}}}}'
  backup_succeeds
  local value
  for value in alice url-password query-secret opaque-header oauth-secret argument-secret inline-secret assignment-secret argument-header env-secret; do
    assert_no_text "$config/mcp.json" "$value"
  done
  assert_json "$config/mcp.json" '.mcpServers | .remote.headers.Authorization == "Bearer ${MCP_TOKEN}" and .remote.oauth.clientId == "client-id" and .local.env.API_KEY == "${TOOLS_KEY}" and .local.command == "npx" and (.remote.url | contains("mode=tools"))'
}

refuses_known_secrets_in_source() {
  put settings.json '{"defaultModel":"good"}'
  backup_succeeds
  put settings.json '{"defaultModel":"changed"}'
  mkdir -p "$agent/extensions"
  printf 'const key = "sk-ant-%030d";\n' 0 > "$agent/extensions/unsafe.ts"
  backup_fails
  assert_json "$config/settings.json" '. == {"defaultModel":"good"}'
  assert_absent "$config/extensions/unsafe.ts"
  assert_no_text "$log" 'sk-ant-'
}

preserves_snapshot_without_python() {
  put settings.json '{"defaultModel":"good"}'
  backup_succeeds
  put settings.json '{"apiKey":"do-not-copy"}'
  mkdir -p "$fixture/bin"
  ln -s "$(command -v dirname)" "$fixture/bin/dirname"
  if HOME="$home" PI_CODING_AGENT_DIR="$agent" PATH="$fixture/bin" /bin/bash "$module/backup.sh" > "$log" 2>&1; then
    fail "backup succeeded without Python"
  fi
  assert_json "$config/settings.json" '. == {"defaultModel":"good"}'
}

refuses_resource_symlinks() {
  put settings.json '{"defaultModel":"good"}'
  backup_succeeds
  put auth.json '{"key":"do-not-follow"}'
  mkdir -p "$agent/extensions"
  ln -s "$agent/auth.json" "$agent/extensions/leak.ts"
  backup_fails
  assert_absent "$config/extensions/leak.ts"
  assert_json "$config/settings.json" '. == {"defaultModel":"good"}'
}

repeat_backup_is_stable() {
  put settings.json '{"defaultModel":"good"}'
  put prompts/review.md 'review'
  backup_succeeds
  cp "$config/settings.json" "$fixture/previous.json"
  # Staging and rsync may change mtimes differently on macOS and Linux.
  # Git tracks contents: identical input must produce identical snapshot bytes.
  touch -t 200001010000 "$config/settings.json"
  backup_succeeds
  cmp -s "$config/settings.json" "$fixture/previous.json" || fail "repeat backup changed settings contents"
  cmp -s "$config/prompts/review.md" "$agent/prompts/review.md" || fail "repeat backup changed resource contents"
  rm "$agent/prompts/review.md"
  backup_succeeds
  assert_absent "$config/prompts/review.md"
}

preserves_snapshot_when_agent_is_absent() {
  put settings.json '{"defaultModel":"good"}'
  backup_succeeds
  rm -rf "$agent"
  backup_succeeds
  assert_json "$config/settings.json" '. == {"defaultModel":"good"}'
}

preserves_manifest_dependencies() {
  put extensions/custom/package.json '{"dependencies":{"jsonwebtoken":"^9.0.0","token-tools":"^1.0.0","oauth":"^0.10.0"}}'
  backup_succeeds
  assert_json "$config/extensions/custom/package.json" '. == {"dependencies":{"jsonwebtoken":"^9.0.0","token-tools":"^1.0.0","oauth":"^0.10.0"}}'
}

redacts_package_url_credentials() {
  put settings.json '{"packages":["git:https://user:private-password@example.com/tools.git"]}'
  backup_succeeds
  assert_no_text "$config/settings.json" 'private-password'
  assert_json "$config/settings.json" '.packages[0] | contains("example.com/tools.git")'
}

reports_external_resources() {
  printf 'external source\n' > "$fixture/external.ts"
  jq -n --arg path "$fixture/external.ts" '{extensions:[$path]}' > "$agent/settings.json"
  backup_succeeds
  grep -q 'outside' "$log" || fail "external resource was not reported"
  assert_absent "$config/external.ts"
}

master_reaches_pi_backup() {
  grep -Fq '"$DOTFILES_DIR/apps/ai-tools/pi/backup.sh"' "$REPO_ROOT/backup.sh" || fail "master does not invoke Pi backup"
}

for test in captures_reusable_config redacts_model_credentials redacts_settings_credentials preserves_snapshot_on_invalid_json redacts_mcp_credentials refuses_known_secrets_in_source preserves_snapshot_without_python refuses_resource_symlinks repeat_backup_is_stable preserves_snapshot_when_agent_is_absent preserves_manifest_dependencies redacts_package_url_credentials reports_external_resources master_reaches_pi_backup; do
  new_fixture "$test"
  "$test"
  printf 'PASS: %s\n' "$test"
done
printf 'PASS: all 14 Pi backup tests\n'
