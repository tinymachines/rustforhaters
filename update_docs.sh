#!/bin/bash
# Hourly docs update script
# Run via cron: 0 * * * * /home/bisenbek/projects/tinymachines/rustforhaters/update_docs.sh

set -e

cd /home/bisenbek/projects/tinymachines/rustforhaters

# Activate Python environment
source ~/.pyenv/versions/nominate/bin/activate

# Pull latest and sync docs
python sync_docs.py

# Restart mkdocs service to pick up changes
sudo systemctl restart rustforhaters-docs

echo "[$(date)] Docs updated successfully"
