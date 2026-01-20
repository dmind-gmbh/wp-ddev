# DDEV Interactive SSH Pull Plugin

This DDEV add-on provides a robust, interactive way to pull databases and files from a remote production or staging server directly into your local DDEV environment.

## Features

- **Interactive First-Run**: Automatically detects missing configuration and guides you through a setup wizard.
- **Persistent Configuration**: Saves your server details to a local `.env` file so you only have to enter them once.
- **Smart Domain Replacement**: Automatically replaces production hostnames with your local DDEV hostname during the database import.
- **Flexible File Sync**: Uses `rsync` for fast file transfers with customizable ignore patterns (e.g., skipping large PDFs or ZIPs).
- **WP-Config Integration**: Optionally updates your `wp-config.php` to match DDEV's local database credentials.

## Installation

Run this command in your project root:

```bash
ddev add-on get dmind-gmbh/wp-ddev
```

## Usage

1. **Authorize SSH**: Ensure your SSH key is available to DDEV:
   ```bash
   ddev auth ssh
   ```

2. **Run the Pull**:
   ```bash
   ddev pull dev
   ```

3. **Follow the Prompts**: On the first run, the script will ask for your server details and save them to `.env`.

## Configuration

The plugin manages the following variables in your `.env` file:

- `SSH_USER` / `SSH_HOST`: Remote server access details.
- `SERVER_ROOT`: The absolute path to the webroot on the remote server.
- `SOURCE_DOMAINS`: Comma-separated list of domains to replace with your local DDEV URL.
- `IGNORED_FILES`: Default file patterns to skip during sync (e.g., `*.pdf,*.zip`).
- `IGNORE_FILES_PROMPT`: 
    - `y`: Auto-accept defaults.
    - `n`: Skip all ignores.
    - `i`: Prompt every time (Interactive).
