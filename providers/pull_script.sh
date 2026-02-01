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

# Determine Environment
PULL_ENV="${PULL_ENV:-dev}"
ENV_FILE=".env.${PULL_ENV}"

# Fallback compatibility
if [ "$PULL_ENV" == "dev" ] && [ ! -f "$ENV_FILE" ] && [ -f ".env" ]; then
    ENV_FILE=".env"
fi

echo -e "${CYAN}=======================================================${NC}"
echo -e "${CYAN}      Starting Pull for Environment: ${YELLOW}${PULL_ENV}${CYAN}      ${NC}"
echo -e "${CYAN}=======================================================${NC}"

# Ensure Config exists
if [ -f "${DDEV_COMPOSER_ROOT:-/var/www/html}/.ddev/providers/ensure_env_config.sh" ]; then
    bash ${DDEV_COMPOSER_ROOT:-/var/www/html}/.ddev/providers/ensure_env_config.sh "$PULL_ENV"
    
    # Reload env after wizard might have created it
    if [ -f "$ENV_FILE" ]; then 
        source "$ENV_FILE"
    fi
else
    echo -e "${RED}Error: Config helper script not found.${NC}"
    # Fallback loading if script missing
    if [ -f "$ENV_FILE" ]; then source "$ENV_FILE"; fi
fi

# ---------------------------------------------------------
# Runtime Prompts (File Ignores, WP Config)
# ---------------------------------------------------------

# File Ignores Logic
DEFAULT_IGNORES="${IGNORED_FILES:-*.pdf,*.zip}"
PROMPT_IGN_VAL="${IGNORE_FILES_PROMPT:-i}"

if [ "$PROMPT_IGN_VAL" == "i" ]; then
    echo -e "${YELLOW}Default file types to ignore: ${DEFAULT_IGNORES}${NC}"
    echo -n "Enter file types to ignore (comma separated) [${DEFAULT_IGNORES}]: " > /dev/tty
    read -r USER_IGNORES < /dev/tty
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
if [ ! -e ${DDEV_COMPOSER_ROOT:-/var/www/html}/${DDEV_DOCROOT}/wp-config.php ]; then
    WP_CONFIG_MISSING=true
    ANSWER="${EDIT_CONFIG:-i}"
    
    if [ "$ANSWER" == "i" ]; then
        echo -e "${YELLOW}wp-config.php is missing.${NC}"
        echo -n "Do you want to automatically edit wp-config.php after download? [Y/n] (no): " > /dev/tty
        read -r PROMPT_ANS < /dev/tty
        if [[ "$PROMPT_ANS" =~ ^[Yy]$ ]]; then DO_EDIT_CONFIG="y"; fi
    elif [ "$ANSWER" == "y" ]; then
        DO_EDIT_CONFIG="y"
    fi
fi

echo -e "${GREEN}Starting sync process...${NC}"
echo ""

# ---------------------------------------------------------
# Execution
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

# Use HEREDOC to execute clean remote commands
ssh -p "${SSH_PORT}" ${SSH_USER}@${SSH_HOST} "bash -s" <<EOF
set -eu -o pipefail
mysqldump -u'$DB_USER' -h'$DB_HOST' -p'$DB_PASSWORD' '$DB_NAME' $SED_CMD | gzip > '$SERVER_ROOT'/db.sql.gz
EOF

echo -e "${BLUE}Downloading dump...${NC}"
rsync -az -e "ssh -p ${SSH_PORT}" ${SSH_USER}@${SSH_HOST}:${SERVER_ROOT}/db.sql.gz ${DDEV_COMPOSER_ROOT:-/var/www/html}/.ddev/.downloads
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
    eval rsync -chavzP -e \"ssh -p ${SSH_PORT}\" $EXCLUDE_FLAGS "${SSH_USER}@${SSH_HOST}:${SERVER_ROOT}${DATA_DIR}/wp-content/uploads/" ${DDEV_COMPOSER_ROOT:-/var/www/html}/${DDEV_DOCROOT}/wp-content/uploads
    eval rsync -chavzP -e \"ssh -p ${SSH_PORT}\" --exclude '*.zip' "${SSH_USER}@${SSH_HOST}:${SERVER_ROOT}${DATA_DIR}/wp-content/languages/" ${DDEV_COMPOSER_ROOT:-/var/www/html}/${DDEV_DOCROOT}/wp-content/languages
else
    echo -e "${BLUE}Fresh installation detected. Syncing entire root...${NC}"
    eval rsync -chavzP -e \"ssh -p ${SSH_PORT}\" $EXCLUDE_FLAGS "${SSH_USER}@${SSH_HOST}:${SERVER_ROOT}${DATA_DIR}/" ${DDEV_COMPOSER_ROOT:-/var/www/html}/${DDEV_DOCROOT}
    
    if [ "$DO_EDIT_CONFIG" == "y" ]; then
        echo -e "${YELLOW}Editing wp-config.php...${NC}"
        sed -ir "s/define\s*(\s*'DB_NAME'\s*,\s*'$DB_NAME'\s*);/define( 'DB_NAME', 'db' );/" ${DDEV_COMPOSER_ROOT:-/var/www/html}/${DDEV_DOCROOT}/wp-config.php
        sed -ir "s/define\s*(\s*'DB_USER'\s*,\s*'$DB_USER'\s*);/define( 'DB_USER', 'db' );/" ${DDEV_COMPOSER_ROOT:-/var/www/html}/${DDEV_DOCROOT}/wp-config.php
        sed -ir "s/define\s*(\s*'DB_PASSWORD'\s*,\s*'[^']*'\s*);/define( 'DB_PASSWORD', 'db' );/" ${DDEV_COMPOSER_ROOT:-/var/www/html}/${DDEV_DOCROOT}/wp-config.php
        sed -ir "s/define\s*(\s*'DB_HOST'\s*,\s*'$DB_HOST'\s*);/define( 'DB_HOST', 'db' );/" ${DDEV_COMPOSER_ROOT:-/var/www/html}/${DDEV_DOCROOT}/wp-config.php
        
        sed -ir "s|<?php|<?php\ndefine( 'WP_HOME', '$DDEV_PRIMARY_URL' );\ndefine( 'WP_SITEURL', '$DDEV_PRIMARY_URL' );|" ${DDEV_COMPOSER_ROOT:-/var/www/html}/${DDEV_DOCROOT}/wp-config.php
        echo -e "${GREEN}wp-config.php updated.${NC}"
    fi
fi

echo -e "${GREEN}Project sync complete!${NC}"
echo -e "${CYAN}=======================================================${NC}"