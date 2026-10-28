#!/bin/bash
# Kirim backup terbaru ke dev-01 setelah backup selesai
SRC_DIR="/var/opt/tableau/tableau_server/data/tabsvc/files/backups"
DEST="meepo@10.8.14.94"
DEST_PORT=2272
DEST_DIR="/var/opt/tableau/tableau_server/data/tabsvc/files/backups"
SSH_KEY="/root/.ssh/id_push"
NAME_REGEX='^[0-9]{4}\.[0-9]{2}\.[0-9]{2}\.[0-9]{2}\.[0-9]{2}-backup_tableau\.tsbak$'
LOG_FILE="/home/meepo/script/log/push-tsbak.log"
STATE_FILE="/home/meepo/script/log/push-tsbak.last"
MIN_AGE_MIN=30

SSH_OPTS="-i $SSH_KEY -p $DEST_PORT -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=30 -o ServerAliveCountMax=10"
mkdir -p "$(dirname "$LOG_FILE")"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }
die() { log "ERROR: $*"; exit 1; }
rssh() { ssh -n $SSH_OPTS "$DEST" "$@"; }

exec 9>/tmp/push-tsbak.lock; flock -n 9 || die "masih berjalan"
[ -r "$SSH_KEY" ] || die "SSH key $SSH_KEY tidak ada atau tidak terbaca"

FILE=$(ls -1 "$SRC_DIR" | grep -E "$NAME_REGEX" | sort | tail -1)
[ -n "$FILE" ] || die "tidak ada backup yang cocok"
[ -z "$(find "$SRC_DIR/$FILE" -mmin -$MIN_AGE_MIN)" ] || die "$FILE masih baru/sedang ditulis"

SIZE=$(stat -c %s "$SRC_DIR/$FILE")
[ "$(cat "$STATE_FILE" 2>/dev/null)" = "$FILE:$SIZE" ] && { log "SKIP: $FILE sudah terkirim"; exit 0; }

FINAL="restore-prod-${FILE%-backup_tableau.tsbak}.tsbak"
ERR=$(rssh "echo ok" 2>&1) || die "tidak bisa SSH ke $DEST port $DEST_PORT: $ERR"

AVAIL=$(rssh "df -B1 --output=avail '$DEST_DIR' | tail -1" | tr -d ' ')
[ "$AVAIL" -gt "$SIZE" ] || die "ruang di dev tidak cukup"

log "Mengirim $FILE ($SIZE byte) ke $DEST sebagai $FINAL"
ok=0
for i in 1 2 3 4 5; do
    rsync -a --partial --inplace --timeout=300 --bwlimit=50000 -e "ssh $SSH_OPTS" \
        "$SRC_DIR/$FILE" "$DEST:$DEST_DIR/$FINAL.part" 2>>"$LOG_FILE" && { ok=1; break; }
    log "Percobaan $i gagal, ulangi dalam 60 detik"; sleep 60
done
[ "$ok" -eq 1 ] || die "gagal mengirim setelah 5 percobaan"

[ "$(rssh "stat -c %s '$DEST_DIR/$FINAL.part'")" = "$SIZE" ] || die "ukuran di dev tidak sama"
rssh "mv '$DEST_DIR/$FINAL.part' '$DEST_DIR/$FINAL'" || die "gagal mengganti nama"

echo "$FILE:$SIZE" > "$STATE_FILE"
log "Selesai: $FINAL terkirim"
