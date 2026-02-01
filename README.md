# DDEV SSH Pull & Deployment for WordPress

A DDEV add-on that automates WordPress project setup, database/file synchronization from remote environments (dev/stage/live), and GitHub Actions deployment.

## How to use it

### 1. Installation
Run this command in your DDEV project:
```bash
ddev add-on get dmind-gmbh/wp-ddev
```

### 2. Project Setup
Run the setup wizard to configure your environment, install WordPress, and set up deployment:
```bash
ddev setup
```

### 3. Sync Content (Pull)
To pull database and files from a remote environment (dev, stage, or live):
```bash
# First, ensure your SSH keys are loaded
ddev auth ssh

# Pull from development
ddev pull dev

# Pull from staging or live
ddev pull stage
ddev pull live
```
*On the first run, you will be prompted to enter SSH and Database credentials interactively.*

---

## What it does

This add-on streamlines the WordPress development workflow by handling:

*   **Environment Syncing**: Securely pulls databases and files from remote servers via SSH. It automatically replaces domains in the database during import.
*   **Configuration Management**: Uses a split-configuration strategy:
    *   **Shared Config** (`.env.dev`): Stores non-sensitive data (host, paths, users). Committed to Git.
    *   **Secret Config** (`.env.dev.local`): Stores passwords. **Ignored** by Git.
*   **WordPress Installation**: Provides a wizard to download and install WordPress core and themes.
*   **Deployment**: Generates a GitHub Actions workflow to deploy your code to remote servers using `rsync`.
*   **Smart Ignoring**: Automatically generates a `.gitignore` optimized for this workflow.

---

## Manual Setup (File Explanation)

If you prefer to configure this manually without the add-on, you can copy the files from the `examples/` directory in this repository to your project.

### Key Files & Structure

1.  **`.ddev/providers/*.yaml`** (`dev.yaml`, `stage.yaml`, `live.yaml`)
    *   Defines the `ddev pull <env>` commands.
    *   Example: `dev.yaml` maps the `pull dev` command to the script that handles the logic.

2.  **`.ddev/providers/pull_script.sh`**
    *   The core logic script. It handles:
        *   Loading credentials from `.env.<env>` files.
        *   Dumping the remote database via SSH.
        *   Syncing files via `rsync`.
        *   Replacing database domains.

3.  **`.ddev/providers/ensure_env_config.sh`**
    *   A helper script that checks if your `.env` files exist and prompts you for credentials if they are missing.

4.  **`.ddev/commands/host/setup`**
    *   The `ddev setup` command script. Orchestrates the entire setup process (Config -> Deployment -> WordPress).

5.  **`.github/workflows/deploy.yml`**
    *   A GitHub Actions workflow file.
    *   It uses `rsync` to deploy your code to the server defined in your repository secrets (`SSH_HOST`, `SSH_USER`, `SSH_KEY`).

### Manual Installation Steps
1.  Copy the contents of `examples/.ddev` to your project's `.ddev` folder.
2.  Copy `examples/.github` to your project root (if you want deployment).
3.  Copy `examples/.gitignore` to your project root.
4.  Run `ddev restart` to register the new commands.
