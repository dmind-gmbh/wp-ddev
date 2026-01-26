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

# Check for Prompt Settings (Ignores)
if [ -z "${IGNORE_FILES_PROMPT:-}" ]; then
    export IGNORE_FILES_PROMPT="i"
    update_env "IGNORE_FILES_PROMPT" "i" "y=auto-accept default ignores, n=ignore nothing, i=interactive"
fi

if [ -z "${IGNORED_FILES:-}" ]; then
     # Files defaults
     DEFAULT_FILES="*.pdf,*.zip,*.tar.gz,*.sql,*.sql.gz,*.mp4,*.mov,*.avi,*.log,debug.log"
     export IGNORED_FILES="$DEFAULT_FILES"
     update_env "IGNORED_FILES" "$DEFAULT_FILES" "Default file patterns to ignore"
fi

if [ -z "${IGNORED_DIRS:-}" ]; then
     # Dirs defaults
     DEFAULT_DIRS="wp-content/cache/,wp-content/backups/,wp-content/updraft/,wp-content/ai1wm-backups/,node_modules/,wp-snapshots/"
     export IGNORED_DIRS="$DEFAULT_DIRS"
     update_env "IGNORED_DIRS" "$DEFAULT_DIRS" "Default directories to ignore"
fi

# Check for File Size Limit Settings
if [ -z "${MAX_SIZE_PROMPT:-}" ]; then
    export MAX_SIZE_PROMPT="i"
    update_env "MAX_SIZE_PROMPT" "i" "y=use default size limit, n=no limit, i=interactive"
fi

if [ -z "${RSYNC_MAX_SIZE:-}" ]; then
    # Default to 0 (infinite)
    export RSYNC_MAX_SIZE="0"
    update_env "RSYNC_MAX_SIZE" "0" "Max file size in MB (0 = no limit)"
fi


if [ "$VARS_UPDATED" = true ]; then
    echo -e "${GREEN}Configuration saved to ${ENV_FILE}.${NC}"
    echo ""
fi

# ---------------------------------------------------------
# PART 2: Runtime Prompts
# ---------------------------------------------------------

# 1. File Ignores Logic
DEFAULT_FILES="${IGNORED_FILES}"
DEFAULT_DIRS="${IGNORED_DIRS}"
PROMPT_IGN_VAL="${IGNORE_FILES_PROMPT}"

if [ "$PROMPT_IGN_VAL" == "i" ]; then
    # Prompt for Files
    echo -e "${YELLOW}Default file patterns: ${DEFAULT_FILES}${NC}"
    read -p "Enter patterns to ignore (comma separated) [${DEFAULT_FILES}]: " USER_FILES
    FINAL_FILES="${USER_FILES:-$DEFAULT_FILES}"
    
    # Prompt for Dirs
    echo -e "${YELLOW}Default directories: ${DEFAULT_DIRS}${NC}"
    read -p "Enter directories to ignore (comma separated) [${DEFAULT_DIRS}]: " USER_DIRS
    FINAL_DIRS="${USER_DIRS:-$DEFAULT_DIRS}"
    
elif [ "$PROMPT_IGN_VAL" == "y" ]; then
    echo -e "${BLUE}Auto-accepting default ignores.${NC}"
    FINAL_FILES="$DEFAULT_FILES"
    FINAL_DIRS="$DEFAULT_DIRS"
else
    echo -e "${BLUE}Ignore list disabled by configuration.${NC}"
    FINAL_FILES=""
    FINAL_DIRS=""
fi

# 2. File Size Limit Logic
DEFAULT_SIZE="${RSYNC_MAX_SIZE:-0}"
PROMPT_SIZE_VAL="${MAX_SIZE_PROMPT:-i}"
FINAL_SIZE="0"

if [ "$PROMPT_SIZE_VAL" == "i" ]; then
    echo -e "${YELLOW}Default max file size: ${DEFAULT_SIZE} MB (0 = no limit)${NC}"
    read -p "Enter max file size in MB [${DEFAULT_SIZE}]: " USER_SIZE
    FINAL_SIZE="${USER_SIZE:-$DEFAULT_SIZE}"
elif [ "$PROMPT_SIZE_VAL" == "y" ]; then
    echo -e "${BLUE}Using configured max size: ${DEFAULT_SIZE} MB${NC}"
    FINAL_SIZE="$DEFAULT_SIZE"
else
    echo -e "${BLUE}File size limit disabled (no limit).${NC}"
    FINAL_SIZE="0"
fi

# 3. wp-config Logic
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
echo -e "${BLUE}Preparing to pull database from ${SSH_HOST}...${NC}"

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
ssh ${SSH_USER}@${SSH_HOST} "bash -s" <<EOF
set -eu -o pipefail
mysqldump -u'$DB_USER' -h'$DB_HOST' -p'$DB_PASSWORD' '$DB_NAME' $SED_CMD | gzip > '$SERVER_ROOT'/db.sql.gz
EOF

echo -e "${BLUE}Downloading dump...${NC}"
rsync -az ${SSH_USER}@${SSH_HOST}:${SERVER_ROOT}/db.sql.gz /var/www/html/.ddev/.downloads
ssh ${SSH_USER}@${SSH_HOST} "rm '${SERVER_ROOT}'/db.sql.gz"

echo -e "${GREEN}Database sync complete!${NC}"
echo ""

# Files Sync
echo -e "${CYAN}>> Phase 2: Files Sync${NC}"
EXCLUDE_FLAGS=""

# Process Files
if [ -n "$FINAL_FILES" ]; then
    IFS=',' read -ra IGNORE_LIST <<< "$FINAL_FILES"
    for item in "${IGNORE_LIST[@]}"; do
        item=$(echo "$item" | xargs)
        if [ -n "$item" ]; then
            EXCLUDE_FLAGS="$EXCLUDE_FLAGS --exclude '$item'"
        fi
    done
fi

# Process Dirs
if [ -n "$FINAL_DIRS" ]; then
    IFS=',' read -ra IGNORE_LIST <<< "$FINAL_DIRS"
    for item in "${IGNORE_LIST[@]}"; do
        item=$(echo "$item" | xargs)
        if [ -n "$item" ]; then
            EXCLUDE_FLAGS="$EXCLUDE_FLAGS --exclude '$item'"
        fi
    done
fi

# Add Max Size Limit if set
if [ "$FINAL_SIZE" -gt 0 ]; then
    echo -e "${BLUE}Applying file size limit: ${FINAL_SIZE} MB${NC}"
    EXCLUDE_FLAGS="$EXCLUDE_FLAGS --max-size=${FINAL_SIZE}m"
fi

echo -e "${BLUE}Syncing files...${NC}"
if [ "$WP_CONFIG_MISSING" = false ]; then
    echo -e "${BLUE}Existing installation detected. Syncing only wp-content/uploads and languages...${NC}"
    eval rsync -chavzP $EXCLUDE_FLAGS "${SSH_USER}@${SSH_HOST}:${SERVER_ROOT}${DATA_DIR}/wp-content/uploads/" /var/www/html/${DDEV_DOCROOT}/wp-content/uploads
    eval rsync -chavzP --exclude '*.zip' "${SSH_USER}@${SSH_HOST}:${SERVER_ROOT}${DATA_DIR}/wp-content/languages/" /var/www/html/${DDEV_DOCROOT}/wp-content/languages
else
    echo -e "${BLUE}Fresh installation detected. Syncing entire root...${NC}"
    eval rsync -chavzP $EXCLUDE_FLAGS "${SSH_USER}@${SSH_HOST}:${SERVER_ROOT}${DATA_DIR}/" /var/www/html/${DDEV_DOCROOT}
    
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
