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

log() {
    echo -e "$@" >&2
}

# Ensure Config exists
if [ -f "${DDEV_COMPOSER_ROOT:-/var/www/html}/.ddev/providers/ensure_env_config.sh" ]; then
    if [ ! -f "$ENV_FILE" ] || [ ! -f "$ENV_FILE_SECRETS" ]; then
        bash "${DDEV_COMPOSER_ROOT:-/var/www/html}/.ddev/providers/ensure_env_config.sh" "$PULL_ENV" >&2
    fi
    [ -f "$ENV_FILE" ] && source "$ENV_FILE" >&2
    [ -f "$ENV_FILE_SECRETS" ] && source "$ENV_FILE_SECRETS" >&2
else
    [ -f "$ENV_FILE" ] && source "$ENV_FILE" >&2
    [ -f "$ENV_FILE_SECRETS" ] && source "$ENV_FILE_SECRETS" >&2
fi

if [ -z "${SSH_HOST:-}" ]; then
    log "${RED}Error: SSH_HOST not defined for ${PULL_ENV}.${NC}"
    exit 1
fi

MODE="${1:-all}"
LOCAL_DB="db"

# ---------------------------------------------------------
# DB Pull
# ---------------------------------------------------------
if [[ "$MODE" == "all" || "$MODE" == "db" ]]; then
    log "${CYAN}>> Phase 1: Database Sync (${PULL_ENV})${NC}"
    
    # IMPORTANT: For DB pull via stdout, the .downloads directory MUST be empty
    # otherwise DDEV might look for files instead of capturing stdout.
    rm -rf "${DDEV_COMPOSER_ROOT:-/var/www/html}/.ddev/.downloads"/* 2>/dev/null || true
    
    SED_ARGS=()
    if [ -n "${SOURCE_DOMAINS:-}" ]; then
        IFS=',' read -ra DOMAINS <<< "$SOURCE_DOMAINS"
        for domain in "${DOMAINS[@]}"; do
            domain=$(echo "$domain" | xargs)
            if [ -n "$domain" ]; then
                escaped_domain=$(echo "$domain" | sed 's/\./\\./g')
                SED_ARGS+=("-e" "s/$escaped_domain/$DDEV_HOSTNAME/g")
            fi
        done
    fi

    log "${BLUE}Streaming remote database...${NC}"
    # Use a file for DB import to be more robust with DDEV
    DB_OUT="${DDEV_COMPOSER_ROOT:-/var/www/html}/.ddev/.downloads/db.sql"
    mkdir -p "${DDEV_COMPOSER_ROOT:-/var/www/html}/.ddev/.downloads"
    
    if [ ${#SED_ARGS[@]} -gt 0 ]; then
        ssh -q -p "${SSH_PORT:-22}" "${SSH_USER}@${SSH_HOST}" "mysqldump -u'${DB_USER}' -h'${DB_HOST}' -p'${DB_PASSWORD}' '${DB_NAME}' --no-tablespaces" | sed "${SED_ARGS[@]}" > "$DB_OUT"
    else
        ssh -q -p "${SSH_PORT:-22}" "${SSH_USER}@${SSH_HOST}" "mysqldump -u'${DB_USER}' -h'${DB_HOST}' -p'${DB_PASSWORD}' '${DB_NAME}' --no-tablespaces" > "$DB_OUT"
    fi
fi

# ---------------------------------------------------------
# Files Pull
# ---------------------------------------------------------
if [[ "$MODE" == "all" || "$MODE" == "files" ]]; then
    log "${CYAN}>> Phase 2: Files Sync (${PULL_ENV})${NC}"
    
    # Ensure docroot exists
    mkdir -p "${DDEV_COMPOSER_ROOT:-/var/www/html}/${DDEV_DOCROOT}"
    RSYNC_ARGS=("-chavzP" "-e" "ssh -p ${SSH_PORT:-22}")
    
    DEFAULT_IGNORES="${IGNORED_FILES:-*.pdf,*.zip,*.tar.gz,*.sql,*.sql.gz,*.mp4,*.mov,*.avi,*.log,debug.log}"
    IFS=',' read -ra IGNORE_LIST <<< "$DEFAULT_IGNORES"
    for item in "${IGNORE_LIST[@]}"; do
        item=$(echo "$item" | xargs)
        [ -n "$item" ] && RSYNC_ARGS+=("--exclude=$item")
    done

    # Clean up paths to prevent double slashes
    S_ROOT="${SERVER_ROOT%/}"
    D_DIR="${DATA_DIR#/}"
    D_DIR="${D_DIR%/}"
    
    if [ -n "$D_DIR" ]; then
        FULL_REMOTE_PATH="${S_ROOT}/${D_DIR}"
    else
        FULL_REMOTE_PATH="${S_ROOT}"
    fi

    # Determine if we are doing a full sync or just uploads
    WP_CONFIG_PATH="${DDEV_COMPOSER_ROOT:-/var/www/html}/${DDEV_DOCROOT}/wp-config.php"
    WP_ADMIN_PATH="${DDEV_COMPOSER_ROOT:-/var/www/html}/${DDEV_DOCROOT}/wp-admin"
    
    if [ -d "$WP_ADMIN_PATH" ] && [ -f "$WP_CONFIG_PATH" ]; then
        log "${BLUE}Existing installation detected. Syncing uploads and languages...${NC}"
        # Sync uploads (ensure local dir exists)
        mkdir -p "${DDEV_COMPOSER_ROOT:-/var/www/html}/${DDEV_DOCROOT}/wp-content/uploads/"
        rsync "${RSYNC_ARGS[@]}" "${SSH_USER}@${SSH_HOST}:${FULL_REMOTE_PATH}/wp-content/uploads/" "${DDEV_COMPOSER_ROOT:-/var/www/html}/${DDEV_DOCROOT}/wp-content/uploads/" >&2 || log "${YELLOW}Warning: Could not sync uploads.${NC}"
        
        # Sync languages (optional, might not exist)
        mkdir -p "${DDEV_COMPOSER_ROOT:-/var/www/html}/${DDEV_DOCROOT}/wp-content/languages/"
        rsync -chavzP -e "ssh -p ${SSH_PORT:-22}" --exclude '*.zip' "${SSH_USER}@${SSH_HOST}:${FULL_REMOTE_PATH}/wp-content/languages/" "${DDEV_COMPOSER_ROOT:-/var/www/html}/${DDEV_DOCROOT}/wp-content/languages/" >&2 || log "${YELLOW}Note: wp-content/languages not found or sync failed.${NC}"
    else
        log "${BLUE}Incomplete or empty project: Performing Full Sync...${NC}"
        rsync "${RSYNC_ARGS[@]}" "${SSH_USER}@${SSH_HOST}:${FULL_REMOTE_PATH}/" "${DDEV_COMPOSER_ROOT:-/var/www/html}/${DDEV_DOCROOT}/" >&2
    fi

    # Post-Sync: Ensure wp-config.php is DDEV compatible
    if [ -f "$WP_CONFIG_PATH" ]; then
        log "${YELLOW}Ensuring wp-config.php is DDEV compatible...${NC}"
        
        # 0. Sync table prefix from remote if missing
        if ! grep -q "\$table_prefix" "$WP_CONFIG_PATH"; then
            log "${BLUE}Extracting table prefix from remote...${NC}"
            # Use sed to clean up the line and ensure it ends with a semicolon
            REMOTE_PREFIX=$(ssh -p "${SSH_PORT:-22}" "${SSH_USER}@${SSH_HOST}" "grep \"\\\$table_prefix\" ${FULL_REMOTE_PATH}/wp-config.php | head -n 1" | sed 's/^[ \t]*//;s/[ \t]*$//')
            if [ -n "$REMOTE_PREFIX" ]; then
                log "${BLUE}Setting table prefix: $REMOTE_PREFIX${NC}"
                sed -i "/<?php/a $REMOTE_PREFIX" "$WP_CONFIG_PATH"
            else
                log "${YELLOW}Warning: Could not find table prefix on remote. Defaulting to wp_...${NC}"
                sed -i "/<?php/a \$table_prefix = 'wp_';" "$WP_CONFIG_PATH"
            fi
        fi

        # 1. Force Local DB Credentials to 'db'
        # Redirect wp-cli output to stderr
        WP_PATH_ARG="--path=${DDEV_COMPOSER_ROOT:-/var/www/html}/${DDEV_DOCROOT}"
        wp config set DB_NAME "$LOCAL_DB" "$WP_PATH_ARG" --type=constant >&2
        wp config set DB_USER "$LOCAL_DB" "$WP_PATH_ARG" --type=constant >&2
        wp config set DB_PASSWORD "$LOCAL_DB" "$WP_PATH_ARG" --type=constant >&2
        wp config set DB_HOST "$LOCAL_DB" "$WP_PATH_ARG" --type=constant >&2
        wp config set WP_HOME "$DDEV_PRIMARY_URL" "$WP_PATH_ARG" --type=constant >&2
        wp config set WP_SITEURL "${DDEV_PRIMARY_URL}/" "$WP_PATH_ARG" --type=constant >&2

        # 2. Ensure DDEV settings inclusion if missing
        if ! grep -q "wp-config-ddev.php" "$WP_CONFIG_PATH"; then
            log "${BLUE}Injecting DDEV settings inclusion...${NC}"
            # Insert before the "stop editing" line or at the end
            if grep -q "That's all, stop editing!" "$WP_CONFIG_PATH"; then
                sed -i "/That's all, stop editing!/i // Include for settings managed by ddev.\n\$ddev_settings = __DIR__ . '/wp-config-ddev.php';\nif ( ! defined( 'DB_USER' ) && getenv( 'IS_DDEV_PROJECT' ) == 'true' && is_readable( \$ddev_settings ) ) {\n\trequire_once( \$ddev_settings );\n}\n" "$WP_CONFIG_PATH"
            else
                echo -e "\n// Include for settings managed by ddev.\n\$ddev_settings = __DIR__ . '/wp-config-ddev.php';\nif ( ! defined( 'DB_USER' ) && getenv( 'IS_DDEV_PROJECT' ) == 'true' && is_readable( \$ddev_settings ) ) {\n\trequire_once( \$ddev_settings );\n}" >> "$WP_CONFIG_PATH"
            fi
        fi
    fi
    
    # Create a dummy tarball to satisfy DDEV requirement for files_pull_command
    mkdir -p "${DDEV_COMPOSER_ROOT:-/var/www/html}/.ddev/.downloads"
    touch "${DDEV_COMPOSER_ROOT:-/var/www/html}/.ddev/.downloads/.rsync-synced"
    tar -czf "${DDEV_COMPOSER_ROOT:-/var/www/html}/.ddev/.downloads/files.tar.gz" -C "${DDEV_COMPOSER_ROOT:-/var/www/html}/.ddev/.downloads" .rsync-synced >&2

    log "${GREEN}Files sync complete.${NC}"
fi
