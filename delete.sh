#!/bin/bash
# delete-tsbak.sh: hapus salinan backup prod (restore-prod-*.tsbak) yang lama di dev-01

BACKUP_DIR="/var/opt/tableau/tableau_server/data/tabsvc/files/backups"
PREFIX="restore-prod-"
KEEP=7                       # jumlah salinan terbaru yang disimpan
LOG_DIR="/home/meepo/script/log"
LOG_FILE="$LOG_DIR/delete-backup.log"
DRY_RUN="${DRY_RUN:-0}"      # 1 = hanya tampilkan, tidak menghapus

mkdir -p "$LOG_DIR"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

# Jangan jalan kalau restore sedang berlangsung (pakai lock yang sama dengan restore-tsm.sh)
exec 9>/var/lock/restore-tsm.lock
flock -n 9 || { log "SKIP: restore sedang berjalan"; exit 0; }

cd "$BACKUP_DIR" || { log "ERROR: tidak bisa masuk ke $BACKUP_DIR"; exit 1; }

# Salinan lengkap, terbaru di atas (tanggal dan jam ada di nama file)
mapfile -t FILES < <(ls -1 | grep -E "^${PREFIX}[0-9.]+\.tsbak$" | sort -r)
log "Ditemukan ${#FILES[@]} salinan, yang disimpan: $KEEP (DRY_RUN=$DRY_RUN)"

if [ "${#FILES[@]}" -gt "$KEEP" ]; then
    for f in "${FILES[@]:$KEEP}"; do
        if [ "$DRY_RUN" = "1" ]; then
            log "DRY RUN, akan dihapus: $f"
        elif rm -f -- "$f"; then
            log "Deleted: $f"
        else
            log "GAGAL menghapus: $f"
        fi
    done
fi

# Sisa transfer yang gagal (.part) dan lebih tua dari 1 hari
find . -maxdepth 1 -name "${PREFIX}*.tsbak.part" -mmin +1440 | while read -r p; do
    if [ "$DRY_RUN" = "1" ]; then
        log "DRY RUN, akan dihapus sisa transfer: $p"
    else
        rm -f -- "$p" && log "Deleted sisa transfer: $p"
    fi
done
