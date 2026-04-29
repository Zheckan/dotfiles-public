#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.env"
DEFAULT_REPO_DIR="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || (cd "$SCRIPT_DIR/.." && pwd))"

require_tty() {
  if [[ ! -t 0 || ! -t 1 ]]; then
    printf 'configure.sh requires an interactive terminal.\n' >&2
    exit 1
  fi
}

hide_cursor() {
  printf '\033[?25l' >&2
}

show_cursor() {
  printf '\033[?25h' >&2
}

display_option() {
  case "$1" in
    opencode|cursor|ollama) printf '%s (experimental)' "$1" ;;
    *) printf '%s' "$1" ;;
  esac
}

select_one() {
  local prompt="$1"
  shift
  local options=("$@")
  local index=0
  local key

  while true; do
    printf '\r\033[K? %s\n' "$prompt" >&2
    local i
    for i in "${!options[@]}"; do
      if [[ "$i" -eq "$index" ]]; then
        printf '  \033[32m●\033[0m \033[1m%s\033[0m\n' "$(display_option "${options[$i]}")" >&2
      else
        printf '  ○ %s\n' "$(display_option "${options[$i]}")" >&2
      fi
    done

    IFS= read -rsn1 key
    case "$key" in
      $'\x1b')
        IFS= read -rsn2 key || true
        case "$key" in
          "[A") ((index > 0)) && index=$((index - 1)) ;;
          "[B") ((index < ${#options[@]} - 1)) && index=$((index + 1)) ;;
        esac
        ;;
      "")
        printf '\r\033[K' >&2
        local clear_lines=$(( ${#options[@]} + 1 ))
        while [[ "$clear_lines" -gt 0 ]]; do
          printf '\033[1A\033[K' >&2
          clear_lines=$((clear_lines - 1))
        done
        printf '✓ %s: %s\n' "$prompt" "$(display_option "${options[$index]}")" >&2
        printf '%s' "${options[$index]}"
        return 0
        ;;
    esac

    local lines=$(( ${#options[@]} + 1 ))
    while [[ "$lines" -gt 0 ]]; do
      printf '\033[1A\033[K' >&2
      lines=$((lines - 1))
    done
  done
}

select_many() {
  local prompt="$1"
  shift
  local options=("$@")
  local selected=()
  local index=0
  local key
  local i

  for i in "${!options[@]}"; do
    selected[$i]=false
  done

  while true; do
    printf '\r\033[K? %s\n' "$prompt" >&2
    printf '  Space toggles, Enter continues. Choose at least one.\n' >&2
    for i in "${!options[@]}"; do
      local marker="○"
      [[ "${selected[$i]}" == "true" ]] && marker="●"
      if [[ "$i" -eq "$index" ]]; then
        printf '  \033[32m%s\033[0m \033[1m%s\033[0m\n' "$marker" "$(display_option "${options[$i]}")" >&2
      else
        printf '  %s %s\n' "$marker" "$(display_option "${options[$i]}")" >&2
      fi
    done

    IFS= read -rsn1 key
    case "$key" in
      $'\x1b')
        IFS= read -rsn2 key || true
        case "$key" in
          "[A") ((index > 0)) && index=$((index - 1)) ;;
          "[B") ((index < ${#options[@]} - 1)) && index=$((index + 1)) ;;
        esac
        ;;
      " ")
        if [[ "${selected[$index]}" == "true" ]]; then
          selected[$index]=false
        else
          selected[$index]=true
        fi
        ;;
      "")
        local chosen=()
        for i in "${!options[@]}"; do
          [[ "${selected[$i]}" == "true" ]] && chosen+=("${options[$i]}")
        done
        if [[ "${#chosen[@]}" -gt 0 ]]; then
          clear_menu $(( ${#options[@]} + 2 ))
          printf '✓ %s: %s\n' "$prompt" "$(join_display_csv "${chosen[@]}")" >&2
          join_csv "${chosen[@]}"
          return 0
        fi
        ;;
    esac

    clear_menu $(( ${#options[@]} + 2 ))
  done
}

clear_menu() {
  local lines="$1"
  while [[ "$lines" -gt 0 ]]; do
    printf '\033[1A\033[K' >&2
    lines=$((lines - 1))
  done
}

join_csv() {
  local first=true
  local item

  for item in "$@"; do
    if [[ "$first" == "true" ]]; then
      first=false
    else
      printf ','
    fi
    printf '%s' "$item"
  done
}

join_display_csv() {
  local first=true
  local item

  for item in "$@"; do
    if [[ "$first" == "true" ]]; then
      first=false
    else
      printf ','
    fi
    display_option "$item"
  done
}

csv_to_array() {
  local raw="$1"
  local old_ifs="$IFS"
  local item

  IFS=,
  for item in $raw; do
    printf '%s\n' "$item"
  done
  IFS="$old_ifs"
}

remove_array_item() {
  local remove="$1"
  shift
  local item

  for item in "$@"; do
    [[ "$item" == "$remove" ]] || printf '%s\n' "$item"
  done
}

choose_reviewer_order() {
  local selected_csv="$1"
  local remaining=()
  local ordered=()
  local choice
  local prompt_label

  while IFS= read -r choice; do
    [[ -n "$choice" ]] && remaining+=("$choice")
  done < <(csv_to_array "$selected_csv")

  while [[ "${#remaining[@]}" -gt 0 ]]; do
    if [[ "${#ordered[@]}" -eq 0 ]]; then
      prompt_label="Default provider to review"
    else
      prompt_label="Fallback provider to review"
    fi

    if [[ "${#remaining[@]}" -eq 1 ]]; then
      ordered+=("${remaining[0]}")
      printf '✓ %s: %s\n' "$prompt_label" "$(display_option "${remaining[0]}")" >&2
      break
    fi
    choice="$(select_one "$prompt_label" "${remaining[@]}")"
    ordered+=("$choice")
    local selected_choice="$choice"
    local current_remaining=("${remaining[@]}")
    remaining=()
    while IFS= read -r choice; do
      [[ -n "$choice" ]] && remaining+=("$choice")
    done < <(remove_array_item "$selected_choice" "${current_remaining[@]}")
  done

  join_csv "${ordered[@]}"
}

models_for_claude_preset() {
  case "$1" in
    "Stable aliases") printf 'default,sonnet,haiku' ;;
    "Default only") printf 'default' ;;
    "Sonnet then Haiku") printf 'sonnet,haiku' ;;
  esac
}

models_for_codex_preset() {
  case "$1" in
    "Default only") printf 'default' ;;
    "Default → GPT-5.4 → Mini") printf 'default,gpt-5.4,gpt-5.4-mini' ;;
    "GPT-5.4 → Mini") printf 'gpt-5.4,gpt-5.4-mini' ;;
  esac
}

models_for_gemini_preset() {
  case "$1" in
    "Default only") printf 'default' ;;
    "Default → Gemini 3 Flash → Flash alias") printf 'default,gemini-3-flash-preview,flash' ;;
    "Gemini 3 Flash → Flash alias") printf 'gemini-3-flash-preview,flash' ;;
  esac
}

write_config() {
  local mode="$1"
  local rebase="$2"
  local review="$3"
  local reviewers="$4"
  local claude_models="$5"
  local codex_models="$6"
  local gemini_models="$7"
  local tmp_file backup_file

  tmp_file="$(mktemp "${TMPDIR:-/tmp}/dotfiles-config.env.XXXXXX")"
  backup_file="${TMPDIR:-/tmp}/dotfiles-config.env.backup.$(date +%Y%m%d-%H%M%S)"

  cat > "$tmp_file" <<CONFIG
# Auto-backup defaults.
# Shortcuts and LaunchAgent should call run-backup.sh without mode flags.
# Override one run with CLI flags, or override one machine with config.local.env.

DOTFILES_AUTOBACKUP_MODE="$mode"
DOTFILES_AUTOBACKUP_REBASE="$rebase"
DOTFILES_AUTOBACKUP_REVIEW="$review"

# Reviewers are tried in order. Claude, Codex, and Gemini are tested adapters.
# OpenCode, Cursor, and Ollama are experimental selectors that fail closed.
# Fallback continues after missing CLIs, failed commands, or empty output.
# Any successful non-empty review whose first non-blank line is not APPROVED stops fallback.
DOTFILES_REVIEWERS="$reviewers"

# Model names are passed through to each CLI as best-effort strings.
DOTFILES_REVIEW_CLAUDE_MODELS="$claude_models"
DOTFILES_REVIEW_CODEX_MODELS="$codex_models"
DOTFILES_REVIEW_GEMINI_MODELS="$gemini_models"

# Experimental selectors exist but fail closed until tested for unattended merge.
# DOTFILES_REVIEW_OPENCODE_MODELS="default"
# DOTFILES_REVIEW_CURSOR_MODELS="default"
# DOTFILES_REVIEW_OLLAMA_MODELS="default"
CONFIG

  if [[ -f "$CONFIG_FILE" ]]; then
    cp "$CONFIG_FILE" "$backup_file"
    printf 'Backed up existing config: %s\n' "$backup_file" >&2
  fi

  mv "$tmp_file" "$CONFIG_FILE"
}

main() {
  local mode_label mode rebase review selected_reviewers reviewers
  local claude_preset codex_preset gemini_preset
  local claude_models codex_models gemini_models repo_dir

  require_tty
  trap show_cursor EXIT
  hide_cursor

  printf 'Auto-backup config setup\n\n'

  mode_label="$(select_one "Auto-backup mode" "main-pc" "device-only" "pr-only" "test")"
  mode="$mode_label"
  rebase="$(select_one "Rebase before backup" "true" "false")"
  review="$(select_one "Run AI review for PR modes" "true" "false")"
  printf 'Claude, Codex, and Gemini reviewers are tested. OpenCode, Cursor, and Ollama are experimental fail-closed selectors.\n' >&2
  selected_reviewers="$(select_many "Reviewers to use" "claude" "codex" "gemini" "opencode" "cursor" "ollama")"
  reviewers="$(choose_reviewer_order "$selected_reviewers")"
  printf '✓ Reviewer fallback order: %s\n' "$reviewers" >&2

  claude_preset="$(select_one "Claude model fallback" "Stable aliases" "Default only" "Sonnet then Haiku")"
  codex_preset="$(select_one "Codex model fallback" "Default → GPT-5.4 → Mini" "Default only" "GPT-5.4 → Mini")"
  gemini_preset="$(select_one "Gemini model fallback" "Default → Gemini 3 Flash → Flash alias" "Default only" "Gemini 3 Flash → Flash alias")"

  claude_models="$(models_for_claude_preset "$claude_preset")"
  codex_models="$(models_for_codex_preset "$codex_preset")"
  gemini_models="$(models_for_gemini_preset "$gemini_preset")"

  write_config "$mode" "$rebase" "$review" "$reviewers" "$claude_models" "$codex_models" "$gemini_models"

  repo_dir="$DEFAULT_REPO_DIR"

  printf '\nWrote: %s\n\n' "$CONFIG_FILE"
  printf 'Use this in Apple Shortcuts or other automation:\n\n'
  printf 'export DOTFILES_REPO_DIR="%s"\n' "$repo_dir"
  printf '"$DOTFILES_REPO_DIR/auto-backup/run-backup.sh"\n\n'
  printf 'For PR review/merge modes, authenticate the selected tools first:\n'
  printf '  gh auth login\n'
  printf '  claude        # if using Claude\n'
  printf '  codex login   # if using Codex\n'
  printf '  gemini        # if using Gemini\n'
}

main "$@"
