# DDEV SSH Pull

DDEV add-on for WordPress projects with a specific directory structure.

## Installation

```bash
ddev add-on get dmind-gmbh/wp-ddev
```

## Usage

1. **Authorize SSH**: `ddev auth ssh`
2. **Run Pull**: `ddev pull dev`

The first run will interactively prompt for server details and save them to your local `.env` file.