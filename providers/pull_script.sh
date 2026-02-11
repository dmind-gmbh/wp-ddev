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

# Local target database is ALWAYS 'db'
LOCAL_DB="db"

# ---------------------------------------------------------
# DB Pull
# ---------------------------------------------------------
if [[ "$MODE" == "all" || "$MODE" == "db" ]]; then
    log "${CYAN}>> Phase 1: Database Sync (${PULL_ENV})${NC}"
    
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
    
    # Ensure docroot exists
    mkdir -p "${DDEV_COMPOSER_ROOT:-/var/www/html}/${DDEV_DOCROOT}"

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
    WP_CONFIG_PATH="${DDEV_COMPOSER_ROOT:-/var/www/html}/${DDEV_DOCROOT}/wp-config.php"
    
    if [ -f "$WP_CONFIG_PATH" ]; then
        log "${BLUE}Existing installation detected. Syncing uploads and languages...${NC}"
        eval rsync -chavzP -e \"ssh -p ${SSH_PORT:-22}\" $EXCLUDE_FLAGS "${SSH_USER}@${SSH_HOST}:${SERVER_ROOT}${DATA_DIR}/wp-content/uploads/" "${DDEV_COMPOSER_ROOT:-/var/www/html}/${DDEV_DOCROOT}/wp-content/uploads/" >&2
        eval rsync -chavzP -e \"ssh -p ${SSH_PORT:-22}\" --exclude '*.zip' "${SSH_USER}@${SSH_HOST}:${SERVER_ROOT}${DATA_DIR}/wp-content/languages/" "${DDEV_COMPOSER_ROOT:-/var/www/html}/${DDEV_DOCROOT}/wp-content/languages/" >&2
    else
        log "${BLUE}Empty local project: Performing Full Sync...${NC}"
        eval rsync -chavzP -e \"ssh -p ${SSH_PORT:-22}\" $EXCLUDE_FLAGS "${SSH_USER}@${SSH_HOST}:${SERVER_ROOT}${DATA_DIR}/" "${DDEV_COMPOSER_ROOT:-/var/www/html}/${DDEV_DOCROOT}/" >&2
    fi

    # Post-Sync: Ensure wp-config.php is DDEV compatible
    if [ -f "$WP_CONFIG_PATH" ]; then
        log "${YELLOW}Ensuring wp-config.php is DDEV compatible...${NC}"
        
        # 1. Force Local DB Credentials to 'db'
        wp config set DB_NAME "$LOCAL_DB" --type=constant >&2
        wp config set DB_USER "$LOCAL_DB" --type=constant >&2
        wp config set DB_PASSWORD "$LOCAL_DB" --type=constant >&2
        wp config set DB_HOST "$LOCAL_DB" --type=constant >&2
        wp config set WP_HOME "$DDEV_PRIMARY_URL" --type=constant >&2
        wp config set WP_SITEURL "${DDEV_PRIMARY_URL}/" --type=constant >&2

        # 2. Ensure DDEV settings inclusion if missing
        if ! grep -q "wp-config-ddev.php" "$WP_CONFIG_PATH"; then
            log "${BLUE}Injecting DDEV settings inclusion...${NC}"
            # Insert before the "stop editing" line or at the end
            if grep -q "That's all, stop editing!" "$WP_CONFIG_PATH"; then
                sed -i "/That's all, stop editing!/i \
// Include for settings managed by ddev.\n\$ddev_settings = __DIR__ . '/wp-config-ddev.php';\nif ( ! defined( 'DB_USER' ) && getenv( 'IS_DDEV_PROJECT' ) == 'true' && is_readable( \$ddev_settings ) ) {\n\trequire_once( \$ddev_settings );\n}\n" "$WP_CONFIG_PATH"
            else
                echo -e "\n// Include for settings managed by ddev.\n\$ddev_settings = __DIR__ . '/wp-config-ddev.php';\nif ( ! defined( 'DB_USER' ) && getenv( 'IS_DDEV_PROJECT' ) == 'true' && is_readable( \$ddev_settings ) ) {\n\trequire_once( \$ddev_settings );\n}" >> "$WP_CONFIG_PATH"
            fi
        fi
    fi
    
    log "${GREEN}Files sync complete.${NC}"
fi
