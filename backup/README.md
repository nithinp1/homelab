# Backup Script

This folder contains a simple shell script that creates a compressed backup archive of a source directory and removes older backups automatically.

## What the script does

The script:
- creates the backup destination folder if it does not exist
- creates a timestamped archive named `homelab_backup_<date>.tar.gz`
- stores the archive in the configured backup directory
- deletes backup files older than 7 days

## Configure the script

Edit [backup/scripts/config.sh](backup/scripts/config.sh) and set the following values using absolute paths:

- `BACKUP_DIR`: where the backup archives should be saved
- `SOURCE_DIR`: the directory you want to archive
- `DATE`: this is generated automatically from the current date and time

Example:

```bash
BACKUP_DIR="/home/USER/docker_backups"
SOURCE_DIR="/home/USER/volumes"
```

## Run the backup

From the scripts directory:

```bash
cd /workspaces/homelab/backup/scripts
chmod +x backup-config.sh
./backup-config.sh
```

The script will create a backup archive in the backup directory and print status messages while it runs.

## Notes

- Use absolute paths for both `BACKUP_DIR` and `SOURCE_DIR` (e.g., /home/username/docker_backups instead of ./docker_backup). Using relative paths can cause critical errors, especially when running with root privileges.
- Run the script with appropriate permissions if the target directories require `sudo`.
- The archive format is `.tar.gz`, which is suitable for simple backups of folders and volumes.
