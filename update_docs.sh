#!/bin/bash
# Hourly docs update script
# Run via cron: 0 * * * * /home/bisenbek/projects/tinymachines/rustforhaters/update_docs.sh

set -e

cd /home/bisenbek/projects/tinymachines/rustforhaters

# Activate Python environment
source ~/.pyenv/versions/nominate/bin/activate

# Pull latest and sync docs
python sync_docs.py

# Build site with PDF generation (takes ~6 minutes for full PDF)
echo "Building site with PDF export..."
export ENABLE_PDF_EXPORT=1
mkdocs build

# PDF is generated directly to site/pdf/rust-for-haters.pdf
if [ -f site/pdf/rust-for-haters.pdf ]; then
    echo "PDF generated: site/pdf/rust-for-haters.pdf ($(du -h site/pdf/rust-for-haters.pdf | cut -f1))"
fi

# Restart mkdocs service to pick up changes
sudo systemctl restart rustforhaters-docs

echo "[$(date)] Docs updated successfully"
