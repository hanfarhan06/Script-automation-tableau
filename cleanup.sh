#!/bin/bash
source /etc/profile.d/tableau_server.sh

# Konfigurasi
LOG_DIR="/home/meepo/script/log"
LOG_FILE="$LOG_DIR/tsm-cleanup.log"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

# Pastikan direktori log ada
mkdir -p "$LOG_DIR"

# Jalankan cleanup
echo "[$DATE] Starting TSM cleanup..." >> "$LOG_FILE"
tsm maintenance cleanup -a >> "$LOG_FILE" 2>&1

# Cek status
if [ $? -eq 0 ]; then
    echo "[$DATE] TSM cleanup completed successfully." >> "$LOG_FILE"
else
    echo "[$DATE] TSM cleanup failed!" >> "$LOG_FILE"
fi
