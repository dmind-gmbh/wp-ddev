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

# Helper to ensure wp-config.php is local-compatible
ensure_local_config() {
    local wp_config_path="${DDEV_COMPOSER_ROOT:-/var/www/html}/${DDEV_DOCROOT}/wp-config.php"
    if [ ! -f "$wp_config_path" ]; then return 0; fi

    log "${YELLOW}Ensuring wp-config.php is DDEV compatible...${NC}"
    local wp_path_arg="--path=${DDEV_COMPOSER_ROOT:-/var/www/html}/${DDEV_DOCROOT}"
    local primary_hostname=$(echo "$DDEV_PRIMARY_URL" | sed 's|https://||;s|http://||;s|/||g')
    
    # 0. Ensure Placement Anchor exists (required for WP-CLI config set)
    if ! grep -q "That's all, stop editing!" "$wp_config_path"; then
        if grep -q "require_once ABSPATH . 'wp-settings.php'" "$wp_config_path"; then
            sed -i "/require_once ABSPATH . 'wp-settings.php'/i \/* That's all, stop editing! Happy publishing. *\/\n" "$wp_config_path"
        else
            echo -e "\n/* That's all, stop editing! Happy publishing. */" >> "$wp_config_path"
        fi
    fi

    # 1. Sync table prefix if missing
    if ! grep -q "\$table_prefix" "$wp_config_path"; then
        log "${BLUE}Table prefix missing. Extracting from remote...${NC}"
        # We need remote paths for this
        local s_root="${SERVER_ROOT%/}"
        local d_dir="${DATA_DIR#/}"
        d_dir="${d_dir%/}"
        local full_remote_path="${s_root}"
        [ -n "$d_dir" ] && full_remote_path="${s_root}/${d_dir}"
        
        local remote_prefix=$(ssh -p "${SSH_PORT:-22}" "${SSH_USER}@${SSH_HOST}" "grep \"\\\$table_prefix\" ${full_remote_path}/wp-config.php | head -n 1" | sed "s/^[ \t]*//;s/[ \t]*$//")
        if [ -n "$remote_prefix" ]; then
            local prefix_val=$(echo "$remote_prefix" | grep -o "['\"].*['\"]" | head -n 1 | tr -d "['\"]")
            wp config set table_prefix "${prefix_val:-wp_}" --type=variable "$wp_path_arg" >&2
        else
            wp config set table_prefix "wp_" --type=variable "$wp_path_arg" >&2
        fi
    fi

    # 2. Force Local DB Credentials
    wp config set DB_NAME "$LOCAL_DB" "$wp_path_arg" --type=constant >&2
    wp config set DB_USER "$LOCAL_DB" "$wp_path_arg" --type=constant >&2
    wp config set DB_PASSWORD "$LOCAL_DB" "$wp_path_arg" --type=constant >&2
    wp config set DB_HOST "$LOCAL_DB" "$wp_path_arg" --type=constant >&2
    # On a multisite the per-site URLs must come from the DB (set by Phase 3's
    # search-replace), not from global WP_HOME/WP_SITEURL constants, which would
    # pin every site to the primary domain and cause redirect loops.
    if [[ "${IS_MULTISITE:-false}" != "true" ]]; then
        wp config set WP_HOME "https://${primary_hostname}" "$wp_path_arg" --type=constant >&2
        wp config set WP_SITEURL "https://${primary_hostname}/" "$wp_path_arg" --type=constant >&2
    else
        wp config delete WP_HOME "$wp_path_arg" --type=constant >&2 || true
        wp config delete WP_SITEURL "$wp_path_arg" --type=constant >&2 || true
    fi

    # Multisite Constants
    if [[ "${IS_MULTISITE:-false}" == "true" ]]; then
        log "${BLUE}Injecting Multisite constants...${NC}"
        wp config set MULTISITE true --raw "$wp_path_arg" --type=constant >&2
        wp config set SUBDOMAIN_INSTALL "$( [ "${MULTISITE_TYPE:-subdirectory}" == "subdomain" ] && echo "true" || echo "false" )" --raw "$wp_path_arg" --type=constant >&2
        wp config set DOMAIN_CURRENT_SITE "${primary_hostname}" "$wp_path_arg" --type=constant >&2
        wp config set PATH_CURRENT_SITE "/" "$wp_path_arg" --type=constant >&2
        wp config set SITE_ID_CURRENT_SITE 1 --raw "$wp_path_arg" --type=constant >&2
        wp config set BLOG_ID_CURRENT_SITE 1 --raw "$wp_path_arg" --type=constant >&2
    fi

    # Cleanup DDEV legacy
    if grep -q "Include for settings managed by ddev" "$wp_config_path"; then
        sed -i "/Include for settings managed by ddev/,/}/d" "$wp_config_path"
    fi
    rm -f "${DDEV_COMPOSER_ROOT:-/var/www/html}/${DDEV_DOCROOT}/wp-config-ddev.php"
}

# Ensure Config exists
if [ -f "${DDEV_COMPOSER_ROOT:-/var/www/html}/.ddev/providers/ensure_env_config.sh" ]; then
    # Only prompt for config when it's missing (not on every pull)
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
    log "${BLUE}Streaming RAW remote database...${NC}"
    
    # Stream the raw dump straight to a gzip file and let DDEV import it. Domain
    # replacement happens afterwards via the post-import-db hook (MODE=replace),
    # so the DB is fixed BEFORE the (slow) files rsync starts.
    DB_OUT="${DDEV_COMPOSER_ROOT:-/var/www/html}/.ddev/.downloads/db.sql.gz"
    mkdir -p "${DDEV_COMPOSER_ROOT:-/var/www/html}/.ddev/.downloads"
    # Record which environment we pulled, so the post-import-db hook (which runs
    # in a separate process with no PULL_ENV) knows which .env to source.
    printf '%s' "$PULL_ENV" > "${DDEV_COMPOSER_ROOT:-/var/www/html}/.ddev/.downloads/.pull_env"
    ssh -q -p "${SSH_PORT:-22}" "${SSH_USER}@${SSH_HOST}" "mysqldump -u'${DB_USER}' -h'${DB_HOST}' -p'${DB_PASSWORD}' '${DB_NAME}' --no-tablespaces" | gzip > "$DB_OUT"
    
    log "${GREEN}DB sync complete.${NC}"
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
    WP_ADMIN_PATH="${DDEV_COMPOSER_ROOT:-/var/www/html}/${DDEV_DOCROOT}/wp-admin"
    WP_CONFIG_PATH="${DDEV_COMPOSER_ROOT:-/var/www/html}/${DDEV_DOCROOT}/wp-config.php"
    
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
    ensure_local_config
    
    # Create a dummy tarball to satisfy DDEV requirement for files_pull_command
    mkdir -p "${DDEV_COMPOSER_ROOT:-/var/www/html}/.ddev/.downloads"
    touch "${DDEV_COMPOSER_ROOT:-/var/www/html}/.ddev/.downloads/.rsync-synced"
    tar -czf "${DDEV_COMPOSER_ROOT:-/var/www/html}/.ddev/.downloads/files.tar.gz" -C "${DDEV_COMPOSER_ROOT:-/var/www/html}/.ddev/.downloads" .rsync-synced >&2

    log "${GREEN}Files sync complete.${NC}"
fi

# ---------------------------------------------------------
# Domain Replacement (safe search-replace)
# ---------------------------------------------------------
# Run AFTER the raw DB has been imported (via a `ddev pull ... db` then a
# post-import-db hook), so we transform the freshly imported DB in place exactly
# once, BEFORE the (slow) files rsync starts. Invoked with MODE=replace.
do_domain_replacement() {
    log "${CYAN}>> Phase 3: Domain Replacement (safe search-replace)${NC}"
    WP_PATH="${DDEV_COMPOSER_ROOT:-/var/www/html}/${DDEV_DOCROOT}"
    PRIMARY_HOSTNAME=$(echo "$DDEV_PRIMARY_URL" | sed 's|https://||;s|http://||;s|/||g')

    # Ensure wp-config.php is local-ready before we run wp-cli
    ensure_local_config

    # Deterministic canonical-domain fix via raw SQL. `wp_blogs`/`wp_site` left on
    # the live domain is what causes the "site not found -> wp-signup.php" loop,
    # and search-replace has proven not to touch them. Raw SQL always works.
    # One CASE UPDATE maps every source domain (and its bare form) in one pass;
    # exact `= domain` matching means it never touches "domain-child"-style slugs.
    if [ -n "${DOMAIN_MAPPING:-}" ]; then
        BLOG_CASE=""
        BLOG_IN=""
        IFS=',' read -ra SQLMAP <<< "$DOMAIN_MAPPING"
        for m in "${SQLMAP[@]}"; do
            m=$(echo "$m" | xargs)
            [ -n "$m" ] || continue
            old=$(echo "${m%%:*}" | xargs)
            new=$(echo "${m#*:}" | xargs)
            [ -n "$old" ] && [ -n "$new" ] || continue
            BLOG_CASE+=" WHEN domain='${old}' THEN '${new}'"
            BLOG_IN+="'${old}',"
            if [[ "$old" == www.* ]]; then
                bare="${old#www.}"
                BLOG_CASE+=" WHEN domain='${bare}' THEN '${new}'"
                BLOG_IN+="'${bare}',"
            fi
        done
        BLOG_IN="${BLOG_IN%,}"
        wp db query "UPDATE wp_blogs SET domain = CASE ${BLOG_CASE} ELSE domain END WHERE domain IN (${BLOG_IN})" --path="$WP_PATH" >&2 || true
    fi
    wp db query "UPDATE wp_site SET domain='${PRIMARY_HOSTNAME}'" --path="$WP_PATH" >&2 || true
    wp db query "UPDATE wp_sitemeta SET meta_value='https://${PRIMARY_HOSTNAME}/' WHERE meta_key='siteurl'" --path="$WP_PATH" >&2 || true
    wp db query "UPDATE wp_options SET option_value='https://${PRIMARY_HOSTNAME}' WHERE option_name IN ('home','siteurl')" --path="$WP_PATH" >&2 || true

    # Build the replacement list as protocol-relative URLs only (//host). This
    # covers http:// and https:// URLs in one pass (the // substring sits right
    # after the scheme) while never touching a bare slug like a theme folder named
    # "postlithiumstorage.org-child". We deliberately do NOT replace the bare
    # "host" substring, because it would rewrite that theme slug and silently
    # disable child-theme code.
    REPLACE_FILE=$(mktemp)
    append_pair() {
        local src="$1" dst="$2"
        [ -n "$src" ] && [ -n "$dst" ] || return
        # Strip any scheme from dst so the // form stays scheme-agnostic.
        dst=$(printf '%s' "$dst" | sed 's|^https\?://||;s|^//||')
        printf '%s|%s|%s\n' "$(( ${#src} + 2 ))" "//${src}" "//${dst}" >> "$REPLACE_FILE"
    }
    if [ -n "${DOMAIN_MAPPING:-}" ]; then
        IFS=',' read -ra MAPPINGS <<< "$DOMAIN_MAPPING"
        for mapping in "${MAPPINGS[@]}"; do
            mapping=$(echo "$mapping" | xargs)
            [ -n "$mapping" ] || continue
            src=$(echo "${mapping%%:*}" | xargs)
            dst=$(echo "${mapping#*:}" | xargs)
            append_pair "$src" "$dst"
            if [[ "$src" == www.* ]]; then
                append_pair "${src#www.}" "$dst"
            fi
        done
    elif [ -n "${SOURCE_DOMAINS:-}" ]; then
        IFS=',' read -ra DOMAINS <<< "$SOURCE_DOMAINS"
        for src in "${DOMAINS[@]}"; do
            src=$(echo "$src" | xargs)
            [ -n "$src" ] || continue
            append_pair "$src" "$PRIMARY_HOSTNAME"
            if [[ "$src" == www.* ]]; then
                append_pair "${src#www.}" "$PRIMARY_HOSTNAME"
            fi
        done
    fi

    if [ -s "$REPLACE_FILE" ]; then
        sort -t'|' -k1 -nr "$REPLACE_FILE" -o "$REPLACE_FILE"
        while IFS='|' read -r _len src dst; do
            [ -n "$src" ] && [ -n "$dst" ] || continue
            log "${BLUE}Replacing $src with $dst...${NC}"
            wp search-replace "$src" "$dst" --all-tables --recurse-objects --skip-columns=guid --path="$WP_PATH" >&2 || log "${YELLOW}Note: Safe search-replace skipped for $src.${NC}"
        done < "$REPLACE_FILE"
    fi
    rm -f "$REPLACE_FILE"

    # Hard guard: the "stylesheet"/"template" options are theme FOLDER names, not
    # URLs. If a bare domain was ever part of the child-theme slug and got
    # rewritten (leaving e.g. "polis.org.ddev.site-child" while the folder is
    # "postlithiumstorage.org-child"), the child theme silently deactivates.
    # Re-read the true theme slugs and restore them verbatim.
    for slug in stylesheet template; do
        val=$(wp option get "$slug" --path="$WP_PATH" 2>/dev/null | tr -d '\n')
        if [ -n "$val" ] && echo "$val" | grep -q '\.ddev\.site'; then
            fixed=$(echo "$val" | sed 's/\.ddev\.site//')
            wp option update "$slug" "$fixed" --path="$WP_PATH" >&2 || true
            log "${YELLOW}Restored theme '${slug}' from '${val}' to '${fixed}'.${NC}"
        fi
    done

    # Guarantee: search-replace can miss the main site's canonical home/siteurl,
    # which is exactly what sends visitors to the live domain. Set it explicitly.
    wp option update home "https://${PRIMARY_HOSTNAME}" --path="$WP_PATH" >&2 || true
    wp option update siteurl "https://${PRIMARY_HOSTNAME}" --path="$WP_PATH" >&2 || true

    # Same guarantee for each sub-site: its wp_N_options home/siteurl drives the
    # admin "My Sites" links. Set them explicitly by resolving each mapped local
    # domain (any mapping whose target isn't the primary host) to its blog.
    if [ -n "${DOMAIN_MAPPING:-}" ]; then
        IFS=',' read -ra SUBS <<< "$DOMAIN_MAPPING"
        for m in "${SUBS[@]}"; do
            m=$(echo "$m" | xargs)
            [ -n "$m" ] || continue
            local_d=$(echo "${m#*:}" | xargs)
            [ -n "$local_d" ] || continue
            [ "$local_d" != "$PRIMARY_HOSTNAME" ] || continue
            wp option update home "https://${local_d}" --url="${local_d}" --path="$WP_PATH" >&2 || true
            wp option update siteurl "https://${local_d}" --url="${local_d}" --path="$WP_PATH" >&2 || true
        done
    fi

    # Clear object cache so WPML/plugin-cached URLs don't keep pointing at stale domains.
    wp cache flush --path="$WP_PATH" >&2 || true

    log "${GREEN}Domain replacement complete.${NC}"
}

# Invoke the domain replacement only in "replace" mode (called by the
# post-import-db hook), or at the end of an "all" run as a fallback.
if [[ "$MODE" == "replace" ]]; then
    do_domain_replacement
elif [[ "$MODE" == "all" ]] && [ -f "${DDEV_COMPOSER_ROOT:-/var/www/html}/${DDEV_DOCROOT}/wp-settings.php" ]; then
    do_domain_replacement
fi
