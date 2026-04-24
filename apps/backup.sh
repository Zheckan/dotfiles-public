#!/usr/bin/env bash
# apps/backup.sh — Dump current Homebrew packages to Brewfile + detect untracked apps

source "$(cd "$(dirname "$0")/.." && pwd)/_helpers.sh"

BREWFILE="$DOTFILES_DIR/apps/Brewfile"
UNTRACKED_FILE="$DOTFILES_DIR/apps/untracked-apps.txt"
CACHE_FILE="$DOTFILES_DIR/apps/.cask-resolve-cache"

# Apps intentionally ignored from untracked reporting
SYSTEM_APPS=("Safari" "Utilities")
EXCLUDED_APPS=("FileZilla" "zoom.us" "OpenVPN Connect" "Microsoft Teams")

# Convert a display app name into a cask-like token for quick lookup.
normalize_to_token() {
  local value="$1"
  value=$(echo "$value" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')
  printf "%s" "$value"
}

# Read cask tokens from the Brewfile.
get_brewfile_casks() {
  sed -nE 's/^cask "([^"]+)".*/\1/p' "$BREWFILE" | sort -u
}

# Read MAS app display names from the Brewfile.
get_brewfile_mas_names() {
  sed -nE 's/^mas "([^"]+)".*/\1/p' "$BREWFILE" | sort -u
}

# Resolve names of currently installed brew cask apps.
resolve_installed_cask_labels() {
  brew info --json=v2 --installed --cask 2>/dev/null | /usr/bin/ruby -rjson -e '
    payload = JSON.parse(STDIN.read)
    labels = []

    payload.fetch("casks", []).each do |cask|
      Array(cask["name"]).each do |name|
        labels << name if name.is_a?(String) && !name.empty?
      end

      walk = lambda do |value|
        case value
        when Hash
          value.each_value { |nested| walk.call(nested) }
        when Array
          value.each { |nested| walk.call(nested) }
        when String
          if value.end_with?(".app")
            labels << File.basename(value, ".app")
          end
        end
      end

      walk.call(cask["artifacts"])
    end

    puts labels.uniq.sort
  '
}

# Search Homebrew for casks that might correspond to the given app name.
search_cask_candidates_for_app() {
  local app_name="$1"
  local normalized
  local word

  normalized="$(normalize_to_token "$app_name")"

  {
    [[ -n "$normalized" ]] && brew search --casks "$normalized" 2>/dev/null
    brew search --casks "$app_name" 2>/dev/null

    for word in $app_name; do
      word=$(echo "$word" | sed -E 's/[^[:alnum:]@.+-]+//g')
      [[ ${#word} -ge 3 ]] || continue
      brew search --casks "$word" 2>/dev/null
    done
  } | sort -u
}

# Pick the best cask token for a discovered app name.
resolve_cask_for_app() {
  local app_name="$1"
  local resolved_token
  local -a cask_candidates

  mapfile -t cask_candidates < <(search_cask_candidates_for_app "$app_name")
  [[ ${#cask_candidates[@]} -gt 0 ]] || return 1

  resolved_token=$(
    brew info --cask --json=v2 "${cask_candidates[@]}" 2>/dev/null | /usr/bin/ruby -rjson -e '
    def normalize(value)
      value.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/^-+|-+$/, "").gsub(/-+/, "-")
    end

    target = ARGV.fetch(0)
    target_normalized = normalize(target)
    payload = JSON.parse(STDIN.read)

    best_token = nil
    best_score = -1

    payload.fetch("casks", []).each do |cask|
      short_token = cask["token"]
      output_token = cask["full_token"] || short_token
      labels = []
      labels.concat(Array(cask["name"]))
      labels << cask["token"]
      labels << cask["full_token"]
      labels.concat(Array(cask["old_tokens"]))

      has_app_match = false

      walk = lambda do |value|
        case value
        when Hash
          value.each_value { |nested| walk.call(nested) }
        when Array
          value.each { |nested| walk.call(nested) }
        when String
          if value.end_with?(".app")
            app_label = File.basename(value, ".app")
            labels << app_label
            has_app_match = true if normalize(app_label) == target_normalized
          end
        end
      end

      walk.call(cask["artifacts"])

      labels.compact!
      next if labels.empty?
      next unless labels.any? { |label| label == target || normalize(label) == target_normalized }

      # Rank: prefer casks with matching .app artifact (+2), then token match (+1)
      # e.g. codex-app (has Codex.app, score=2) beats codex CLI (no .app, score=1)
      # e.g. telegram (has Telegram.app + token match, score=3) beats forkgram-telegram (score=2)
      score = 0
      score += 2 if has_app_match
      score += 1 if normalize(short_token) == target_normalized

      if score > best_score
        best_score = score
        best_token = output_token
      end
    end

    if best_token
      puts best_token
      exit 0
    end

    exit 1
  ' "$app_name"
  ) || return 1

  [[ -n "$resolved_token" ]] || return 1
  printf "%s\n" "$resolved_token"
  return 0
}

# ── Cask resolution cache ────────────────────────────────────────────
# Persists resolved app→cask mappings so expensive brew search/info
# network calls don't repeat every run. Format: app_name<TAB>result
# where result is a cask token or "UNRESOLVABLE:<epoch>".
# UNRESOLVABLE entries expire after 7 days to allow re-resolution
# when Homebrew adds new casks. Cache is pruned for removed apps on load.
CACHE_TTL=$((7 * 24 * 60 * 60))  # 7 days in seconds
declare -A CASK_CACHE=()

load_cask_cache() {
  [[ -f "$CACHE_FILE" ]] || return 0
  local now
  now=$(date +%s)
  while IFS=$'\t' read -r name result; do
    [[ -n "$name" && -n "$result" ]] || continue
    # Prune entries for apps no longer in /Applications
    [[ -d "/Applications/${name}.app" ]] || continue
    # Expire UNRESOLVABLE entries after TTL
    if [[ "$result" == UNRESOLVABLE:* ]]; then
      local cached_at="${result#UNRESOLVABLE:}"
      if (( now - cached_at > CACHE_TTL )); then
        continue
      fi
    fi
    CASK_CACHE["$name"]="$result"
  done < "$CACHE_FILE"
}

save_cask_cache() {
  if [[ ${#CASK_CACHE[@]} -eq 0 ]]; then
    rm -f "$CACHE_FILE"
    return 0
  fi
  local tmp_file
  tmp_file=$(mktemp "${CACHE_FILE}.XXXXXX") || return 1
  {
    for name in "${!CASK_CACHE[@]}"; do
      printf "%s\t%s\n" "$name" "${CASK_CACHE[$name]}"
    done
  } | sort > "$tmp_file" || { rm -f "$tmp_file"; return 1; }
  mv "$tmp_file" "$CACHE_FILE" || { rm -f "$tmp_file"; return 1; }
}

# Insert cask lines after the last existing cask line (or append if none).
insert_casks_into_brewfile() {
  local new_tokens=("$@")
  [[ ${#new_tokens[@]} -gt 0 ]] || return 0

  local insert_lines
  insert_lines=$(printf 'cask "%s"\n' "${new_tokens[@]}" | sort -u)

  local last_cask_line
  last_cask_line=$(grep -n '^cask ' "$BREWFILE" | tail -1 | cut -d: -f1 || true)

  if [[ -n "$last_cask_line" ]]; then
    head -n "$last_cask_line" "$BREWFILE" > "$BREWFILE.tmp"
    printf "%s\n" "$insert_lines" >> "$BREWFILE.tmp"
    tail -n +"$((last_cask_line + 1))" "$BREWFILE" >> "$BREWFILE.tmp"
    mv "$BREWFILE.tmp" "$BREWFILE"
  else
    printf "%s\n" "$insert_lines" >> "$BREWFILE"
  fi
}

# ── Dump Brewfile ────────────────────────────────────────────────────
# Save previous cask list to detect dropped casks after dump + scan
mapfile -t PREV_CASKS < <(get_brewfile_casks)

log_info "Dumping Homebrew packages to $BREWFILE..."
brew bundle dump --force --file="$BREWFILE"
log_info "Brewfile updated at $BREWFILE"

# ── Detect untracked apps ───────────────────────────────────────────
log_info "Scanning for untracked applications..."

load_cask_cache

declare -A TRACKED_APPS=()
declare -A EXISTING_CASKS=()
declare -A AUTO_ADDED_CASKS=()

mapfile -t BREWFILE_CASKS < <(get_brewfile_casks)
mapfile -t BREWFILE_MAS_NAMES < <(get_brewfile_mas_names)
mapfile -t INSTALLED_CASK_LABELS < <(resolve_installed_cask_labels)

for token in "${BREWFILE_CASKS[@]}"; do
  [[ -n "$token" ]] || continue
  EXISTING_CASKS["$token"]=1
done

for app in "${INSTALLED_CASK_LABELS[@]}" "${BREWFILE_MAS_NAMES[@]}" "${SYSTEM_APPS[@]}" "${EXCLUDED_APPS[@]}"; do
  [[ -n "$app" ]] || continue
  TRACKED_APPS["$app"]=1
done

UNTRACKED_MANUAL=()
for app_path in /Applications/*.app; do
  [[ -d "$app_path" ]] || continue
  app_name=$(basename "$app_path" .app)

  if [[ -n "${TRACKED_APPS[$app_name]+x}" ]]; then
    continue
  fi

  # Fast path: check if the normalized app name matches an existing cask token
  # (e.g. "Google Chrome" → "google-chrome", "Visual Studio Code" → "visual-studio-code")
  # This avoids expensive brew search/info network calls for the common case.
  normalized_name=$(normalize_to_token "$app_name")
  if [[ -n "${EXISTING_CASKS[$normalized_name]+x}" ]]; then
    TRACKED_APPS["$app_name"]=1
    continue
  fi

  # Check cache before expensive brew lookup
  if [[ -n "${CASK_CACHE[$app_name]+x}" ]]; then
    cached="${CASK_CACHE[$app_name]}"
    if [[ "$cached" == UNRESOLVABLE:* ]]; then
      UNTRACKED_MANUAL+=("$app_name")
    elif [[ -n "$cached" ]] && [[ -z "${EXISTING_CASKS[$cached]+x}" ]] && [[ -z "${AUTO_ADDED_CASKS[$cached]+x}" ]]; then
      AUTO_ADDED_CASKS["$cached"]=1
      TRACKED_APPS["$app_name"]=1
    fi
    continue
  fi

  if resolved_token="$(resolve_cask_for_app "$app_name")"; then
    CASK_CACHE["$app_name"]="$resolved_token"
    if [[ -z "${EXISTING_CASKS[$resolved_token]+x}" ]] && [[ -z "${AUTO_ADDED_CASKS[$resolved_token]+x}" ]]; then
      AUTO_ADDED_CASKS["$resolved_token"]=1
      TRACKED_APPS["$app_name"]=1
    fi
  else
    CASK_CACHE["$app_name"]="UNRESOLVABLE:$(date +%s)"
    UNTRACKED_MANUAL+=("$app_name")
  fi
done

if [[ ${#AUTO_ADDED_CASKS[@]} -gt 0 ]]; then
  mapfile -t AUTO_CASK_LIST < <(printf "%s\n" "${!AUTO_ADDED_CASKS[@]}" | sort)
  insert_casks_into_brewfile "${AUTO_CASK_LIST[@]}"
  log_info "Auto-added ${#AUTO_CASK_LIST[@]} cask(s) to Brewfile from /Applications scan"
  for token in "${AUTO_CASK_LIST[@]}"; do
    log_info "  Added cask: $token"
  done
fi

# ── Warn about dropped casks ──────────────────────────────────────────
# Compare final Brewfile against previous to surface any casks that disappeared.
# This catches pkg-based or non-/Applications casks that neither brew bundle dump
# nor the /Applications scan can rediscover.
if [[ ${#PREV_CASKS[@]} -gt 0 ]]; then
  mapfile -t FINAL_CASKS < <(get_brewfile_casks)
  mapfile -t DROPPED_CASKS < <(comm -23 <(printf "%s\n" "${PREV_CASKS[@]}") <(printf "%s\n" "${FINAL_CASKS[@]}"))

  if [[ ${#DROPPED_CASKS[@]} -gt 0 ]]; then
    log_warn "Dropped ${#DROPPED_CASKS[@]} cask(s) from Brewfile (no longer installed or not in /Applications):"
    for token in "${DROPPED_CASKS[@]}"; do
      log_warn "  Dropped cask: $token"
    done
  fi
fi

# Write manual-only apps list
if [[ ${#UNTRACKED_MANUAL[@]} -gt 0 ]]; then
  printf "%s\n" "${UNTRACKED_MANUAL[@]}" | sort > "$UNTRACKED_FILE"
  log_warn "Found ${#UNTRACKED_MANUAL[@]} app(s) with no matching cask — see apps/untracked-apps.txt:"
  for app in "${UNTRACKED_MANUAL[@]}"; do
    log_warn "  Manual install needed: $app"
  done
else
  echo "# No manual-install apps detected" > "$UNTRACKED_FILE"
  log_info "All /Applications apps are covered by Brewfile, MAS, or excluded list."
fi

save_cask_cache
