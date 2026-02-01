#ddev-generated
#!/bin/bash
# Interactive Wizard for GitHub Deployment

DEPLOY_FILE=".github/workflows/deploy.yml"
TEMPLATE_FILE=".ddev/templates/deploy.yml.template"

if [ -f "$DEPLOY_FILE" ]; then
    echo "Deployment workflow already exists at $DEPLOY_FILE. Skipping." > /dev/tty
    exit 0
fi

# Prompt user
echo "" > /dev/tty
echo "----------------------------------------------------------------" > /dev/tty
echo "GitHub Deployment Setup" > /dev/tty
echo "----------------------------------------------------------------" > /dev/tty
echo -n "Do you want to add a GitHub deployment workflow? [Y/n] " > /dev/tty
read -r REPLY < /dev/tty
REPLY=${REPLY:-Y}

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Skipping GitHub deployment setup." > /dev/tty
    exit 0
fi

# Ask for Destination Path
echo "" > /dev/tty
echo "Enter the absolute path on the remote server where files should be deployed." > /dev/tty
echo "Example: /var/www/html/mysite/ or /kunden/12345/webseiten/site" > /dev/tty

# Try to find a default from existing env configs
DEFAULT_PATH=""
for env in live stage dev; do
    if [ -f ".env.$env" ]; then
        # Read variables without executing the whole file
        SERVER_ROOT=$(grep "^SERVER_ROOT=" ".env.$env" | cut -d'"' -f2)
        DATA_DIR=$(grep "^DATA_DIR=" ".env.$env" | cut -d'"' -f2)
        
        # Strip potential trailing slash from server_root to avoid double slash, though rsync handles it usually
        # But we need to construct the full path
        if [ -n "$SERVER_ROOT" ]; then
             # Remove trailing slash from root if present
             SERVER_ROOT="${SERVER_ROOT%/}"
             # Ensure data dir starts with slash if root doesn't end with one, or just join.
             # Actually DATA_DIR usually starts with / (relative to root? No, relative to system root usually means absolute)
             # Wait, DATA_DIR in our config: "Enter Remote Data Directory (relative to root, usually /)"
             # So SERVER_ROOT is usually the base, DATA_DIR is / or /public_html
             
             if [[ "$DATA_DIR" == /* ]]; then
                 DEFAULT_PATH="${SERVER_ROOT}${DATA_DIR}"
             else
                 DEFAULT_PATH="${SERVER_ROOT}/${DATA_DIR}"
             fi
             break
        fi
    fi
done

if [ -n "$DEFAULT_PATH" ]; then
    echo -n "Destination Path [${DEFAULT_PATH}]: " > /dev/tty
else
    echo -n "Destination Path: " > /dev/tty
fi

read -r DEST_PATH < /dev/tty
DEST_PATH=${DEST_PATH:-$DEFAULT_PATH}

if [ -z "$DEST_PATH" ]; then
    echo "Destination path is required. Skipping." > /dev/tty
    exit 0
fi

# Collect Directories
STEPS_FILE=$(mktemp)

echo "" > /dev/tty
echo "Define directories to sync." > /dev/tty
echo "You will specify a local source directory and a remote destination (relative to the Destination Path above)." > /dev/tty
echo "Enter an empty source path to finish." > /dev/tty

while true; do
    echo "---" > /dev/tty
    echo -n "Local Source Path (e.g., webroot/wp-content/themes/): " > /dev/tty
    read -r SRC < /dev/tty
    
    if [ -z "$SRC" ]; then
        break
    fi
    
    echo -n "Remote Relative Destination (leave empty to mirror structure, e.g., webroot/wp-content/themes/): " > /dev/tty
    read -r DEST_REL < /dev/tty
    
    if [ -z "$DEST_REL" ]; then
        DEST_REL="$SRC"
    fi
    
    # Build rsync command block and append to temp file
    # Note: These are NOT redirected to tty because they build the file content
    echo "          echo \"📦 Deploying ${SRC}...\"" >> "$STEPS_FILE"
    echo "          rsync -avO \\" >> "$STEPS_FILE"
    echo "            --exclude /.git/ \\" >> "$STEPS_FILE"
    echo "            --exclude /.github/ \\" >> "$STEPS_FILE"
    echo "            -e \"ssh -o StrictHostKeyChecking=no -i ~/.ssh/deploy.key\" \\" >> "$STEPS_FILE"
    echo "            ./${SRC} \\" >> "$STEPS_FILE"
    echo "            \\\${{ env.SSH_USER }}@\\\	extvariable{env.SSH_HOST }:\\\	extvariable{env.DEST }/${DEST_REL}" >> "$STEPS_FILE"
    echo "" >> "$STEPS_FILE"
done

# If no steps were added
if [ ! -s "$STEPS_FILE" ]; then
    echo "No directories specified. Generating file with no sync steps." > /dev/tty
    echo "          echo 'No sync steps configured.'" > "$STEPS_FILE"
fi

# Ensure directory exists
mkdir -p ".github/workflows"

echo "Configuring deployment..." > /dev/tty

# Create file from template
if [ -f "$TEMPLATE_FILE" ]; then
    cp "$TEMPLATE_FILE" "$DEPLOY_FILE"
    
    # Replace Destination using perl to handle slashes safely
    export DEST_PATH
    perl -i -pe 's|\{\{DESTINATION_PATH\}\}|$ENV{DEST_PATH}|g' "$DEPLOY_FILE"
    
    # Replace Steps: Insert content of STEPS_FILE at {{RSYNC_STEPS}} and delete marker
    sed -i -e "/{{RSYNC_STEPS}}/r $STEPS_FILE" -e '//d' "$DEPLOY_FILE"
    
    echo "" > /dev/tty
    echo "✅ Created $DEPLOY_FILE" > /dev/tty
    echo "" > /dev/tty
    echo "⚠️  IMPORTANT: You must set the following Secrets in your GitHub Repository:" > /dev/tty
    echo "   - SSH_HOST" > /dev/tty
    echo "   - SSH_USER" > /dev/tty
    echo "   - SSH_KEY (Private SSH Key)" > /dev/tty
else
    echo "Error: Template $TEMPLATE_FILE not found." > /dev/tty
fi

rm "$STEPS_FILE"
echo "----------------------------------------------------------------" > /dev/tty