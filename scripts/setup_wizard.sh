#ddev-generated
#!/bin/bash
# Interactive Setup Wizard for New Projects

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "" > /dev/tty
echo "----------------------------------------------------------------" > /dev/tty
echo "Project Setup Wizard" > /dev/tty
echo "----------------------------------------------------------------" > /dev/tty
echo -n "Is this a new project setup? [y/N] " > /dev/tty
read -r REPLY < /dev/tty
REPLY=${REPLY:-N}

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Skipping new project setup."
    exit 0
fi

# ---------------------------------------------------------
# Step 1: d-mind Master Theme
# ---------------------------------------------------------
echo "" > /dev/tty
echo -e "${BLUE}Step 1: Theme Selection${NC}" > /dev/tty
echo "Do you want to download the d-mind Master-Theme?" > /dev/tty
echo "Repo: https://github.com/dmind-gmbh/dmind-wp-master" > /dev/tty
echo -n "Download and install theme? [Y/n] " > /dev/tty
read -r THEME_REPLY < /dev/tty
THEME_REPLY=${THEME_REPLY:-Y}

if [[ $THEME_REPLY =~ ^[Yy]$ ]]; then
    # Get docroot from config.yaml
    DOCROOT=$(grep "^docroot:" .ddev/config.yaml | awk '{print $2}' | tr -d '"' | tr -d "'")
    if [ -n "$DOCROOT" ] && [ "$DOCROOT" != "." ]; then
        DOCROOT="${DOCROOT}/"
    else
        DOCROOT=""
    fi
    
    THEMES_DIR="${DOCROOT}wp-content/themes"
    TARGET_DIR="${THEMES_DIR}/dmind-wp-master"
    
    # Ensure themes directory exists
    if [ ! -d "$THEMES_DIR" ]; then
        echo -e "${YELLOW}Themes directory not found at '$THEMES_DIR'. Creating it...${NC}" > /dev/tty
        mkdir -p "$THEMES_DIR"
    fi
    
    if [ -d "$TARGET_DIR" ]; then
        echo -e "${YELLOW}Target directory '$TARGET_DIR' already exists. Skipping download.${NC}" > /dev/tty
    else
        echo "Cloning dmind-wp-master..." > /dev/tty
        if git clone https://github.com/dmind-gmbh/dmind-wp-master.git "$TARGET_DIR"; then
             echo -e "${GREEN}Theme cloned successfully to '$TARGET_DIR'.${NC}" > /dev/tty
        else
             echo -e "${YELLOW}Failed to clone theme. Please check your internet connection or permissions.${NC}" > /dev/tty
        fi
    fi
fi

# Future steps can be added here...
echo "" > /dev/tty
echo -e "${GREEN}New project setup complete.${NC}" > /dev/tty