#ddev-generated
#!/bin/bash
# Interactive Wizard for GitHub Deployment (Multi-Server Support)

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

# 3. Destination Path
echo "" > /dev/tty
echo "Enter the absolute path on the remote server for ${ENV_NAME}." > /dev/tty

# Try to find a default from existing env configs
DEFAULT_PATH=""
if [ -f ".env.${ENV_NAME}" ]; then
    SERVER_ROOT=$(grep "^SERVER_ROOT=" ".env.${ENV_NAME}" | cut -d'"' -f2)
    DATA_DIR=$(grep "^DATA_DIR=" ".env.${ENV_NAME}" | cut -d'"' -f2)
    if [ -n "$SERVER_ROOT" ]; then
        SERVER_ROOT="${SERVER_ROOT%/}"
        if [[ "$DATA_DIR" == /* ]]; then DEFAULT_PATH="${SERVER_ROOT}${DATA_DIR}"; else DEFAULT_PATH="${SERVER_ROOT}/${DATA_DIR}"; fi
    fi
fi

if [ -n "$DEFAULT_PATH" ]; then
    echo -n "Destination Path [${DEFAULT_PATH}]: " > /dev/tty
else
    echo -n "Destination Path: " > /dev/tty
fi

read -r DEST_PATH < /dev/tty
DEST_PATH=${DEST_PATH:-$DEFAULT_PATH}

# 4. Sync Steps
STEPS_FILE=$(mktemp)
echo "" > /dev/tty
echo "Define directories to sync for ${ENV_NAME}." > /dev/tty
echo "Enter an empty source path to finish." > /dev/tty

while true; do
    echo "---" > /dev/tty
    echo -n "Local Source Path (e.g., webroot/wp-content/themes/): " > /dev/tty
    read -r SRC < /dev/tty
    if [ -z "$SRC" ]; then break; fi
    
    echo -n "Remote Relative Destination [${SRC}]: " > /dev/tty
    read -r DEST_REL < /dev/tty
    DEST_REL=${DEST_REL:-$SRC}
    
    echo "          echo \"📦 Deploying ${SRC}...\"" >> "$STEPS_FILE"
    echo "          rsync -avO \\" >> "$STEPS_FILE"
    echo "            --exclude /.git/ \\" >> "$STEPS_FILE"
    echo "            --exclude /.github/ \\" >> "$STEPS_FILE"
    echo "            -e \"ssh -o StrictHostKeyChecking=no -i ~/.ssh/deploy.key\" \\" >> "$STEPS_FILE"
    echo "            ./${SRC} \\" >> "$STEPS_FILE"
    echo "            \${{ env.SSH_USER }}@\${{ env.SSH_HOST }}:\${{ env.DEST }}/${DEST_REL}" >> "$STEPS_FILE"
    echo "" >> "$STEPS_FILE"
done

if [ ! -s "$STEPS_FILE" ]; then
    echo "          echo 'No sync steps configured.'" >> "$STEPS_FILE"
fi

# 5. Secret Strategy
echo "" > /dev/tty
echo "Secret Naming Strategy:" > /dev/tty
echo "1) Use generic SSH_HOST, SSH_USER (for single server setups)" > /dev/tty
echo "2) Use environment-specific SSH_HOST_${ENV_NAME^^}, SSH_USER_${ENV_NAME^^}" > /dev/tty
echo -n "Choice [1/2]: " > /dev/tty
read -r SECRET_CHOICE < /dev/tty
SECRET_CHOICE=${SECRET_CHOICE:-1}

if [ "$SECRET_CHOICE" == "2" ]; then
    SUFFIX="_${ENV_NAME^^}"
else
    SUFFIX=""
fi

# 6. Generate File
mkdir -p ".github/workflows"
if [ -f "$TEMPLATE_FILE" ]; then
    cp "$TEMPLATE_FILE" "$DEPLOY_FILE"
    
    # Replace variables
    export ENV_NAME BRANCH_NAME DEST_PATH SUFFIX
    perl -i -pe "s|name: .*|name: 🚀 Deploy to $ENV_NAME|g" "$DEPLOY_FILE"
    perl -i -pe 's|branches:.*|branches:|g' "$DEPLOY_FILE"
    perl -i -pe 's|- main|- '"$BRANCH_NAME"'|g' "$DEPLOY_FILE"
    perl -i -pe 's|\{\{DESTINATION_PATH\}\}|$ENV{DEST_PATH}|g' "$DEPLOY_FILE"
    perl -i -pe 's|SSH_HOST: \$\{\{ secrets\.SSH_HOST \}\}|SSH_HOST: \$\{\{ secrets.SSH_HOST'"$SUFFIX"' \}\}|g' "$DEPLOY_FILE"
    perl -i -pe 's|SSH_USER: \$\{\{ secrets\.SSH_USER \}\}|SSH_USER: \$\{\{ secrets.SSH_USER'"$SUFFIX"' \}\}|g' "$DEPLOY_FILE"
    perl -i -pe 's|SSH_KEY: \$\{\{ secrets\.SSH_KEY \}\}|SSH_KEY: \$\{\{ secrets.SSH_KEY'"$SUFFIX"' \}\}|g' "$DEPLOY_FILE"
    
    # Secret check step updates
    perl -i -pe 's|secrets\.SSH_HOST|secrets.SSH_HOST'"$SUFFIX"'|g' "$DEPLOY_FILE"
    perl -i -pe 's|secrets\.SSH_USER|secrets.SSH_USER'"$SUFFIX"'|g' "$DEPLOY_FILE"
    perl -i -pe 's|secrets\.SSH_KEY|secrets.SSH_KEY'"$SUFFIX"'|g' "$DEPLOY_FILE"

    # Insert steps
    sed -i -e "/{{RSYNC_STEPS}}/r $STEPS_FILE" -e '//d' "$DEPLOY_FILE"
    
    echo -e "\n✅ Created $DEPLOY_FILE" > /dev/tty
    echo -e "⚠️  Ensure these Secrets are set in GitHub: SSH_HOST$SUFFIX, SSH_USER$SUFFIX, SSH_KEY$SUFFIX" > /dev/tty
else
    echo "Error: Template not found." > /dev/tty
fi

rm "$STEPS_FILE"
echo "----------------------------------------------------------------" > /dev/tty
