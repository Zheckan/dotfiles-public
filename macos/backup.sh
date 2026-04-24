#!/usr/bin/env bash
# macOS defaults backup — auto-discovers settings from shell history,
# appends new ones to defaults.sh, and snapshots current system values.
source "$(cd "$(dirname "$0")/.." && pwd)/_helpers.sh"

log_section "macOS Defaults — Backup"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULTS_SH="$SCRIPT_DIR/defaults.sh"
SNAPSHOT="$SCRIPT_DIR/defaults-snapshot.txt"

# ── Helper: generate a defaults write command from current system ─
# Uses `defaults read-type` to detect type, `defaults read` for value.
# Returns empty if the key doesn't exist or has a complex type.
build_write_cmd() {
  local prefix="$1"   # "defaults write" or "defaults -currentHost write"
  local domain="$2"
  local key="$3"

  local type_output
  if [[ "$prefix" == *"-currentHost"* ]]; then
    type_output=$(defaults -currentHost read-type "$domain" "$key" 2>/dev/null) || return
  else
    type_output=$(defaults read-type "$domain" "$key" 2>/dev/null) || return
  fi

  local type_flag
  case "${type_output#Type is }" in
    boolean)    type_flag="-bool" ;;
    integer)    type_flag="-int" ;;
    float)      type_flag="-float" ;;
    string)     type_flag="-string" ;;
    *)          return ;;  # skip array, dict, data
  esac

  local value
  if [[ "$prefix" == *"-currentHost"* ]]; then
    value=$(defaults -currentHost read "$domain" "$key" 2>/dev/null) || return
  else
    value=$(defaults read "$domain" "$key" 2>/dev/null) || return
  fi

  # Format value for the write command
  case "$type_flag" in
    -bool)   [[ "$value" == "1" ]] && value="true" || value="false" ;;
    -string) value="\"$value\"" ;;
  esac

  echo "$prefix $domain $key $type_flag $value"
}

# ── Step 1: Discover new settings from shell history ──────────────
discover_new_defaults() {
  local history_file="$HOME/.zsh_history"
  [[ -f "$history_file" ]] || return 0

  local new_count=0
  local tmpfile
  tmpfile=$(mktemp)

  # Extract defaults write commands, split multiline, deduplicate
  grep 'defaults.*write' "$history_file" \
    | sed 's/^: [0-9]*:[0-9]*;//' \
    | tr '\\' ' ' \
    | tr ';' '\n' \
    | grep -E '^\s*defaults\s+' \
    | sed 's/^[[:space:]]*//' \
    | sed 's/[[:space:]]*$//' \
    | sort -u > "$tmpfile"

  # Collect new commands to insert (before killall line)
  local new_cmds=()

  while IFS= read -r cmd; do
    # Skip complex commands
    echo "$cmd" | grep -qE '\-dict-add|delete|\$|`|\(' && continue

    local domain="" key="" is_currenthost=false prefix="defaults write"

    if echo "$cmd" | grep -q '\-currentHost'; then
      is_currenthost=true
      prefix="defaults -currentHost write"
      local rest
      rest=$(echo "$cmd" | sed 's/defaults[[:space:]]*-currentHost[[:space:]]*write[[:space:]]*//')
      domain=$(echo "$rest" | awk '{print $1}')
      key=$(echo "$rest" | awk '{print $2}')
      [[ "$domain" == "-globalDomain" ]] && domain="NSGlobalDomain"
    else
      local rest
      rest=$(echo "$cmd" | sed 's/defaults[[:space:]]*write[[:space:]]*//')
      domain=$(echo "$rest" | awk '{print $1}')
      if [[ "$domain" == "-g" ]]; then
        domain="NSGlobalDomain"
        key=$(echo "$rest" | awk '{print $2}')
      else
        key=$(echo "$rest" | awk '{print $2}')
      fi
    fi

    # Skip invalid entries
    [[ -z "$domain" || -z "$key" ]] && continue
    [[ "$key" == -* ]] && continue

    # Skip if this key is already tracked in defaults.sh
    grep -q "$key" "$DEFAULTS_SH" 2>/dev/null && continue

    # Build write command with current system value
    local write_cmd
    write_cmd=$(build_write_cmd "$prefix" "$domain" "$key") || continue
    [[ -z "$write_cmd" ]] && continue

    # Deduplicate (same domain+key may appear with different values in history)
    local already_added=false
    for existing in "${new_cmds[@]}"; do
      if echo "$existing" | grep -q "$key"; then
        already_added=true
        break
      fi
    done
    [[ "$already_added" == true ]] && continue

    new_cmds+=("$write_cmd")
    new_count=$((new_count + 1))
    log_info "Discovered: $write_cmd"

  done < "$tmpfile"
  rm -f "$tmpfile"

  # Insert new commands before the killall line
  if [[ ${#new_cmds[@]} -gt 0 ]]; then
    local tmpsh
    tmpsh=$(mktemp)

    # Write insert block to a temp file
    local insert_file
    insert_file=$(mktemp)
    {
      echo ""
      echo "# Auto-discovered from shell history"
      for cmd in "${new_cmds[@]}"; do
        echo "$cmd"
      done
      echo ""
    } > "$insert_file"

    # Insert before "# Kill affected apps" or append at end
    if grep -q "^# Kill affected apps" "$DEFAULTS_SH"; then
      while IFS= read -r line; do
        if [[ "$line" == "# Kill affected apps" ]]; then
          cat "$insert_file"
        fi
        echo "$line"
      done < "$DEFAULTS_SH" > "$tmpsh"
      mv "$tmpsh" "$DEFAULTS_SH"
    else
      cat "$insert_file" >> "$DEFAULTS_SH"
    fi

    rm -f "$insert_file" "$tmpsh"
    log_info "Added $new_count new settings to defaults.sh"
  fi
}

# ── Step 2: Monitor tracked domains for GUI-changed settings ──────
# Fully scans small, user-focused domains for new settings.
# Large/noisy domains (NSGlobalDomain, Finder) rely on history + sync_values.
monitor_domains() {
  # Domains safe to fully scan (small, mostly user preferences)
  local monitored_domains=(
    com.apple.dock
    com.apple.WindowManager
    com.apple.screencapture
    com.apple.AppleMultitouchTrackpad
  )

  # Keys that are system-managed noise (timestamps, counters, internal state)
  local noise_pattern='mod-count|last-analytics|lastShow|[Vv]ersion$|^region$|^loc$|trash-full|recent-apps|persistent-apps|persistent-others|Heartbeat|HasDisplayed|GloballyEnabledEver|last-selection|UserPreferences'

  local new_cmds=()
  local new_count=0

  for domain in "${monitored_domains[@]}"; do
    local tmplist
    tmplist=$(mktemp /tmp/defaults-XXXXXX.plist)
    defaults export "$domain" "$tmplist" 2>/dev/null || { rm -f "$tmplist"; continue; }

    local keys_values
    keys_values=$(python3 -c "
import plistlib
with open('$tmplist', 'rb') as f:
    data = plistlib.load(f)
for k, v in sorted(data.items()):
    if isinstance(v, bool):
        print(f'{k}\tbool\t{str(v).lower()}')
    elif isinstance(v, int):
        print(f'{k}\tint\t{v}')
    elif isinstance(v, float):
        print(f'{k}\tfloat\t{v}')
    elif isinstance(v, str):
        print(f'{k}\tstring\t{v}')
" 2>/dev/null)
    rm -f "$tmplist"

    [[ -z "$keys_values" ]] && continue

    while IFS=$'\t' read -r key vtype value; do
      [[ -z "$key" ]] && continue
      grep -q "$key" "$DEFAULTS_SH" 2>/dev/null && continue
      echo "$key" | grep -qE "$noise_pattern" && continue

      local type_flag
      case "$vtype" in
        bool)   type_flag="-bool" ;;
        int)    type_flag="-int" ;;
        float)  type_flag="-float" ;;
        string) type_flag="-string"; value="\"$value\"" ;;
        *)      continue ;;
      esac

      local write_cmd="defaults write $domain $key $type_flag $value"
      new_cmds+=("$write_cmd")
      new_count=$((new_count + 1))
      log_info "Detected (GUI): $write_cmd"

    done <<< "$keys_values"
  done

  # Insert new commands before the killall line
  if [[ ${#new_cmds[@]} -gt 0 ]]; then
    local tmpsh
    tmpsh=$(mktemp)
    local insert_file
    insert_file=$(mktemp)
    {
      echo ""
      echo "# Auto-discovered from domain monitoring"
      for cmd in "${new_cmds[@]}"; do
        echo "$cmd"
      done
      echo ""
    } > "$insert_file"

    if grep -q "^# Kill affected apps" "$DEFAULTS_SH"; then
      while IFS= read -r line; do
        if [[ "$line" == "# Kill affected apps" ]]; then
          cat "$insert_file"
        fi
        echo "$line"
      done < "$DEFAULTS_SH" > "$tmpsh"
      mv "$tmpsh" "$DEFAULTS_SH"
    else
      cat "$insert_file" >> "$DEFAULTS_SH"
    fi

    rm -f "$insert_file" "$tmpsh"
    log_info "Added $new_count GUI-changed settings to defaults.sh"
  fi
}

# ── Step 3: Update defaults.sh values to match current system ─────
sync_values() {
  local tmpsh
  tmpsh=$(mktemp)
  local updated=0

  while IFS= read -r line; do
    # Only process simple "defaults write" or "defaults -currentHost write" lines
    # Skip lines with shell variables ($(whoami)) to preserve portability
    if echo "$line" | grep -qE '^defaults (-currentHost )?write ' \
       && ! echo "$line" | grep -qE '\-dict-add|\\$|\$\('; then

      local domain="" key="" prefix=""

      if echo "$line" | grep -q '\-currentHost'; then
        prefix="defaults -currentHost write"
        local rest
        rest=$(echo "$line" | sed 's/defaults[[:space:]]*-currentHost[[:space:]]*write[[:space:]]*//')
        domain=$(echo "$rest" | awk '{print $1}')
        key=$(echo "$rest" | awk '{print $2}')
        [[ "$domain" == "-globalDomain" ]] && domain="NSGlobalDomain"
      else
        prefix="defaults write"
        local rest
        rest=$(echo "$line" | sed 's/defaults[[:space:]]*write[[:space:]]*//')
        domain=$(echo "$rest" | awk '{print $1}')
        key=$(echo "$rest" | awk '{print $2}')
      fi

      if [[ -n "$domain" && -n "$key" && "$key" != -* ]]; then
        local new_cmd
        new_cmd=$(build_write_cmd "$prefix" "$domain" "$key" 2>/dev/null)
        if [[ -n "$new_cmd" && "$new_cmd" != "$line" ]]; then
          echo "$new_cmd" >> "$tmpsh"
          updated=$((updated + 1))
          continue
        fi
      fi
    fi

    echo "$line" >> "$tmpsh"
  done < "$DEFAULTS_SH"

  if [[ $updated -gt 0 ]]; then
    mv "$tmpsh" "$DEFAULTS_SH"
    log_info "Updated $updated settings in defaults.sh to match current system"
  else
    rm -f "$tmpsh"
  fi
}

# ── Step 3: Generate human-readable snapshot ──────────────────────
generate_snapshot() {
  {
    cat << 'HEADER'
# macOS Defaults Snapshot
# Current system values for all settings managed by defaults.sh
# If a value here differs from defaults.sh, either:
#   - You changed a setting via System Preferences (update defaults.sh to match)
#   - defaults.sh hasn't been applied yet (run macos/install.sh)

HEADER

    local last_section=""

    # Parse defaults.sh for all defaults write commands
    grep -E '^defaults (-currentHost )?write ' "$DEFAULTS_SH" \
      | grep -v '\-dict-add' \
      | while IFS= read -r cmd; do

      local domain="" key="" is_currenthost=false

      if echo "$cmd" | grep -q '\-currentHost'; then
        is_currenthost=true
        local rest
        rest=$(echo "$cmd" | sed 's/defaults[[:space:]]*-currentHost[[:space:]]*write[[:space:]]*//')
        domain=$(echo "$rest" | awk '{print $1}')
        key=$(echo "$rest" | awk '{print $2}')
        [[ "$domain" == "-globalDomain" ]] && domain="NSGlobalDomain"
      else
        local rest
        rest=$(echo "$cmd" | sed 's/defaults[[:space:]]*write[[:space:]]*//')
        domain=$(echo "$rest" | awk '{print $1}')
        key=$(echo "$rest" | awk '{print $2}')
      fi

      [[ -z "$domain" || -z "$key" ]] && continue

      # Section header on domain change
      if [[ "$domain" != "$last_section" ]]; then
        [[ -n "$last_section" ]] && echo ""
        echo "## $domain"
        last_section="$domain"
      fi

      # Read current value
      local current_val
      if [[ "$is_currenthost" == true ]]; then
        current_val=$(defaults -currentHost read "$domain" "$key" 2>/dev/null || echo "(not set)")
      else
        current_val=$(defaults read "$domain" "$key" 2>/dev/null || echo "(not set)")
      fi

      echo "$domain $key = $current_val"
    done

    # Symbolic hotkeys (dict-add entries need PlistBuddy)
    echo ""
    echo "## com.apple.symbolichotkeys (keyboard shortcuts)"
    local plist="$HOME/Library/Preferences/com.apple.symbolichotkeys.plist"
    for key_id in 31 15 16 17 18 19 20 21 22 23 24 25 26; do
      local enabled
      enabled=$(/usr/libexec/PlistBuddy -c "Print :AppleSymbolicHotKeys:${key_id}:enabled" "$plist" 2>/dev/null || echo "(not set)")
      echo "symbolichotkeys:${key_id}:enabled = $enabled"
    done

  } > "$SNAPSHOT"
}

# ── Run ───────────────────────────────────────────────────────────
discover_new_defaults    # Step 1: scan shell history for new CLI settings
monitor_domains          # Step 2: scan tracked domains for GUI-changed settings
sync_values              # Step 3: update values in defaults.sh to current system
generate_snapshot        # Step 4: write human-readable snapshot

log_info "macOS defaults backed up."
