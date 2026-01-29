#ddev-generated
#!/bin/bash
# Generate .gitignore based on docroot

# Get docroot from config
DOCROOT=$(grep "^docroot:" .ddev/config.yaml | awk '{print $2}' | tr -d '"' | tr -d "'")

# Normalize docroot (add trailing slash if not empty and not just dot)
if [ -n "$DOCROOT" ] && [ "$DOCROOT" != "." ]; then
    DOCROOT="${DOCROOT}/"
else
    DOCROOT=""
fi

TEMPLATE=".ddev/templates/gitignore.template"
TARGET=".gitignore"

if [ ! -f "$TARGET" ]; then
    echo "Creating .gitignore from template..."
    if [ -f "$TEMPLATE" ]; then
        sed "s|{{DOCROOT}}|$DOCROOT|g" "$TEMPLATE" > "$TARGET"
        echo ".gitignore created."
    else
        echo "Error: Template $TEMPLATE not found."
    fi
else
    echo ".gitignore already exists. Skipping creation."
fi
