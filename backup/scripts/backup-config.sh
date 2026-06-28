#!/bin/bash
source ./config.sh
# Homelab Automated Backup Script

# 1. Create the backup folder if it doesn't exist
mkdir -p "$BACKUP_DIR"

echo "Starting backup of $SOURCE_DIR..."

# 2. Compress the entire volumes folder into a single .tar.gz file
tar -czvf "$BACKUP_DIR/homelab_backup_$DATE.tar.gz" "$SOURCE_DIR"

echo "Backup complete: homelab_backup_$DATE.tar.gz"

# 3. Find and delete backups older than 7 days
find "$BACKUP_DIR" -type f -name "homelab_backup_*.tar.gz" -mtime +7 -exec rm {} \;

echo "Old backups cleaned up. Done!"