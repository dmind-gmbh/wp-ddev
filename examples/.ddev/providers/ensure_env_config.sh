#!/bin/bash
# Shared Configuration Wizard
# Ensures that .env.<env> exists and contains necessary variables.

ENV_NAME="${1:-dev}"
ENV_FILE=".env.${ENV_NAME}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Helper function to update .env
update_env() {
    local key="$1"
    local value="$2"
    local comment="$3"
    
    if [ ! -f "$ENV_FILE" ]; then
        echo "# DDEV Project Configuration (${ENV_NAME})" > "$ENV_FILE"
    fi

    if grep -q "^${key}=" "$ENV_FILE"; then
        : # Variable exists
    else
        echo "" >> "$ENV_FILE"
        if [ -n "$comment" ]; then echo "# $comment" >> "$ENV_FILE"; fi
        echo "${key}=\"${value}\"" >> "$ENV_FILE"
    fi
}

echo -e "${CYAN}Checking configuration for: ${YELLOW}${ENV_NAME}${NC}"

# Ensure config file exists
if [ ! -f "$ENV_FILE" ]; then
    echo -e "${YELLOW}Configuration file ${ENV_FILE} not found. Starting interactive setup...${NC}"
    touch "$ENV_FILE"
fi

# Load existing
source "$ENV_FILE"

VARS_UPDATED=false

# Function to prompt and save
ensure_var() {
    local var_name="$1"
    local prompt_text="$2"
    local current_val="${!var_name:-}"
    local is_secret="${3:-false}"

    if [ -z "$current_val" ]; then
        if [ "$is_secret" = true ]; then
            echo -n "$prompt_text " > /dev/tty
            read -r -s input_val < /dev/tty
            echo "" > /dev/tty
        else
            echo -n "$prompt_text " > /dev/tty
            read -r input_val < /dev/tty
        fi
        
        export "$var_name"="$input_val"
        update_env "$var_name" "$input_val" "Auto-generated setting"
        VARS_UPDATED=true
    fi
}

ensure_var "SSH_USER" "Enter SSH Username (e.g. user-123):"
ensure_var "SSH_HOST" "Enter SSH Host (e.g. example.com):"

if [ -z "${SSH_PORT:-}" ]; then
    echo -n "Enter SSH Port [22]: " > /dev/tty
    read -r INPUT_PORT < /dev/tty
    SSH_PORT="${INPUT_PORT:-22}"
    export SSH_PORT
    update_env "SSH_PORT" "$SSH_PORT" "Remote SSH Port"
    VARS_UPDATED=true
fi

ensure_var "SERVER_ROOT" "Enter Remote Server Root Path:"
ensure_var "DATA_DIR" "Enter Remote Data Directory (relative to root, usually /):"
ensure_var "DB_NAME" "Enter Remote Database Name:"
ensure_var "DB_HOST" "Enter Remote Database Host:"
ensure_var "DB_USER" "Enter Remote Database User:"
ensure_var "DB_PASSWORD" "Enter Remote Database Password:" true

if [ -z "${SOURCE_DOMAINS:-}" ]; then
    echo -e "${YELLOW}Source Domains not configured.${NC}" > /dev/tty
    echo -n "Enter comma-separated domains to replace (e.g. old.com,alias.com): " > /dev/tty
    read -r INPUT_DOMAINS < /dev/tty
    export SOURCE_DOMAINS="$INPUT_DOMAINS"
    update_env "SOURCE_DOMAINS" "$INPUT_DOMAINS" "Comma separated list of domains to replace"
    VARS_UPDATED=true
fi

# Prompt Settings Defaults
if [ -z "${IGNORE_FILES_PROMPT:-}" ]; then
    export IGNORE_FILES_PROMPT="i"
    update_env "IGNORE_FILES_PROMPT" "i" "y=auto-accept default ignores, n=ignore nothing, i=interactive"
fi

if [ -z "${IGNORED_FILES:-}" ]; then
     export IGNORED_FILES="*.pdf,*.zip,*.tar.gz,*.sql,*.sql.gz,*.mp4,*.mov,*.avi,*.log,debug.log"
     update_env "IGNORED_FILES" "$IGNORED_FILES" "Default file types to ignore"
fi

if [ "$VARS_UPDATED" = true ]; then
    echo -e "${GREEN}Configuration saved to ${ENV_FILE}.${NC}" > /dev/tty
fi

