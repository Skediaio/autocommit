#!/bin/bash

# AutoCommit Bash Script
# AI-powered Git Commit Helper with ENV + Config merge

set -e

# Configuration file path
CONFIG_FILE="$HOME/.autocommit/config.json"
INSTRUCTIONS_FILE="$HOME/.autocommit/instructions.txt"
TEMP_DIR="/tmp/autocommit-$$"

# Flags and tuning via env (env overrides config at runtime)
RELAX="${AUTOCOMMIT_RELAX:-0}"              # AUTOCOMMIT_RELAX=1 skip strict validation
DEBUG="${AUTOCOMMIT_DEBUG:-0}"              # AUTOCOMMIT_DEBUG=1 dump prompts/responses
MAX_DIFF_CHARS="${AUTOCOMMIT_MAX_DIFF_CHARS:-15360}"  # truncate large diffs (0 = unlimited)
WRITE_BACK="${AUTOCOMMIT_WRITE_BACK:-0}"    # AUTOCOMMIT_WRITE_BACK=1 persist env merge into config

# Enhanced default instructions template following Conventional Commits
DEFAULT_INSTRUCTIONS="Generate a git commit message following Conventional Commits specification.

Format: <type>[optional scope]: <description>

[optional body]

Required types: feat, fix, docs, style, refactor, test, chore, build, ci, perf, revert

Rules:
1. Use lowercase for type and description
2. No period at the end of description
3. Description should be imperative mood
4. Keep first line under 72 characters but be descriptive
5. Use scope when changes affect specific component
6. Add body paragraph if the change needs explanation
7. Be specific about what changed and why
8. If 'package.json' is updated, summarize the dependency changes (e.g., 'upgrade layerchart to v0.4.0') instead of listing every package. Do not mention package lock files.

Always analyze the complete git diff carefully including file paths and +/- prefixes to provide specific, meaningful commit messages."

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

# Runtime config values (after merge)
provider=""; api_key=""; model=""; base_url=""

print_color() { echo -e "${1}${2}${NC}"; }

cleanup() {
  rm -rf "$TEMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT

check_dependencies() {
  local missing=()
  command -v jq >/dev/null 2>&1 || missing+=("jq")
  command -v curl >/dev/null 2>&1 || missing+=("curl")
  command -v git >/dev/null 2>&1 || missing+=("git")
  if ((${#missing[@]})); then
    print_color "$RED" "Missing required dependencies: ${missing[*]}"; exit 1
  fi
}

create_config_dir() {
  mkdir -p "$(dirname "$CONFIG_FILE")"
  mkdir -p "$(dirname "$INSTRUCTIONS_FILE")"
}

check_git_status() {
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    print_color "$RED" "Error: Not in a git repository"; exit 1
  fi
  if git diff --cached --quiet; then
    print_color "$YELLOW" "No staged changes found. Stage changes with 'git add' first."; exit 1
  fi
}

default_base_url_for() {
  case "$1" in
    openai) echo "https://api.openai.com/v1" ;;
    groq) echo "https://api.groq.com/openai/v1" ;;
    mistral) echo "https://api.mistral.ai/v1" ;;
    google) echo "https://generativelanguage.googleapis.com/v1beta" ;;
    ollama) echo "${OLLAMA_HOST:-http://localhost:11434}" ;;
    openrouter) echo "https://openrouter.ai/api/v1" ;;
    *) echo "" ;;
  esac
}

pick_api_key_for() {
  local p="$1"
  if [[ -n "$AUTOCOMMIT_API_KEY" ]]; then echo "$AUTOCOMMIT_API_KEY"; return; fi
  case "$p" in
    openai) echo "${OPENAI_API_KEY:-}";;
    groq)   echo "${GROQ_API_KEY:-}";;
    mistral) echo "${MISTRAL_API_KEY:-}";;
    google) echo "${GOOGLE_API_KEY:-${GEMINI_API_KEY:-}}";;
    openrouter) echo "${OPENROUTER_API_KEY:-}";;
    ollama) echo "";;
    *) echo "";;
  esac
}

# Merge config.json with environment variables (env has precedence)
load_config() {
  local file_json="{}"
  if [[ -f "$CONFIG_FILE" ]]; then
    if ! jq empty "$CONFIG_FILE" >/dev/null 2>&1; then
      print_color "$RED" "Invalid configuration file at $CONFIG_FILE"; exit 1
    fi
    file_json=$(cat "$CONFIG_FILE")
  fi

  local f_provider f_model f_base_url f_api_key f_relax f_debug f_max f_write_back
  f_provider=$(jq -r '.provider // empty' <<<"$file_json")
  f_model=$(jq -r '.model // empty' <<<"$file_json")
  f_base_url=$(jq -r '.base_url // empty' <<<"$file_json")
  f_api_key=$(jq -r '.api_key // empty' <<<"$file_json")
  f_relax=$(jq -r '.relax // empty' <<<"$file_json")
  f_debug=$(jq -r '.debug // empty' <<<"$file_json")
  f_max=$(jq -r '.max_diff_chars // empty' <<<"$file_json")
  f_write_back=$(jq -r '.write_back // empty' <<<"$file_json")

  # Main fields with env precedence
  provider="${AUTOCOMMIT_PROVIDER:-$f_provider}"
  model="${AUTOCOMMIT_MODEL:-$f_model}"
  base_url="${AUTOCOMMIT_BASE_URL:-$f_base_url}"

  if [[ -z "$base_url" && -n "$provider" ]]; then
    base_url=$(default_base_url_for "$provider")
  fi

  local env_key=""
  if [[ -n "$AUTOCOMMIT_API_KEY" ]]; then
    env_key="$AUTOCOMMIT_API_KEY"
  elif [[ -n "$provider" ]]; then
    env_key="$(pick_api_key_for "$provider")"
  fi
  if [[ -n "$env_key" ]]; then
    api_key="$env_key"
  else
    api_key="$f_api_key"
  fi

  # Flags: env overrides config; if env not set, use config values (if present)
  RELAX="${AUTOCOMMIT_RELAX:-${f_relax:-$RELAX}}"
  DEBUG="${AUTOCOMMIT_DEBUG:-${f_debug:-$DEBUG}}"
  MAX_DIFF_CHARS="${AUTOCOMMIT_MAX_DIFF_CHARS:-${f_max:-$MAX_DIFF_CHARS}}"
  WRITE_BACK="${AUTOCOMMIT_WRITE_BACK:-${f_write_back:-$WRITE_BACK}}"

  if [[ -z "$provider" || -z "$model" ]]; then
    print_color "$YELLOW" "No complete configuration found. Run: $0 configure"
    exit 1
  fi

  # Optionally persist env-merged config to disk each run
  if [[ "$WRITE_BACK" == "1" ]]; then
    create_config_dir
    jq -n \
      --arg provider "$provider" \
      --arg api_key "$api_key" \
      --arg model "$model" \
      --arg base_url "$base_url" \
      --argjson relax "${RELAX:-0}" \
      --argjson debug "${DEBUG:-0}" \
      --argjson write_back "${WRITE_BACK:-0}" \
      --argjson max_diff_chars "${MAX_DIFF_CHARS:-15360}" \
      '{
        provider: $provider,
        api_key: $api_key,
        model: $model,
        base_url: $base_url,
        relax: $relax,
        debug: $debug,
        write_back: $write_back,
        max_diff_chars: $max_diff_chars,
        updated_at: (now | strftime("%Y-%m-%d %H:%M:%S"))
      }' > "$CONFIG_FILE"
  fi
}

# --- Model Selection Guide ---
# When using Ollama for local inference, choosing the right model is key.
# - For a great balance of speed and quality: `gemma2:9b-instruct-q4_K_M` is recommended.
# - For maximum speed on less powerful hardware: `llama3.1:8b-instruct-q4_K_M` is a solid choice.
# You can download these models by running `ollama run <model_name>`.
configure_provider() {
  create_config_dir

  print_color "$BLUE" "Select AI Provider:"
  echo "1) OpenAI"
  echo "2) Ollama (local)"
  echo "3) Mistral"
  echo "4) Google AI (Gemini)"
  echo "5) Groq"
  echo "6) OpenRouter"
  echo "7) Custom (OpenAI-compatible)"

  read -p "Enter choice (1-7) [2]: " choice; choice=${choice:-2}

  local m base akey is_custom=0
  case "$choice" in
    1) provider="openai"; base="${AUTOCOMMIT_BASE_URL:-$(default_base_url_for openai)}"
       m="${AUTOCOMMIT_MODEL:-gpt-4o}"
       akey="${AUTOCOMMIT_API_KEY:-$(pick_api_key_for openai)}"
       ;;
    2) provider="ollama"; base="${AUTOCOMMIT_BASE_URL:-$(default_base_url_for ollama)}"
       m="${AUTOCOMMIT_MODEL:-gemma2:9b-instruct-q4_K_M}"
       akey="" ;;
    3) provider="mistral"; base="${AUTOCOMMIT_BASE_URL:-$(default_base_url_for mistral)}"
       m="${AUTOCOMMIT_MODEL:-mistral-large-latest}"
       akey="${AUTOCOMMIT_API_KEY:-$(pick_api_key_for mistral)}"
       ;;
    4) provider="google"; base="${AUTOCOMMIT_BASE_URL:-$(default_base_url_for google)}"
       m="${AUTOCOMMIT_MODEL:-gemini-1.5-flash-latest}"
       akey="${AUTOCOMMIT_API_KEY:-$(pick_api_key_for google)}"
       ;;
    5) provider="groq"; base="${AUTOCOMMIT_BASE_URL:-$(default_base_url_for groq)}"
       m="${AUTOCOMMIT_MODEL:-llama-3.1-70b-versatile}"
       akey="${AUTOCOMMIT_API_KEY:-$(pick_api_key_for groq)}"
       ;;
    6) provider="openrouter"; base="${AUTOCOMMIT_BASE_URL:-$(default_base_url_for openrouter)}"
       m="${AUTOCOMMIT_MODEL:-nousresearch/nous-hermes-2-mixtral-8x7b-dpo}"
       akey="${AUTOCOMMIT_API_KEY:-$(pick_api_key_for openrouter)}"
       ;;
    7) provider="custom"; is_custom=1; base=""; m=""; akey="" ;;
    *) print_color "$RED" "Invalid choice"; exit 1 ;;
  esac

  # --- Unified Prompting Logic ---
  if (( is_custom )); then
    read -p "Enter custom OpenAI-compatible base URL: " base
    if [[ -z "$base" ]]; then print_color "$RED" "Base URL is required."; exit 1; fi
    read -p "Enter custom model name: " m
    if [[ -z "$m" ]]; then print_color "$RED" "Model name is required."; exit 1; fi
    read -p "Enter API key (optional): " akey
  else
    if [[ -z "$akey" && "$provider" != "ollama" ]]; then
      read -p "Enter API key: " akey
    fi
    if [[ -z "$AUTOCOMMIT_MODEL" ]]; then
      read -p "Enter model name [$m]: " tmp; m=${tmp:-$m}
    fi
    if [[ -n "$AUTOCOMMIT_BASE_URL" ]]; then
      echo "Using base URL from env: $base"
    else
      read -p "Enter base URL [$base]: " tmp; base=${tmp:-$base}
    fi
  fi

  # --- Flag prompts with better explanations ---
  local def_relax="${AUTOCOMMIT_RELAX:-$RELAX}"
  local def_debug="${AUTOCOMMIT_DEBUG:-$DEBUG}"
  local def_max="${AUTOCOMMIT_MAX_DIFF_CHARS:-$MAX_DIFF_CHARS}"
  local def_write="${AUTOCOMMIT_WRITE_BACK:-$WRITE_BACK}"

  read -p "Relaxed validation (skips strict Conventional Commit check)? [0/1] [$def_relax]: " ans; RELAX=${ans:-$def_relax}
  read -p "Enable DEBUG mode (show API requests/responses)? [0/1] [$def_debug]: " ans; DEBUG=${ans:-$def_debug}
  read -p "Max diff chars sent to model (0 = unlimited) [$def_max]: " ans; MAX_DIFF_CHARS=${ans:-$def_max}
  read -p "Save env variables to config file on each run (WRITE_BACK)? [0/1] [$def_write]: " ans; WRITE_BACK=${ans:-$def_write}

  model="$m"; base_url="$base"; api_key="$akey"

  jq -n \
    --arg provider "$provider" \
    --arg api_key "$api_key" \
    --arg model "$model" \
    --arg base_url "$base_url" \
    --argjson relax "${RELAX:-0}" \
    --argjson debug "${DEBUG:-0}" \
    --argjson write_back "${WRITE_BACK:-0}" \
    --argjson max_diff_chars "${MAX_DIFF_CHARS:-15360}" \
    '{
      provider: $provider,
      api_key: $api_key,
      model: $model,
      base_url: $base_url,
      relax: $relax,
      debug: $debug,
      write_back: $write_back,
      max_diff_chars: $max_diff_chars,
      created_at: now | strftime("%Y-%m-%d %H:%M:%S")
    }' > "$CONFIG_FILE"

  print_color "$GREEN" "Configuration saved to $CONFIG_FILE"

  if [[ "$provider" == "ollama" ]]; then
    print_color "$YELLOW" "Testing Ollama connection..."
    if ! curl -s "${base_url%/}/api/tags" >/dev/null 2>&1; then
      print_color "$YELLOW" "Warning: Ollama server not responding. Run 'ollama serve'."
    else
      print_color "$GREEN" "Ollama connection successful!"
    fi
  fi
}

load_instructions() {
  if [[ -f "$INSTRUCTIONS_FILE" ]]; then
    cat "$INSTRUCTIONS_FILE"
  else
    echo "$DEFAULT_INSTRUCTIONS"
  fi
}

get_changes_summary() {
  # Get both status and numstat for comprehensive view, ignoring lockfiles
  local status; status=$(git diff --cached --name-status -- . ':!package-lock.json' ':!yarn.lock' ':!pnpm-lock.yaml')
  local numstat; numstat=$(git diff --cached --numstat -- . ':!package-lock.json' ':!yarn.lock' ':!pnpm-lock.yaml')

  local added modified deleted total_add total_del
  added=$(echo "$status" | grep -c "^A" || true)
  modified=$(echo "$status" | grep -c "^M" || true)
  deleted=$(echo "$status" | grep -c "^D" || true)

  total_add=0; total_del=0
  while read -r a d p; do
    [[ -z "$p" ]] && continue
    [[ "$a" == "-" ]] && a=0
    [[ "$d" == "-" ]] && d=0
    total_add=$((total_add + ${a:-0}))
    total_del=$((total_del + ${d:-0}))
  done <<<"$numstat"

  echo "File changes: +$added new, ~$modified modified, -$deleted deleted"
  echo "Line changes: +$total_add additions, -$total_del deletions"
  echo
  echo "Files:"
  echo "$status"
}

get_diff_content() {
  # Ignore common lockfiles to reduce noise and improve AI focus
  local diff; diff=$(git diff --cached --no-color -- . ':!package-lock.json' ':!yarn.lock' ':!pnpm-lock.yaml')
  local diff_size=${#diff}

  print_color "$BLUE" "📊 Diff size: $diff_size chars"

  # If MAX_DIFF_CHARS is 0 or negative, disable the limit entirely
  if (( MAX_DIFF_CHARS <= 0 )); then
    echo "$diff"
    return 0
  fi

  if (( diff_size > MAX_DIFF_CHARS )); then
    print_color "$YELLOW" "⚠️ Truncating diff to $MAX_DIFF_CHARS chars for model reliability"
    echo "${diff:0:$MAX_DIFF_CHARS}"
    echo "... [TRUNCATED - use AUTOCOMMIT_MAX_DIFF_CHARS=0 for unlimited]"
  else
    echo "$diff"
  fi
}

debug_dump() {
  [[ "$DEBUG" == "1" ]] || return 0
  local label="$1"; shift
  echo -e "\n${BLUE}[DEBUG] $label${NC}"
  local content="$*"; local n=${#content}
  if (( n > 2000 )); then echo "${content:0:2000}"; echo "[...truncated ${n} chars total...]"
  else echo "$content"; fi
}

call_ollama() {
  local prompt_file="$1"

  # Create payload file to avoid argument list too long
  local payload_file="$TEMP_DIR/payload.json"

  # Build JSON payload using file input
  cat > "$payload_file" << EOF
{
  "model": "$model",
  "prompt": $(jq -Rs . < "$prompt_file"),
  "stream": false,
  "options": {
    "temperature": 0.2,
    "num_predict": 400,
    "num_ctx": 8192
  }
}
EOF

  debug_dump "Ollama Payload" "$(head -20 "$payload_file")"

  local response
  response=$(curl -sS -X POST "${base_url%/}/api/generate" \
    -H "Content-Type: application/json" \
    -d @"$payload_file" 2>/dev/null)

  if [[ $? -ne 0 || -z "$response" ]]; then
    print_color "$RED" "❌ Failed to connect to Ollama at $base_url"
    print_color "$YELLOW" "Make sure Ollama is running: ollama serve"
    return 1
  fi

  debug_dump "Ollama Response" "$response"

  # Check for API errors
  if echo "$response" | jq -e '.error' >/dev/null 2>&1; then
    local error_msg; error_msg=$(echo "$response" | jq -r '.error // "Unknown error"')
    print_color "$RED" "❌ Ollama API Error: $error_msg"
    return 1
  fi

  local commit_message
  commit_message=$(echo "$response" | jq -r '.response // empty' 2>/dev/null)

  # Check if response is empty or null
  if [[ -z "$commit_message" || "$commit_message" == "null" ]]; then
    print_color "$RED" "❌ Error: Model returned empty response"
    print_color "$YELLOW" "Try reducing diff size or using a different model"
    return 1
  fi

  # Clean up the message
  commit_message=$(echo "$commit_message" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed 's/^```.*$//g' | sed 's/^`//;s/`$//')
  echo "$commit_message"
}

call_openai_compatible() {
  local prompt_file="$1"

  # Create payload file
  local payload_file="$TEMP_DIR/payload.json"

  cat > "$payload_file" << EOF
{
  "model": "$model",
  "messages": [
    {"role": "system", "content": "You are an expert git commit message generator that follows Conventional Commits. Analyze complete git diffs and file status. Generate detailed, specific messages."},
    {"role": "user", "content": $(jq -Rs . < "$prompt_file")}
  ],
  "max_tokens": 400,
  "temperature": 0.2
}
EOF

  debug_dump "API Payload" "$(head -20 "$payload_file")"

  local response
  if [[ -n "$api_key" ]]; then
    response=$(curl -sS -X POST "${base_url%/}/chat/completions" \
      -H "Authorization: Bearer $api_key" \
      -H "Content-Type: application/json" \
      -d @"$payload_file" 2>/dev/null)
  else
    response=$(curl -sS -X POST "${base_url%/}/chat/completions" \
      -H "Content-Type: application/json" \
      -d @"$payload_file" 2>/dev/null)
  fi

  if [[ $? -ne 0 || -z "$response" ]]; then
    print_color "$RED" "❌ Failed to connect to API at $base_url"
    return 1
  fi

  debug_dump "API Response" "$response"

  # Check for API errors
  if echo "$response" | jq -e '.error' >/dev/null 2>&1; then
    local error_msg; error_msg=$(echo "$response" | jq -r '.error.message // "Unknown error"')
    print_color "$RED" "❌ API Error: $error_msg"
    return 1
  fi

  local commit_message
  commit_message=$(echo "$response" | jq -r '.choices[0].message.content // empty' 2>/dev/null)

  if [[ -z "$commit_message" || "$commit_message" == "null" ]]; then
    print_color "$RED" "❌ Error: Model returned empty response"
    return 1
  fi

  commit_message=$(echo "$commit_message" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed 's/^```.*$//g' | sed 's/^`//;s/`$//')
  echo "$commit_message"
}

generate_commit_message() {
  local additional_context="$1"
  local changes_summary; changes_summary=$(get_changes_summary)
  local diff_content; diff_content=$(get_diff_content)
  local instructions; instructions=$(load_instructions)

  print_color "$BLUE" "🤖 Generating commit message with $provider ($model)..."

  # Create temp directory and prompt file
  mkdir -p "$TEMP_DIR"
  local prompt_file="$TEMP_DIR/prompt.txt"

  # Write comprehensive prompt to file
  cat > "$prompt_file" << EOF
$instructions

$changes_summary

Git diff showing the actual changes:
$diff_content
EOF

  # Add the new context if provided
  if [[ -n "$additional_context" ]]; then
    echo -e "\nAdditional context from user (must be followed):\n$additional_context" >> "$prompt_file"
  fi

  # Add the final instruction
  cat >> "$prompt_file" << EOF

Generate a detailed commit message following the Conventional Commits format. Be specific about what changed, which files were affected, and why. Pay close attention to whether content was added (+) or removed (-). Return ONLY the commit message (no extra text).
EOF

  debug_dump "Prompt File Size" "$(wc -c < "$prompt_file") bytes"

  local commit_message=""
  case "$provider" in
    "ollama") commit_message=$(call_ollama "$prompt_file") ;;
    "openai"|"groq"|"mistral"|"openrouter"|"custom") commit_message=$(call_openai_compatible "$prompt_file") ;;
    *) print_color "$RED" "Unknown provider: $provider"; exit 1 ;;
  esac

  if [[ -z "$commit_message" ]]; then
    print_color "$RED" "Failed to generate commit message"
    return 1
  fi

  echo "$commit_message"
}

show_menu() {
  local commit_message="$1"
  echo
  print_color "$GREEN" "Generated commit message:"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "$commit_message"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  # Validate format
  if [[ "$RELAX" == "1" ]]; then
    # Relaxed mode: check for at least one colon
    if [[ "$commit_message" == *":"* ]]; then
      print_color "$GREEN" "✅ Contains a ':' (Relaxed Mode)"
    else
      print_color "$YELLOW" "⚠️  Missing ':' (Relaxed Mode)"
    fi
  else
    # Strict mode (default)
    if [[ "$commit_message" =~ ^(feat|fix|docs|style|refactor|test|chore|build|ci|perf|revert)(\(.+\))?!?:\ .+ ]]; then
      print_color "$GREEN" "✅ Follows Conventional Commits format"
    else
      print_color "$YELLOW" "⚠️  May not follow Conventional Commits format"
    fi
  fi

  echo
  echo "What would you like to do?"
  echo "1) 📝 Commit with this message"
  echo "2) 📋 Copy to clipboard"
  echo "3) 🔄 Regenerate message"
  echo "4) 💬 Regenerate with additional context"
  echo "5) ❌ Exit without committing"
  echo

  while true; do
    read -p "Enter choice (1-5): " user_choice
    case "$user_choice" in
      [1-5]) break ;;
      *) print_color "$RED" "Invalid choice. Please enter 1-5." ;;
    esac
  done
}

copy_to_clipboard() {
  local message="$1"
  if command -v pbcopy >/dev/null 2>&1; then echo "$message" | pbcopy; print_color "$GREEN" "📋 Copied (macOS)!"
  elif command -v xclip >/dev/null 2>&1; then echo "$message" | xclip -selection clipboard; print_color "$GREEN" "📋 Copied (X11)!"
  elif command -v wl-copy >/dev/null 2>&1; then echo "$message" | wl-copy; print_color "$GREEN" "📋 Copied (Wayland)!"
  else print_color "$YELLOW" "Clipboard utility not found. Here's the message:"; echo; echo "$message"; fi
}

show_config() {
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  print_color "$BLUE" "Current Configuration:"
  echo "Provider: $provider"
  echo "Model: $model"
  local api_mask="Not set"; [[ -n "$api_key" && "$api_key" != "null" ]] && api_mask="${api_key:0:8}..."
  echo "API Key: $api_mask"
  echo "Base URL: $base_url"
  echo "Flags: relax=$RELAX, debug=$DEBUG, write_back=$WRITE_BACK, max_diff_chars=$MAX_DIFF_CHARS"
  echo "Config file: $CONFIG_FILE"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Main
main() {
  check_dependencies

  # Parse flags
  local positional=()
  while (($#)); do
    case "$1" in
      --relax) RELAX=1; shift ;;
      --debug) DEBUG=1; shift ;;
      *) positional+=("$1"); shift ;;
    esac
  done
  set -- "${positional[@]}"

  case "${1:-}" in
    configure) configure_provider; exit 0 ;;
    config) load_config; show_config; exit 0 ;;
    status) load_config || true; show_config; exit 0 ;;
    "--help"|"-h"|"help")
      echo "🤖 AutoCommit - AI-powered Git Commit Helper"
      echo "Generates detailed Conventional Commits messages."
      echo
      echo "Usage: $0 [--relax] [--debug]"
      echo "Commands:"
      echo "  configure               Configure AI provider and settings"
      echo "  config                  Show current configuration"
      echo "  status                  Alias for 'config'"
      echo "  help                    Show this help message"
      echo
      echo "Environment variables (override config):"
      echo "  AUTOCOMMIT_PROVIDER=openai|ollama|mistral|google|groq|openrouter|custom"
      echo "  AUTOCOMMIT_MODEL=...              (e.g., gpt-4o, llama3.1:8b)"
      echo "  AUTOCOMMIT_BASE_URL=...           (overrides default base URL)"
      echo "  AUTOCOMMIT_API_KEY=...            (generic override)"
      echo "  AUTOCOMMIT_MAX_DIFF_CHARS=N       (0 = unlimited, default: $MAX_DIFF_CHARS)"
      echo "  AUTOCOMMIT_DEBUG=1                (show debug info)"
      exit 0
      ;;
    "--version"|"-v")
      echo "AutoCommit v2.1.0 - Simplified commands and improved local model support"
      exit 0
      ;;
  esac

  # Default action: generate message and interact
  check_git_status
  load_config

  print_color "$BLUE" "🔍 Analyzing staged changes..."

  local additional_context=""
  while true; do
    if commit_message=$(generate_commit_message "$additional_context"); then
      additional_context="" # Reset context after each successful generation
      show_menu "$commit_message"
      case "$user_choice" in
        1)
          print_color "$BLUE" "📝 Committing changes..."
          if git commit -m "$commit_message"; then
            print_color "$GREEN" "✅ Committed successfully!"
            break
          else
            print_color "$RED" "❌ Commit failed"
          fi
          ;;
        2) copy_to_clipboard "$commit_message" ;;
        3) print_color "$BLUE" "🔄 Regenerating..." ;;
        4)
          print_color "$BLUE" "💬 Please provide additional context:"
          read -e -p "> " additional_context
          print_color "$BLUE" "🔄 Regenerating with new context..."
          ;;
        5) print_color "$YELLOW" "❌ Exiting without committing"; break ;;
      esac
    else
      print_color "$RED" "Failed to generate message. Try again or exit."
      read -p "Retry? (y/N): " retry
      [[ "$retry" =~ ^[Yy] ]] || exit 1
    fi
  done
}

main "$@"
