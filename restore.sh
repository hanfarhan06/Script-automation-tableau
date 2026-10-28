#!/bin/bash
# Restore backup prod yang sudah dikirim ke folder backups lokal
# Pemakaian: restore-tsm.sh [--dry-run] [--yes] [--force] [--file restore-prod-XXXX.tsbak]

[ -f /etc/profile.d/tableau_server.sh ] && source /etc/profile.d/tableau_server.sh

BACKUP_DIR="/var/opt/tableau/tableau_server/data/tabsvc/files/backups"
COPY_PREFIX="restore-prod-"
LOG_DIR="/home/meepo/script/log"
LOG_FILE="$LOG_DIR/restore-tsm.log"
STATE_FILE="$LOG_DIR/restore-tsm.last"
LOCK_FILE="/var/lock/restore-tsm.lock"
MIN_AGE_MIN=10
KEEP_COPIES=2
RESTORE_TIMEOUT=14400
STOP_BEFORE=1

YES=0; DRY_RUN=0; FORCE=0; FILE_ARG=""
while [ $# -gt 0 ]; do
    case "$1" in
        --yes) YES=1 ;; --dry-run) DRY_RUN=1 ;; --force) FORCE=1 ;;
        --file) FILE_ARG="$(basename "$2")"; shift ;;
        *) echo "Argumen tidak dikenal: $1"; exit 1 ;;
    esac
    shift
done

mkdir -p "$LOG_DIR"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }
die() { log "ERROR: $*"; exit 1; }

[ "$(id -u)" -eq 0 ] || die "jalankan sebagai root"
exec 9>"$LOCK_FILE"; flock -n 9 || die "script ini sedang berjalan"
command -v tsm >/dev/null || die "perintah tsm tidak ditemukan"

if [ -n "$FILE_ARG" ]; then
    FILE="$FILE_ARG"
else
    FILE=$(ls -1 "$BACKUP_DIR" | grep -E "^${COPY_PREFIX}[0-9.]+\.tsbak$" | sort | tail -1)
fi
[ -n "$FILE" ] && [ -f "$BACKUP_DIR/$FILE" ] || die "tidak ada file ${COPY_PREFIX}*.tsbak di $BACKUP_DIR"

[ -z "$(find "$BACKUP_DIR/$FILE" -mmin -$MIN_AGE_MIN)" ] || die "$FILE baru diubah (< $MIN_AGE_MIN menit)"
SIZE=$(stat -c %s "$BACKUP_DIR/$FILE")

if [ "$FORCE" -ne 1 ] && [ "$(cat "$STATE_FILE" 2>/dev/null)" = "$FILE:$SIZE" ]; then
    log "SKIP: $FILE sudah pernah di-restore (pakai --force untuk mengulang)"; exit 0
fi

log "Rencana: restore $FILE ($SIZE byte) (DRY_RUN=$DRY_RUN)"
[ "$DRY_RUN" -eq 1 ] && exit 0

if [ "$YES" -ne 1 ]; then
    [ -t 0 ] || die "mode non-interaktif, gunakan --yes"
    read -r -p "Restore MENIMPA semua data di $(hostname). Ketik RESTORE untuk lanjut: " ANS
    [ "$ANS" = "RESTORE" ] || die "dibatalkan"
fi

chown tableau:tableau "$BACKUP_DIR/$FILE"; chmod 660 "$BACKUP_DIR/$FILE"

if [ "$STOP_BEFORE" = "1" ]; then
    log "tsm stop ..."
    tsm stop 2>&1 | tee -a "$LOG_FILE"
    [ "${PIPESTATUS[0]}" -eq 0 ] || die "tsm stop gagal"
fi

log "tsm maintenance restore --file $FILE ..."
tsm maintenance restore --file "$FILE" --request-timeout "$RESTORE_TIMEOUT" 2>&1 | tee -a "$LOG_FILE"
RC=${PIPESTATUS[0]}

log "tsm start ..."
tsm start 2>&1 | tee -a "$LOG_FILE"

if [ "$RC" -ne 0 ]; then
    tsm status -v 2>&1 | tee -a "$LOG_FILE"
    die "restore gagal (kode $RC), cek log di atas"
fi

echo "$FILE:$SIZE" > "$STATE_FILE"
log "Restore selesai: $FILE"
tsm status -v 2>&1 | tee -a "$LOG_FILE"

ls -1 "$BACKUP_DIR"/${COPY_PREFIX}*.tsbak 2>/dev/null | sort -r | tail -n +$((KEEP_COPIES + 1)) | while read -r old; do
    rm -f -- "$old" && log "Deleted salinan lama: $old"
done
