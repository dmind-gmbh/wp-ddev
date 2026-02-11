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
ENV_FILE_SECRETS=".env.${PULL_ENV}.local"

# Function for logging to stderr (to keep stdout clean for SQL)
log() {
    echo -e "$@" >&2
}

# Ensure Config exists
if [ -f "${DDEV_COMPOSER_ROOT:-/var/www/html}/.ddev/providers/ensure_env_config.sh" ]; then
    # Run wizard if config is missing (interactive)
    if [ ! -f "$ENV_FILE" ] || [ ! -f "$ENV_FILE_SECRETS" ]; then
        bash "${DDEV_COMPOSER_ROOT:-/var/www/html}/.ddev/providers/ensure_env_config.sh" "$PULL_ENV"
    fi
    
    # Load env
    if [ -f "$ENV_FILE" ]; then source "$ENV_FILE"; fi
    if [ -f "$ENV_FILE_SECRETS" ]; then source "$ENV_FILE_SECRETS"; fi
else
    log "${RED}Error: Config helper script not found.${NC}"
    if [ -f "$ENV_FILE" ]; then source "$ENV_FILE"; fi
    if [ -f "$ENV_FILE_SECRETS" ]; then source "$ENV_FILE_SECRETS"; fi
fi

# Validation
if [ -z "${SSH_HOST:-}" ]; then
    log "${RED}Error: SSH_HOST not defined for ${PULL_ENV}.${NC}"
    exit 1
fi

MODE="${1:-all}" # all, db, files

# ---------------------------------------------------------
# DB Pull
# ---------------------------------------------------------
if [[ "$MODE" == "all" || "$MODE" == "db" ]]; then
    log "${CYAN}>> Phase 1: Database Sync (${PULL_ENV})${NC}"
    
    # We use a temp script on the remote to ensure we get a clean dump
    # but we stream it back.
    
    SED_COMMANDS=""
    if [ -n "${SOURCE_DOMAINS:-}" ]; then
        IFS=',' read -ra DOMAINS <<< "$SOURCE_DOMAINS"
        for domain in "${DOMAINS[@]}"; do
            domain=$(echo "$domain" | xargs)
            if [ -n "$domain" ]; then
                SED_COMMANDS="$SED_COMMANDS | sed -e 's/$domain/$DDEV_HOSTNAME/g'"
            fi
        done
    fi

    log "${BLUE}Streaming remote database...${NC}"
    # Note: We output SQL to STDOUT. All logs must go to STDERR.
    ssh -p "${SSH_PORT:-22}" "${SSH_USER}@${SSH_HOST}" "mysqldump -u'${DB_USER}' -h'${DB_HOST}' -p'${DB_PASSWORD}' '${DB_NAME}' --no-tablespaces" $SED_COMMANDS
    
    log "${GREEN}Database stream complete.${NC}"
fi

# ---------------------------------------------------------
# Files Pull
# ---------------------------------------------------------
if [[ "$MODE" == "all" || "$MODE" == "files" ]]; then
    log "${CYAN}>> Phase 2: Files Sync (${PULL_ENV})${NC}"
    
    DEFAULT_IGNORES="${IGNORED_FILES:-*.pdf,*.zip,*.tar.gz,*.sql,*.sql.gz,*.mp4,*.mov,*.avi,*.log,debug.log}"
    EXCLUDE_FLAGS=""
    IFS=',' read -ra IGNORE_LIST <<< "$DEFAULT_IGNORES"
    for item in "${IGNORE_LIST[@]}"; do
        item=$(echo "$item" | xargs)
        if [ -n "$item" ]; then
            EXCLUDE_FLAGS="$EXCLUDE_FLAGS --exclude='$item'"
        fi
    done

    # Determine if we are doing a full sync or just uploads
    # If wp-config.php exists, we usually just want uploads.
    if [ -f "${DDEV_COMPOSER_ROOT:-/var/www/html}/${DDEV_DOCROOT}/wp-config.php" ]; then
        log "${BLUE}Syncing uploads and languages...${NC}"
        eval rsync -chavzP -e \"ssh -p ${SSH_PORT:-22}\" $EXCLUDE_FLAGS "${SSH_USER}@${SSH_HOST}:${SERVER_ROOT}${DATA_DIR}/wp-content/uploads/" "${DDEV_COMPOSER_ROOT:-/var/www/html}/${DDEV_DOCROOT}/wp-content/uploads/" >&2
        eval rsync -chavzP -e \"ssh -p ${SSH_PORT:-22}\" --exclude '*.zip' "${SSH_USER}@${SSH_HOST}:${SERVER_ROOT}${DATA_DIR}/wp-content/languages/" "${DDEV_COMPOSER_ROOT:-/var/www/html}/${DDEV_DOCROOT}/wp-content/languages/" >&2
    else
        log "${BLUE}Fresh installation: Syncing entire root...${NC}"
        eval rsync -chavzP -e \"ssh -p ${SSH_PORT:-22}\" $EXCLUDE_FLAGS "${SSH_USER}@${SSH_HOST}:${SERVER_ROOT}${DATA_DIR}/" "${DDEV_COMPOSER_ROOT:-/var/www/html}/${DDEV_DOCROOT}/" >&2
        
        # After full sync, we should fix wp-config.php
        log "${YELLOW}Adjusting wp-config.php for local environment...${NC}"
        if [ -f "${DDEV_COMPOSER_ROOT:-/var/www/html}/${DDEV_DOCROOT}/wp-config.php" ]; then
            wp config set DB_NAME db >&2
            wp config set DB_USER db >&2
            wp config set DB_PASSWORD db >&2
            wp config set DB_HOST db >&2
            wp config set WP_HOME "$DDEV_PRIMARY_URL" >&2
            wp config set WP_SITEURL "$DDEV_PRIMARY_URL" >&2
        fi
    fi
    
    log "${GREEN}Files sync complete.${NC}"
fi
