#!/bin/bash
#ddev-generated
# Shared Configuration Wizard
# Ensures that .env.<env> exists and contains necessary variables.
# Segregates secrets (passwords) into .env.<env>.local to allow committing the main config.

ENV_NAME="${1:-dev}"
ENV_FILE=".env.${ENV_NAME}"
ENV_FILE_SECRETS=".env.${ENV_NAME}.local"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Helper function to update .env files
update_env() {
    local target_file="$1"
    local key="$2"
    local value="$3"
    local comment="$4"
    
    if [ ! -f "$target_file" ]; then
        if [[ "$target_file" == *".local" ]]; then
            echo "# DDEV Project Secrets (${ENV_NAME}) - DO NOT COMMIT" > "$target_file"
        else
            echo "# DDEV Project Configuration (${ENV_NAME})" > "$target_file"
        fi
    fi

    if grep -q "^${key}=" "$target_file"; then
        : # Variable exists
    else
        echo "" >> "$target_file"
        if [ -n "$comment" ]; then echo "# $comment" >> "$target_file"; fi
        echo "${key}=\"${value}\"" >> "$target_file"
    fi
}

echo -e "${CYAN}Checking configuration for: ${YELLOW}${ENV_NAME}${NC}"

# Ensure config files exist
if [ ! -f "$ENV_FILE" ]; then
    echo -e "${YELLOW}Configuration file ${ENV_FILE} not found. Starting interactive setup...${NC}"
    touch "$ENV_FILE"
fi

if [ ! -f "$ENV_FILE_SECRETS" ]; then
    touch "$ENV_FILE_SECRETS"
fi

# Load existing
source "$ENV_FILE"
source "$ENV_FILE_SECRETS"

VARS_UPDATED=false

# Function to prompt and save
ensure_var() {
    local var_name="$1"
    local prompt_text="$2"
    local is_secret="${3:-false}"
    
    # Check if variable is already in the file
    local in_file=false
    if grep -q "^${var_name}=" "$ENV_FILE" || ([ -f "$ENV_FILE_SECRETS" ] && grep -q "^${var_name}=" "$ENV_FILE_SECRETS"); then
        in_file=true
    fi

    # Get current value from environment
    local current_val="${!var_name:-}"

    # If not in file, OR if in file but empty, handle it.
    # Check if it's missing from the file or empty in memory.
    
    if [ "$in_file" = false ] || [ -z "$current_val" ]; then
        local input_val="$current_val"
        
        # If no value is set (not in env), prompt for it
        if [ -z "$input_val" ]; then
            while true; do
                if [ "$is_secret" = true ]; then
                    echo -n "$prompt_text " > /dev/tty
                    read -r -s input_val < /dev/tty
                    echo "" > /dev/tty
                else
                    echo -n "$prompt_text " > /dev/tty
                    read -r input_val < /dev/tty
                fi
                
                # Validation: Allow empty ONLY if not essential? 
                # For now, let's enforce non-empty for Host/User/DB stuff to fix the user issue.
                if [ -n "$input_val" ]; then
                    break
                fi
                echo -e "${YELLOW}Value cannot be empty. Please try again.${NC}" > /dev/tty
            done
        fi
        
        # Export for current session
        export "$var_name"="$input_val"
        
        # Save to file if not already there
        if [ "$is_secret" = true ]; then
             update_env "$ENV_FILE_SECRETS" "$var_name" "$input_val" "Secret: ${var_name}"
        else
             update_env "$ENV_FILE" "$var_name" "$input_val" "Auto-generated setting"
        fi
        
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
    update_env "$ENV_FILE" "SSH_PORT" "$SSH_PORT" "Remote SSH Port"
    VARS_UPDATED=true
fi

ensure_var "SERVER_ROOT" "Enter Remote Server Base Path (Absolute, e.g. /var/www/vhosts/example.com):"
ensure_var "DATA_DIR" "Enter Project Subdirectory relative to Base Path (e.g. / or /httpdocs):"
ensure_var "DB_NAME" "Enter Remote Database Name:"
ensure_var "DB_HOST" "Enter Remote Database Host:"
ensure_var "DB_USER" "Enter Remote Database User:"
ensure_var "DB_PASSWORD" "Enter Remote Database Password:" true

# Optional Plugin Settings
if [ -z "${ACF_PRO_KEY:-}" ]; then
    echo -n "Enter ACF Pro License Key (optional, press Enter to skip): " > /dev/tty
    read -r ACF_KEY < /dev/tty
    if [ -n "$ACF_KEY" ]; then
        export ACF_PRO_KEY="$ACF_KEY"
        update_env "$ENV_FILE_SECRETS" "ACF_PRO_KEY" "$ACF_KEY" "ACF Pro License Key"
        VARS_UPDATED=true
    fi
fi

if [ -z "${SOURCE_DOMAINS:-}" ]; then
    echo -e "${YELLOW}Source Domains not configured.${NC}" > /dev/tty
    echo -n "Enter comma-separated domains to replace (e.g. old.com,alias.com): " > /dev/tty
    read -r INPUT_DOMAINS < /dev/tty
    export SOURCE_DOMAINS="$INPUT_DOMAINS"
    update_env "$ENV_FILE" "SOURCE_DOMAINS" "$INPUT_DOMAINS" "Comma separated list of domains to replace"
    VARS_UPDATED=true
fi

# Prompt Settings Defaults
if [ -z "${IGNORE_FILES_PROMPT:-}" ]; then
    export IGNORE_FILES_PROMPT="i"
    update_env "$ENV_FILE" "IGNORE_FILES_PROMPT" "i" "y=auto-accept default ignores, n=ignore nothing, i=interactive"
fi

if [ -z "${IGNORED_FILES:-}" ]; then
     export IGNORED_FILES="*.pdf,*.zip,*.tar.gz,*.sql,*.sql.gz,*.mp4,*.mov,*.avi,*.log,debug.log"
     update_env "$ENV_FILE" "IGNORED_FILES" "$IGNORED_FILES" "Default file types to ignore"
fi

if [ "$VARS_UPDATED" = true ]; then
    echo -e "${GREEN}Configuration saved.${NC}" > /dev/tty
    echo -e "${GREEN}  - Shared:  ${ENV_FILE} (Safe to commit)${NC}" > /dev/tty
    echo -e "${GREEN}  - Secrets: ${ENV_FILE_SECRETS} (DO NOT COMMIT)${NC}" > /dev/tty
fi
