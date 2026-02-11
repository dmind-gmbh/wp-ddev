# DDEV Pull Plugin (WordPress)

A comprehensive DDEV add-on for scaffolding WordPress projects, syncing data from remote servers via SSH, and setting up automated GitHub deployments.

## 🚀 Quick Start

### 1. Install the Add-on
```bash
ddev get dmind-gmbh/ddev-pull-plugin
```

### 2. Run the Setup Wizard
```bash
ddev setup
```
The wizard will guide you through:
- Configuring `.gitignore` for DDEV/WordPress.
- Initializing a fresh WordPress install (optional).
- Installing the **d-mind Master-Theme** and default plugins (**ACF Pro**, **dmind-fse-blocks**).
- Setting up remote server configurations (`dev`, `stage`, `live`).
- Generating GitHub Action deployment workflows for multiple environments.

## 🛠 Commands

| Command | Description |
| :--- | :--- |
| `ddev setup` | Launches the interactive project setup wizard. |
| `ddev pull [env]` | Syncs DB and Files from a remote server (`dev`, `stage`, `live`). |
| `ddev deploy [env]` | One-time initial deployment of local DB and Files to a remote server. |
| `ddev auth ssh` | Authenticates your SSH key with the DDEV web container (required for pull/push). |

## 📁 Configuration

Configuration is split into two files per environment to ensure security:
- `.env.{env}`: Shared settings (SSH Host, Paths, DB Names). **Safe to commit.**
- `.env.{env}.local`: Private secrets (SSH Ports, DB Passwords, ACF Keys). **Ignored by Git.**

## 📖 What it Does

### Scaffolding & WordPress Setup
The plugin automates the repetitive "day 0" tasks. It downloads WordPress, sets up the `wp-config.php` for DDEV, and can clone the company's master theme and block plugins. It also handles the installation of **ACF Pro** using an environment-stored license key.

### Data Synchronization (`ddev pull`)
Uses a high-performance "streaming" approach. It executes `mysqldump` on the remote server and pipes the output directly into the DDEV database, performing domain replacements on the fly. It then uses `rsync` to pull down media files and translations.

### Initial Deployment (`ddev deploy`)
Provides a safe way to perform the first deployment to a new server. It exports your local database, replaces your local `.ddev.site` domain with the remote production domain, and uploads everything via SSH.

### GitHub Deployments
Generates ready-to-use `.github/workflows/deploy-{env}.yml` files. These workflows are configured to deploy specific branches to specific servers using `rsync`, with support for environment-specific secrets.

---
*Maintained by d-mind GmbH*
