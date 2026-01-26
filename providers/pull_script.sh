#!/bin/bash
#ddev-generated
set -eu -o pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Determine Environment and Config File
PULL_ENV="${PULL_ENV:-dev}"
ENV_FILE=".env.${PULL_ENV}"

# Fallback compatibility: If pulling 'dev' and .env.dev doesn't exist but .env does, use .env
if [ "$PULL_ENV" == "dev" ] && [ ! -f "$ENV_FILE" ] && [ -f ".env" ]; then
    ENV_FILE=".env"
fi

echo -e "${CYAN}=======================================================${NC}"
echo -e "${CYAN}      Starting Pull for Environment: ${YELLOW}${PULL_ENV}${CYAN}      ${NC}"
echo -e "${CYAN}=======================================================${NC}"

# Helper function to update .env
update_env() {
    local key="$1"
    local value="$2"
    local comment="$3"
    
    # If file doesn't exist, create it
    if [ ! -f "$ENV_FILE" ]; then
        echo "# DDEV Project Configuration (${PULL_ENV})" > "$ENV_FILE"
    fi

    # Check if key exists
    if grep -q "^${key}=" "$ENV_FILE"; then
        : # Variable exists
    else
        echo "" >> "$ENV_FILE"
        if [ -n "$comment" ]; then echo "# $comment" >> "$ENV_FILE"; fi
        echo "${key}=\"${value}\"" >> "$ENV_FILE"
    fi
}

# Load environment variables if file exists
if [ -f "$ENV_FILE" ]; then 
    source "$ENV_FILE"
    echo -e "${BLUE}Loaded configuration from ${ENV_FILE}${NC}"
else
    echo -e "${YELLOW}Configuration file ${ENV_FILE} not found. Starting interactive setup...${NC}"
fi

# ---------------------------------------------------------
# PART 1: Interactive Setup & Persistence
# ---------------------------------------------------------
echo -e "${CYAN}>> Configuration Check${NC}"

VARS_UPDATED=false

# Function to prompt and save
ensure_var() {
    local var_name="$1"
    local prompt_text="$2"
    local current_val="${!var_name:-""}"
    local is_secret="${3:-false}"

    if [ -z "$current_val" ]; then
        if [ "$is_secret" = true ]; then
            echo -n "$prompt_text "
            read -s input_val
            echo ""
        else
            read -p "$prompt_text " input_val
        fi
        
        # Export for current session
        export "$var_name"="$input_val"
        
        # Save to .env file
        update_env "$var_name" "$input_val" "Auto-generated setting"
        VARS_UPDATED=true
    fi
}

ensure_var "SSH_USER" "Enter SSH Username (e.g. user-123):"
ensure_var "SSH_HOST" "Enter SSH Host (e.g. example.com):"

# SSH Port Handling
if [ -z "${SSH_PORT:-}" ]; then
    read -p "Enter SSH Port [22]: " INPUT_PORT
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

# Check for Domains
if [ -z "${SOURCE_DOMAINS:-}" ]; then
    echo -e "${YELLOW}Source Domains not configured.${NC}"
    read -p "Enter comma-separated domains to replace (e.g. old.com,alias.com): " INPUT_DOMAINS
    export SOURCE_DOMAINS="$INPUT_DOMAINS"
    update_env "SOURCE_DOMAINS" "$INPUT_DOMAINS" "Comma separated list of domains to replace"
    VARS_UPDATED=true
fi

# Check for Prompt Settings
if [ -z "${IGNORE_FILES_PROMPT:-}" ]; then
    export IGNORE_FILES_PROMPT="i"
    update_env "IGNORE_FILES_PROMPT" "i" "y=auto-accept default ignores, n=ignore nothing, i=interactive"
fi

if [ -z "${IGNORED_FILES:-}" ]; then
     export IGNORED_FILES="*.pdf,*.zip"
     update_env "IGNORED_FILES" "*.pdf,*.zip" "Default file types to ignore"
fi

if [ "$VARS_UPDATED" = true ]; then
    echo -e "${GREEN}Configuration saved to ${ENV_FILE}.${NC}"
    echo ""
fi

# ---------------------------------------------------------
# PART 2: Runtime Prompts
# ---------------------------------------------------------

# File Ignores Logic
DEFAULT_IGNORES="${IGNORED_FILES}"
PROMPT_IGN_VAL="${IGNORE_FILES_PROMPT}"

if [ "$PROMPT_IGN_VAL" == "i" ]; then
    echo -e "${YELLOW}Default file types to ignore: ${DEFAULT_IGNORES}${NC}"
    read -p "Enter file types to ignore (comma separated) [${DEFAULT_IGNORES}]: " USER_IGNORES
    FINAL_IGNORES="${USER_IGNORES:-$DEFAULT_IGNORES}"
elif [ "$PROMPT_IGN_VAL" == "y" ]; then
    echo -e "${BLUE}Auto-accepting default ignores: ${DEFAULT_IGNORES}${NC}"
    FINAL_IGNORES="$DEFAULT_IGNORES"
else
    echo -e "${BLUE}Ignore list disabled by configuration.${NC}"
    FINAL_IGNORES=""
fi

# wp-config Logic
DO_EDIT_CONFIG="n"
WP_CONFIG_MISSING=false
if [ ! -e /var/www/html/${DDEV_DOCROOT}/wp-config.php ]; then
    WP_CONFIG_MISSING=true
    ANSWER="${EDIT_CONFIG:-i}"
    
    if [ -z "${EDIT_CONFIG:-}" ]; then
        ANSWER="i"
        update_env "EDIT_CONFIG" "i" "y=yes, n=no, i=interactive for wp-config editing"
    fi

    if [ "$ANSWER" == "i" ]; then
        echo -e "${YELLOW}wp-config.php is missing.${NC}"
        read -p "Do you want to automatically edit wp-config.php after download? [Y/n] (no): " PROMPT_ANS
        if [[ "$PROMPT_ANS" =~ ^[Yy]$ ]]; then DO_EDIT_CONFIG="y"; fi
    elif [ "$ANSWER" == "y" ]; then
        DO_EDIT_CONFIG="y"
    fi
fi

echo -e "${GREEN}Starting sync process...${NC}"
echo ""

# ---------------------------------------------------------
# PART 3: Execution
# ---------------------------------------------------------

# DB Sync
echo -e "${CYAN}>> Phase 1: Database Sync${NC}"
echo -e "${BLUE}Preparing to pull database from ${SSH_HOST}:${SSH_PORT}...${NC}"

SED_CMD=""
if [ -n "${SOURCE_DOMAINS:-}" ]; then
    IFS=',' read -ra DOMAINS <<< "$SOURCE_DOMAINS"
    for domain in "${DOMAINS[@]}"; do
        domain=$(echo "$domain" | xargs)
        if [ -n "$domain" ]; then
            echo -e "  - configured replacement: $domain -> ${DDEV_HOSTNAME}"
            SED_CMD="$SED_CMD | sed -e 's/$domain/$DDEV_HOSTNAME/g'"
        fi
    done
fi

set -eu -o pipefail

echo -e "${BLUE}Dumping remote database...${NC}"

# Use HEREDOC to execute clean remote commands without quoting hell
# Added -p for SSH port
ssh -p "${SSH_PORT}" ${SSH_USER}@${SSH_HOST} "bash -s" <<EOF
set -eu -o pipefail
mysqldump -u'$DB_USER' -h'$DB_HOST' -p'$DB_PASSWORD' '$DB_NAME' $SED_CMD | gzip > '$SERVER_ROOT'/db.sql.gz
EOF

echo -e "${BLUE}Downloading dump...${NC}"
# Added -e "ssh -p PORT" for rsync
rsync -az -e "ssh -p ${SSH_PORT}" ${SSH_USER}@${SSH_HOST}:${SERVER_ROOT}/db.sql.gz /var/www/html/.ddev/.downloads
ssh -p "${SSH_PORT}" ${SSH_USER}@${SSH_HOST} "rm '${SERVER_ROOT}'/db.sql.gz"

echo -e "${GREEN}Database sync complete!${NC}"
echo ""

# Files Sync
echo -e "${CYAN}>> Phase 2: Files Sync${NC}"
EXCLUDE_FLAGS=""
if [ -n "$FINAL_IGNORES" ]; then
    IFS=',' read -ra IGNORE_LIST <<< "$FINAL_IGNORES"
    for item in "${IGNORE_LIST[@]}"; do
        item=$(echo "$item" | xargs)
        if [ -n "$item" ]; then
            EXCLUDE_FLAGS="$EXCLUDE_FLAGS --exclude '$item'"
        fi
    done
fi

echo -e "${BLUE}Syncing files...${NC}"
if [ "$WP_CONFIG_MISSING" = false ]; then
    echo -e "${BLUE}Existing installation detected. Syncing only wp-content/uploads and languages...${NC}"
    eval rsync -chavzP -e "ssh -p ${SSH_PORT}" $EXCLUDE_FLAGS "${SSH_USER}@${SSH_HOST}:${SERVER_ROOT}${DATA_DIR}/wp-content/uploads/" /var/www/html/${DDEV_DOCROOT}/wp-content/uploads
    eval rsync -chavzP -e "ssh -p ${SSH_PORT}" --exclude '*.zip' "${SSH_USER}@${SSH_HOST}:${SERVER_ROOT}${DATA_DIR}/wp-content/languages/" /var/www/html/${DDEV_DOCROOT}/wp-content/languages
else
    echo -e "${BLUE}Fresh installation detected. Syncing entire root...${NC}"
    eval rsync -chavzP -e "ssh -p ${SSH_PORT}" $EXCLUDE_FLAGS "${SSH_USER}@${SSH_HOST}:${SERVER_ROOT}${DATA_DIR}/" /var/www/html/${DDEV_DOCROOT}
    
    if [ "$DO_EDIT_CONFIG" == "y" ]; then
        echo -e "${YELLOW}Editing wp-config.php...${NC}"
        sed -ir "s/define\s*(\s*'DB_NAME'\s*,\s*'$DB_NAME'\s*);/define( 'DB_NAME', 'db' );/" /var/www/html/${DDEV_DOCROOT}/wp-config.php
        sed -ir "s/define\s*(\s*'DB_USER'\s*,\s*'$DB_USER'\s*);/define( 'DB_USER', 'db' );/" /var/www/html/${DDEV_DOCROOT}/wp-config.php
        sed -ir "s/define\s*(\s*'DB_PASSWORD'\s*,\s*'[^']*'\s*);/define( 'DB_PASSWORD', 'db' );/" /var/www/html/${DDEV_DOCROOT}/wp-config.php
        sed -ir "s/define\s*(\s*'DB_HOST'\s*,\s*'$DB_HOST'\s*);/define( 'DB_HOST', 'db' );/" /var/www/html/${DDEV_DOCROOT}/wp-config.php
        
        sed -ir "s|<?php|<?php\ndefine( 'WP_HOME', '$DDEV_PRIMARY_URL' );\ndefine( 'WP_SITEURL', '$DDEV_PRIMARY_URL' );|" /var/www/html/${DDEV_DOCROOT}/wp-config.php
        echo -e "${GREEN}wp-config.php updated.${NC}"
    fi
fi

echo -e "${GREEN}Project sync complete!${NC}"
echo -e "${CYAN}=======================================================${NC}"