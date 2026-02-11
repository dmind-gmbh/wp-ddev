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
        # Replace existing value
        sed -i "s|^${key}=.*|${key}=\"${value}\"|" "$target_file"
    else
        echo "" >> "$target_file"
        if [ -n "$comment" ]; then echo "# $comment" >> "$target_file"; fi
        echo "${key}=\"${value}\"" >> "$target_file"
    fi
}

echo -e "${CYAN}Checking configuration for environment: ${YELLOW}${ENV_NAME}${NC}"
echo -e "${CYAN}Note: Local environment will always use 'db' for DB credentials.${NC}"

# Ensure config files exist
if [ ! -f "$ENV_FILE" ]; then
    echo -e "${YELLOW}Configuration file ${ENV_FILE} not found. Starting interactive setup...${NC}"
    touch "$ENV_FILE"
fi

if [ ! -f "$ENV_FILE_SECRETS" ]; then
    touch "$ENV_FILE_SECRETS"
fi

# Load existing
[ -f "$ENV_FILE" ] && source "$ENV_FILE"
[ -f "$ENV_FILE_SECRETS" ] && source "$ENV_FILE_SECRETS"

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

    if [ "$in_file" = false ] || [ -z "$current_val" ]; then
        local input_val="$current_val"
        
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
                
                if [ -n "$input_val" ]; then
                    break
                fi
                echo -e "${YELLOW}Value cannot be empty. Please try again.${NC}" > /dev/tty
            done
        fi
        
        export "$var_name"="$input_val"
        
        if [ "$is_secret" = true ]; then
             update_env "$ENV_FILE_SECRETS" "$var_name" "$input_val" "Secret: ${var_name}"
        else
             update_env "$ENV_FILE" "$var_name" "$input_val" "Auto-generated setting"
        fi
        
        VARS_UPDATED=true
    fi
}

echo -e "\n${BLUE}--- SSH Connection ---${NC}"
ensure_var "SSH_USER" "Enter REMOTE SSH Username (e.g. user-123):"
ensure_var "SSH_HOST" "Enter REMOTE SSH Host (e.g. example.com):"

if [ -z "${SSH_PORT:-}" ]; then
    echo -n "Enter REMOTE SSH Port [22]: " > /dev/tty
    read -r INPUT_PORT < /dev/tty
    SSH_PORT="${INPUT_PORT:-22}"
    export SSH_PORT
    update_env "$ENV_FILE" "SSH_PORT" "$SSH_PORT" "Remote SSH Port"
    VARS_UPDATED=true
fi

echo -e "\n${BLUE}--- Server Paths ---${NC}"
ensure_var "SERVER_ROOT" "Enter REMOTE Server Base Path (Absolute, e.g. /var/www/vhosts/example.com):"
ensure_var "DATA_DIR" "Enter Project Subdirectory relative to Base Path (e.g. / or /httpdocs):"

echo -e "\n${BLUE}--- Remote Database (Production/Staging Credentials) ---${NC}"
ensure_var "DB_NAME" "Enter REMOTE Database Name:"
ensure_var "DB_HOST" "Enter REMOTE Database Host:"
ensure_var "DB_USER" "Enter REMOTE Database User:"
ensure_var "DB_PASSWORD" "Enter REMOTE Database Password:" true

echo -e "\n${BLUE}--- Domain Handling ---${NC}"
if [ -z "${SOURCE_DOMAINS:-}" ]; then
    echo -n "Enter comma-separated REMOTE domains to replace with local URL (e.g. example.com,www.example.com): " > /dev/tty
    read -r INPUT_DOMAINS < /dev/tty
    export SOURCE_DOMAINS="$INPUT_DOMAINS"
    update_env "$ENV_FILE" "SOURCE_DOMAINS" "$INPUT_DOMAINS" "Comma separated list of domains to replace"
    VARS_UPDATED=true
fi

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

if [ "$VARS_UPDATED" = true ]; then
    echo -e "\n${GREEN}Configuration for ${ENV_NAME} saved.${NC}" > /dev/tty
fi
