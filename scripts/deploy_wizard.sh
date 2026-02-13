#ddev-generated
#!/bin/bash
# Interactive Wizard for GitHub Deployment (Streamlined)

TEMPLATE_FILE=".ddev/templates/deploy.yml.template"

# Prompt user
echo "" > /dev/tty
echo "----------------------------------------------------------------" > /dev/tty
echo "GitHub Deployment Setup" > /dev/tty
echo "----------------------------------------------------------------" > /dev/tty
echo -n "Do you want to add/update a GitHub deployment workflow? [Y/n] " > /dev/tty
read -r REPLY < /dev/tty
REPLY=${REPLY:-Y}

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Skipping GitHub deployment setup." > /dev/tty
    exit 0
fi

# 1. Environment Selection
echo "" > /dev/tty
echo "Select environment for this workflow:" > /dev/tty
OPTIONS=("live" "stage" "dev" "custom")
select opt in "${OPTIONS[@]}"; do
    case $opt in
        "live"|"stage"|"dev")
            ENV_NAME=$opt
            break
            ;;
        "custom")
            echo -n "Enter custom environment name: " > /dev/tty
            read -r ENV_NAME < /dev/tty
            break
            ;;
        *) echo "Invalid option $REPLY";;
    esac
done

DEPLOY_FILE=".github/workflows/deploy-${ENV_NAME}.yml"

# 2. Branch Selection
DEFAULT_BRANCH="main"
if [ "$ENV_NAME" == "dev" ]; then DEFAULT_BRANCH="develop"; fi
if [ "$ENV_NAME" == "stage" ]; then DEFAULT_BRANCH="staging"; fi

echo -n "Trigger deployment on push to branch [${DEFAULT_BRANCH}]: " > /dev/tty
read -r BRANCH_NAME < /dev/tty
BRANCH_NAME=${BRANCH_NAME:-$DEFAULT_BRANCH}

# 3. Path Detection
DOCROOT=$(grep "^docroot:" .ddev/config.yaml | awk '{print $2}' | tr -d '"' | tr -d "'")
LOCAL_ROOT="${DOCROOT:-.}"
LOCAL_ROOT="${LOCAL_ROOT%/}"

DEST_PATH=""
if [ -f ".env.${ENV_NAME}" ]; then
    S_ROOT=$(grep "^SERVER_ROOT=" ".env.${ENV_NAME}" | cut -d'"' -f2)
    D_DIR=$(grep "^DATA_DIR=" ".env.${ENV_NAME}" | cut -d'"' -f2)
    if [ -n "$S_ROOT" ]; then
        S_ROOT="${S_ROOT%/}"
        D_DIR="${D_DIR#/}"
        D_DIR="${D_DIR%/}"
        if [ -n "$D_DIR" ]; then
            DEST_PATH="${S_ROOT}/${D_DIR}"
        else
            DEST_PATH="${S_ROOT}"
        fi
    fi
fi

if [ -z "$DEST_PATH" ]; then
    echo -e "\n${YELLOW}Remote SERVER_ROOT not found in .env.${ENV_NAME}.${NC}" > /dev/tty
    echo -n "Enter absolute remote destination path: " > /dev/tty
    read -r DEST_PATH < /dev/tty
fi

# 4. Sync Steps
STEPS_FILE=$(mktemp)
echo "" > /dev/tty
echo "Define folders to sync (relative to project root)." > /dev/tty
echo "Example: wp-content/themes/child-theme-name" > /dev/tty
echo "Enter an empty path to finish." > /dev/tty

while true; do
    echo "---" > /dev/tty
    echo -n "Folder path: " > /dev/tty
    read -r FOLDER < /dev/tty
    if [ -z "$FOLDER" ]; then break; fi
    
    # Sanitize input: remove non-printable characters and control chars
    FOLDER=$(echo "$FOLDER" | tr -d '\r\n' | tr -cd '[:print:]')
    
    # Remove leading/trailing slashes
    FOLDER="${FOLDER#/}"
    FOLDER="${FOLDER%/}"
    
    # Construct paths
    # Local: uses docroot prefix if needed
    if [ -n "$LOCAL_ROOT" ] && [[ "$FOLDER" != "$LOCAL_ROOT"* ]]; then
        SRC_PATH="${LOCAL_ROOT}/${FOLDER}/"
    else
        SRC_PATH="${FOLDER}/"
    fi
    
    # Remote: relative to DEST_PATH
    DEST_REL="${FOLDER}"
    
    echo "          echo \"📦 Deploying ${FOLDER}...\"" >> "$STEPS_FILE"
    echo "          rsync -avO \\" >> "$STEPS_FILE"
    echo "            --exclude /.git/ \\" >> "$STEPS_FILE"
    echo "            --exclude /.github/ \\" >> "$STEPS_FILE"
    echo "            -e \"ssh -o StrictHostKeyChecking=no -i ~/.ssh/deploy.key\" \\" >> "$STEPS_FILE"
    echo "            ./${SRC_PATH} \\" >> "$STEPS_FILE"
    echo "            \${{ env.SSH_USER }}@\${{ env.SSH_HOST }}:\${{ env.DEST }}/${DEST_REL}" >> "$STEPS_FILE"
    echo "" >> "$STEPS_FILE"
done

if [ ! -s "$STEPS_FILE" ]; then
    echo "          echo 'No sync steps configured.'" >> "$STEPS_FILE"
fi

# 5. Secret Strategy (Always suffixed)
SUFFIX="_${ENV_NAME^^}"

# 6. Generate File
mkdir -p ".github/workflows"
if [ -f "$TEMPLATE_FILE" ]; then
    cp "$TEMPLATE_FILE" "$DEPLOY_FILE"
    
    # Replace variables
    export ENV_NAME BRANCH_NAME DEST_PATH SUFFIX
    perl -i -pe "s|\{\{ENV_NAME\}\}|$ENV{ENV_NAME}|g" "$DEPLOY_FILE"
    perl -i -pe 's|branches:.*|branches:|g' "$DEPLOY_FILE"
    perl -i -pe 's|- main|- '"$BRANCH_NAME"'|g' "$DEPLOY_FILE"
    perl -i -pe 's|\{\{DESTINATION_PATH\}\}|$ENV{DEST_PATH}|g' "$DEPLOY_FILE"
    
    # Replace secrets with suffixed versions across the whole file
    perl -i -pe "s|secrets\.SSH_HOST|secrets.SSH_HOST$SUFFIX|g" "$DEPLOY_FILE"
    perl -i -pe "s|secrets\.SSH_USER|secrets.SSH_USER$SUFFIX|g" "$DEPLOY_FILE"
    perl -i -pe "s|secrets\.SSH_KEY|secrets.SSH_KEY$SUFFIX|g" "$DEPLOY_FILE"

    # Insert steps
    sed -i -e "/{{RSYNC_STEPS}}/r $STEPS_FILE" -e '//d' "$DEPLOY_FILE"
    
    echo -e "\n✅ Created $DEPLOY_FILE" > /dev/tty
    echo -e "⚠️  Ensure these Repository Secrets are set in GitHub: SSH_HOST$SUFFIX, SSH_USER$SUFFIX, SSH_KEY$SUFFIX" > /dev/tty
else
    echo "Error: Template not found." > /dev/tty
fi

rm "$STEPS_FILE"
echo "----------------------------------------------------------------" > /dev/tty
