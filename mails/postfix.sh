#!/usr/bin/env bash
# install_postfix.sh
# Install Postfix + Mailutils and restart with `service` (for GCP Shell)

set -euo pipefail

echo "Updating package lists..."
sudo apt-get update -y

echo "Installing Postfix and Mailutils (non-interactive)..."
# Preseed Postfix install to avoid config prompt
echo "postfix postfix/main_mailer_type string 'Internet Site'" | sudo debconf-set-selections
echo "postfix postfix/mailname string $(hostname -f)" | sudo debconf-set-selections

sudo DEBIAN_FRONTEND=noninteractive apt-get install -y postfix mailutils

echo "Ensuring myhostname is set..."
if ! grep -q '^myhostname' /etc/postfix/main.cf; then
  echo "myhostname = $(hostname -f)" | sudo tee -a /etc/postfix/main.cf >/dev/null
fi

echo "Restarting Postfix..."
sudo service postfix restart

echo "Checking Postfix status..."
sudo service postfix status

echo "Installation complete. Postfix + Mailutils installed and restarted."