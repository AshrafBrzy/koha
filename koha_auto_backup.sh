#!/bin/bash

# ==============================================================================
# Koha Automated Backup Script (Date-Folder Structure)
# ==============================================================================
# Author:      Ashraf
# License:     Creative Commons Attribution 4.0 International (CC BY 4.0)
#              You are free to:
#              - Share: copy and redistribute the material in any medium or format
#              - Adapt: remix, transform, and build upon the material
#              Under the following terms: You must give appropriate credit.
# ==============================================================================
# Function:
# 1. Create a single directory named with current DATE/TIME.
# 2. Dump all databases and configs into this specific directory.
# 3. Handle system files and variable data in the same directory.
# 4. [Optional] Backup Source Code on demand.
# 5. Retention: Keep last X backup directories, delete oldest.
# ==============================================================================
# INSTALLATION & CRONJOB USAGE:
# ------------------------------------------------------------------------------
# 1. Save this script to a secure location, e.g., /usr/local/bin/koha_auto_backup.sh
# 2. Make it executable:
#    sudo chmod +x /usr/local/bin/koha_auto_backup.sh
#
# 3. Add to Cronjob (Automated Scheduling):
#    Run: sudo crontab -e
#
#    Add the following line to run daily at 3:00 AM:
#    0 3 * * * /usr/local/bin/koha_auto_backup.sh
#
#    (Optional) Add this line to backup Source Code once a month (1st day at 4 AM):
#    0 4 1 * * /usr/local/bin/koha_auto_backup.sh --source
# ==============================================================================

set -o pipefail

# --- Configuration ---

BACKUP_BASE_DIR="/home/backup_koha"
RETENTION_COUNT=10
LOG_FILE="/var/log/koha_backup.log"
DATE=$(date +%Y-%m-%d_%H-%M)

# The specific folder for THIS backup session
CURRENT_BACKUP_DIR="$BACKUP_BASE_DIR/$DATE"

# ------------------------------------------------------------------------------

log_message() {
    echo "[$DATE] $1" >> "$LOG_FILE"
    echo "$1"
}

if [[ $EUID -ne 0 ]]; then
   echo "ERROR: This script must be run as root." 
   exit 1
fi

log_message "--- Starting Backup Process (Folder: $DATE) ---"

# Create the specific directory for today's backup
if [ ! -d "$CURRENT_BACKUP_DIR" ]; then
    mkdir -p "$CURRENT_BACKUP_DIR"
    log_message "Created backup directory: $CURRENT_BACKUP_DIR"
fi

# ==============================================================================
# PART 1: Koha Instances (Databases & Instance Configs)
# ==============================================================================
INSTANCES=$(koha-list)

if [ -z "$INSTANCES" ]; then
    log_message "WARNING: No Koha instances found."
else
    for name in $INSTANCES; do
        log_message "Processing instance: $name"
        
        # 1. Database
        # Filename format: instance_db.sql.gz (Date is already in folder name)
        DB_FILE="$CURRENT_BACKUP_DIR/${name}_db.sql.gz"
        
        if mysqldump --single-transaction --add-drop-table "koha_$name" | gzip > "$DB_FILE"; then
            log_message "  [OK] Database dumped: $DB_FILE"
        else
            log_message "  [ERROR] Failed to dump database for $name"
            rm -f "$DB_FILE"
        fi

        # 2. Site Config
        CONF_FILE="$CURRENT_BACKUP_DIR/${name}_conf.tar.gz"
        if [ -d "/etc/koha/sites/$name" ]; then
            tar -czf "$CONF_FILE" -C /etc/koha/sites/ "$name" 2>/dev/null
            log_message "  [OK] Config backed up: $CONF_FILE"
        fi
    done
fi

# ==============================================================================
# PART 2: System Files & Variable Data
# ==============================================================================
log_message "Processing System & Variable Data..."

# List of directories to backup
# Format: "SourcePath|FilenamePrefix"
declare -a SYS_PATHS=(
    "/etc/koha|system_etc_koha"
    "/etc/apache2|system_etc_apache2"
    "/var/lib/koha|system_var_lib_koha"
    "/var/log/koha|system_var_log_koha"
    "/var/cache/koha|system_var_cache_koha"
)

for entry in "${SYS_PATHS[@]}"; do
    src="${entry%%|*}"
    prefix="${entry##*|}"
    dest="$CURRENT_BACKUP_DIR/${prefix}.tar.gz"
    
    if [ -d "$src" ]; then
        tar -czf "$dest" "$src" 2>/dev/null || true
        if [ -f "$dest" ]; then
            log_message "  [OK] Backed up $src"
        else
            log_message "  [ERROR] Failed to create backup for $src"
        fi
    else
        log_message "  [SKIP] Source directory not found: $src"
    fi
done

# ==============================================================================
# PART 3: Source Code (On Demand)
# Run script with '--source' to trigger this part
# ==============================================================================
if [[ "$1" == "--source" ]]; then
    log_message "--- Source Code Backup Requested ---"
    
    SRC_PATH="/usr/share/koha"
    DEST_FILE="$CURRENT_BACKUP_DIR/source_usr_share_koha.tar.gz"
    
    if [ -d "$SRC_PATH" ]; then
        log_message "  Archiving $SRC_PATH..."
        tar -czf "$DEST_FILE" "$SRC_PATH" 2>/dev/null
        log_message "  [OK] Source code backed up: $DEST_FILE"
    else
        log_message "  [ERROR] Source path not found: $SRC_PATH"
    fi
fi

# ==============================================================================
# PART 4: Retention Policy (Clean Old Directories)
# ==============================================================================
log_message "Checking retention policy (Max $RETENTION_COUNT backups)..."

# Count directories inside BACKUP_BASE_DIR that look like dates (YYYY-MM-DD_HH-MM)
# We use a glob pattern [0-9][0-9][0-9][0-9]-* to avoid deleting other random folders
# ls -1d returns the full path, so we process it carefully.

# Go to base dir to list folders easily
cd "$BACKUP_BASE_DIR" || exit 1

# List directories matching date pattern, sorted by name (oldest first)
# Note: Since format is YYYY-MM-DD, alphabetical sort IS chronological sort.
DIRS=$(ls -1d 20[0-9][0-9]-[0-1][0-9]-[0-3][0-9]_* 2>/dev/null)
DIR_COUNT=$(echo "$DIRS" | grep -c '^')

if [ "$DIR_COUNT" -gt "$RETENTION_COUNT" ]; then
    REMOVE_COUNT=$((DIR_COUNT - RETENTION_COUNT))
    log_message "  -> Found $DIR_COUNT backups. Removing oldest $REMOVE_COUNT..."
    
    # List again, take the top N (head), and remove them
    ls -1d 20[0-9][0-9]-[0-1][0-9]-[0-3][0-9]_* | head -n "$REMOVE_COUNT" | while read -r old_dir; do
        log_message "     Deleting old backup folder: $old_dir"
        rm -rf "$old_dir"
    done
else
    log_message "  -> Backup count ($DIR_COUNT) is within limit ($RETENTION_COUNT). No deletion needed."
fi

log_message "--- Backup process completed successfully ---"
exit 0
