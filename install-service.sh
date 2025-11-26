#!/bin/bash
# Install the MkDocs documentation server as a systemd service
# Run with: sudo ./install-service.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_FILE="$SCRIPT_DIR/rustforhaters-docs.service"
SERVICE_NAME="rustforhaters-docs"

if [ "$EUID" -ne 0 ]; then
    echo "Please run with sudo: sudo ./install-service.sh"
    exit 1
fi

echo "Installing $SERVICE_NAME service..."

# Copy service file
cp "$SERVICE_FILE" /etc/systemd/system/

# Reload systemd
systemctl daemon-reload

# Enable and start service
systemctl enable "$SERVICE_NAME"
systemctl start "$SERVICE_NAME"

echo ""
echo "Service installed and started!"
echo ""
echo "Commands:"
echo "  sudo systemctl status $SERVICE_NAME   # Check status"
echo "  sudo systemctl restart $SERVICE_NAME  # Restart"
echo "  sudo systemctl stop $SERVICE_NAME     # Stop"
echo "  sudo journalctl -u $SERVICE_NAME -f   # View logs"
echo ""
echo "Documentation available at: http://0.0.0.0:8764"
