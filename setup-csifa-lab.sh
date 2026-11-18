cat > /root/setup-csifa-lab.sh <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

TEAMS="${TEAMS:-5}"
SSH_PORT="${SSH_PORT:-22}"
BASE="/srv/csifa"
CASE="case01"

if [[ "$EUID" -ne 0 ]]; then
  echo "Jalankan sebagai root: sudo -i"
  exit 1
fi

echo "[1] Update dan install package dasar..."
apt-get update
apt-get install -y \
  ca-certificates gnupg lsb-release openssl sudo \
  curl wget git vim nano less tree tmux screen \
  zip unzip p7zip-full xz-utils zstd \
  rsyslog logrotate cron ufw fail2ban \
  procps psmisc lsof net-tools iproute2 dnsutils \
  util-linux file time jq gawk ripgrep \
  tcpdump tshark nftables \
  python3 python3-pip python3-venv \
  gdb binutils \
  auditd audispd-plugins aide aide-common \
  sleuthkit dcfldd hashdeep \
  ewf-tools afflib-tools \
  qemu-utils parted gdisk \
  testdisk e2fsprogs \
  libimage-exiftool-perl poppler-utils qpdf \
  yara

mkdir -p "$BASE/00-admin"
touch "$BASE/00-admin/install-missing-packages.log"

install_if_available() {
  for p in "$@"; do
    if apt-cache show "$p" >/dev/null 2>&1; then
      apt-get install -y "$p"
    else
      echo "Package tidak tersedia: $p" | tee -a "$BASE/00-admin/install-missing-packages.log"
    fi
  done
}

echo "[2] Install package optional forensic..."
install_if_available foremost scalpel binwalk bulk-extractor extundelete ext4magic gddrescue volatility3

echo "[3] Konfigurasi timezone dan journald..."
timedatectl set-timezone Asia/Jakarta || true
mkdir -p /var/log/journal
sed -i 's/^#\?Storage=.*/Storage=persistent/' /etc/systemd/journald.conf
grep -q '^Storage=persistent' /etc/systemd/journald.conf || echo 'Storage=persistent' >> /etc/systemd/journald.conf
systemctl restart systemd-journald || true
systemctl enable --now rsyslog cron fail2ban || true

echo "[4] Konfigurasi firewall dasar..."
ufw allow "${SSH_PORT}/tcp" comment 'SSH Admin CSIFA'
ufw logging low
ufw --force enable

echo "[5] Siapkan Python virtual environment..."
mkdir -p /opt/venvs
python3 -m venv /opt/venvs/csifa
/opt/venvs/csifa/bin/pip install --upgrade pip setuptools wheel
/opt/venvs/csifa/bin/pip install pandas python-dateutil rich psutil scapy yara-python

if ! command -v volatility3 >/dev/null 2>&1 && ! command -v vol >/dev/null 2>&1; then
  if [[ ! -d /opt/volatility3 ]]; then
    git clone --depth 1 https://github.com/volatilityfoundation/volatility3.git /opt/volatility3
  fi
  /opt/venvs/csifa/bin/pip install -e /opt/volatility3
  cat > /usr/local/bin/vol3 <<'EOF'
#!/bin/sh
exec /opt/venvs/csifa/bin/python /opt/volatility3/vol.py "$@"
EOF
  chmod +x /usr/local/bin/vol3
fi

echo "[6] Membuat struktur folder lab..."
mkdir -p "$BASE"/{00-admin/templates,00-admin/instructor-notes,01-scenario,02-evidence-original,03-working,04-images,05-analysis,06-reports,07-tools/rules,08-transfer,09-public}
mkdir -p "$BASE/01-scenario/$CASE"
mkdir -p "$BASE/02-evidence-original/$CASE"

groupadd -f csifa
groupadd -f evidence

echo "[7] Membuat user instructor dan team..."
CRED="/root/csifa-credentials.txt"
install -m 600 /dev/null "$CRED"

if ! id instructor >/dev/null 2>&1; then
  useradd -m -s /bin/bash instructor
fi
PASS_INSTR="$(openssl rand -base64 12)"
echo "instructor:$PASS_INSTR" | chpasswd
usermod -aG sudo,csifa,evidence instructor
echo "instructor : $PASS_INSTR" >> "$CRED"

for n in $(seq -f "%02g" 1 "$TEAMS"); do
  U="team$n"
  if ! id "$U" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "$U"
  fi
  P="$(openssl rand -base64 12)"
  echo "$U:$P" | chpasswd
  usermod -aG csifa "$U"
  echo "$U : $P" >> "$CRED"
  mkdir -p "$BASE/03-working/$U"
done

echo "[8] Membuat template dokumen..."
cat > "$BASE/00-admin/templates/chain-of-custody.md" <<'EOF'
# Chain of Custody Form

Case ID:
Evidence ID:
Description:
Source System:
Collected By:
Collection Date/Time:
Timezone:
Collection Method:
Tool/Command Used:
Original Hash SHA-256:
Working Copy Hash SHA-256:
Storage Location:

| Date/Time | From | To | Action | Reason | Signature |
|---|---|---|---|---|---|
| | | | | | |
EOF

cat > "$BASE/00-admin/templates/incident-report.md" <<'EOF'
# Incident Forensic Report

## 1. Executive Summary
Ringkasan insiden, dampak, dan kesimpulan utama.

## 2. Scope
Sistem, akun, log, image, dan artifact yang dianalisis.

## 3. Evidence List
| Evidence ID | File | Hash SHA-256 | Source | Notes |
|---|---|---|---|---|

## 4. Methodology
Langkah dan tools yang digunakan.

## 5. Timeline
| Time | Event | Evidence | Interpretation |
|---|---|---|---|

## 6. Findings
Temuan utama.

## 7. Anti-Forensic Indicators
Hidden file, deleted file, timestamp manipulation, encryption, log gap.

## 8. Root Cause Analysis
Penyebab awal insiden berdasarkan bukti.

## 9. Impact
Dampak terhadap sistem, data, dan bisnis.

## 10. Recommendations
Rekomendasi remediasi dan pencegahan.

## 11. Appendix
Command, hash, screenshot, dan catatan tambahan.
EOF

cat > "$BASE/00-admin/templates/acquisition-log.md" <<'EOF'
# Acquisition Log

Case ID:
Investigator:
Date/Time:
Source:
Destination:
Method:
Tool:
Command:
Hash Before:
Hash After:
Verification Result:
Notes:
EOF

cp -a "$BASE/00-admin/templates" "$BASE/09-public/"
chgrp -R csifa "$BASE/09-public"
chmod -R g+rX "$BASE/09-public"

echo "[9] Membuat script live response..."
cat > /usr/local/bin/csifa-live-collect <<'COLLECT'
#!/usr/bin/env bash
set -u

OUT="${1:-/srv/csifa/03-working/$(whoami)/live-$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$OUT"

run() {
  local name="$1"
  shift
  {
    echo "# COMMAND: $*"
    "$@"
  } > "$OUT/${name}.txt" 2>&1 || true
}

runbash() {
  local name="$1"
  shift
  {
    echo "# COMMAND: $*"
    bash -c "$*"
  } > "$OUT/${name}.txt" 2>&1 || true
}

runbash "00_context" "date -u; date; hostname; whoami; id"
runbash "01_system" "hostnamectl; uname -a; uptime; cat /etc/os-release"
runbash "02_users" "who -a; w; last -ai | head -50; lastlog | head -50"
runbash "03_process" "ps auxww; pstree -ap"
runbash "04_network" "ip addr; ip route; ss -tulpna; ss -antp"
runbash "05_openfiles" "lsof -nP | head -300"
runbash "06_services" "systemctl --type=service --state=running"
runbash "07_firewall" "ufw status verbose; nft list ruleset"
runbash "08_authlogs" "journalctl --since '24 hours ago' --no-pager | tail -300"
runbash "09_cron" "ls -la /etc/cron* /var/spool/cron/crontabs 2>/dev/null"
runbash "10_listening" "ss -lntup"
runbash "11_env" "env"

mkdir -p "$OUT/var_log"
for f in /var/log/auth.log* /var/log/syslog* /var/log/ufw.log* /var/log/kern.log*; do
  [[ -e "$f" ]] && cp -a "$f" "$OUT/var_log/"
done

(
  cd "$OUT"
  find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS
)

echo "Live response collection saved to: $OUT"
COLLECT

chmod +x /usr/local/bin/csifa-live-collect

echo "[10] Membuat briefing kasus..."
SCEN="$BASE/01-scenario/$CASE"
ORIG="$BASE/02-evidence-original/$CASE"

cat > "$SCEN/briefing.md" <<'EOF'
# CSIFA Case 01 - Suspicious Access on Debian Server

Tanggal simulasi: 17 November 2026  
Sistem: Debian 13 Web/Internal Server  
Hostname simulasi: web01  
IP korban simulasi: 10.10.10.5  
IP eksternal mencurigakan: 203.0.113.77  

## Latar Belakang
Tim SOC menerima indikasi akses SSH tidak wajar dan file backup yang dikumpulkan oleh akun deploy.

## Tugas Peserta
1. Lakukan live response.
2. Identifikasi user, proses, koneksi, dan log yang relevan.
3. Akuisisi evidence dengan benar.
4. Verifikasi hash.
5. Analisis disk image.
6. Temukan hidden file, deleted file, encrypted file, dan network artifact.
7. Buat timeline.
8. Susun laporan investigasi.

## Flag Simulasi
Flag hanya digunakan untuk pembelajaran CTF internal.
EOF

echo "[11] Membuat mock logs..."
cat > "$ORIG/auth.log" <<'EOF'
Nov 17 09:10:01 web01 sshd[1101]: Failed password for invalid user admin from 203.0.113.77 port 51510 ssh2
Nov 17 09:10:05 web01 sshd[1102]: Failed password for deploy from 203.0.113.77 port 51511 ssh2
Nov 17 09:10:09 web01 sshd[1103]: Accepted password for deploy from 203.0.113.77 port 51512 ssh2
Nov 17 09:10:09 web01 sshd[1103]: pam_unix(sshd:session): session opened for user deploy(uid=1001) by (uid=0)
Nov 17 09:12:21 web01 sudo: deploy : TTY=pts/1 ; PWD=/home/deploy ; USER=root ; COMMAND=/usr/bin/tar -czf /tmp/backup.tgz /var/www
Nov 17 09:15:02 web01 sshd[1103]: Received disconnect from 203.0.113.77 port 51512:11: disconnected by user
Nov 17 09:15:02 web01 sshd[1103]: pam_unix(sshd:session): session closed for user deploy
EOF

cat > "$ORIG/syslog" <<'EOF'
Nov 17 09:09:50 web01 kernel: [UFW BLOCK] IN=eth0 OUT= MAC=00:11:22:33:44:55 SRC=203.0.113.77 DST=10.10.10.5 LEN=60 TOS=0x00 PROTO=TCP SPT=51500 DPT=22 WINDOW=64240 SYN
Nov 17 09:10:09 web01 systemd-logind[520]: New session 22 of user deploy.
Nov 17 09:12:25 web01 kernel: audit: type=1105 msg=audit(1794905545.000:120): pid=2201 uid=1001 auid=1001 ses=22 msg='op=PAM:session_open acct="root" exe="/usr/bin/sudo" hostname=? addr=? terminal=/dev/pts/1 res=success'
Nov 17 09:14:30 web01 systemd[1]: Started Session 22 of user deploy.
EOF

cat > "$ORIG/web-access.log" <<'EOF'
203.0.113.77 - - [17/Nov/2026:09:11:01 +0700] "GET / HTTP/1.1" 200 512 "-" "curl/8.0"
203.0.113.77 - - [17/Nov/2026:09:11:22 +0700] "GET /backup.zip HTTP/1.1" 200 2048 "-" "curl/8.0"
203.0.113.77 - - [17/Nov/2026:09:11:45 +0700] "GET /.env HTTP/1.1" 404 153 "-" "curl/8.0"
EOF

cat > "$ORIG/ufw.log" <<'EOF'
Nov 17 09:09:50 web01 kernel: [UFW BLOCK] IN=eth0 OUT= MAC=00:11:22:33:44:55 SRC=203.0.113.77 DST=10.10.10.5 PROTO=TCP SPT=51500 DPT=22 SYN
Nov 17 09:09:55 web01 kernel: [UFW BLOCK] IN=eth0 OUT= MAC=00:11:22:33:44:55 SRC=203.0.113.77 DST=10.10.10.5 PROTO=TCP SPT=51501 DPT=22 SYN
EOF

cat > "$ORIG/syslog-tampered.log" <<'EOF'
Nov 17 09:10:09 web01 systemd-logind[520]: New session 22 of user deploy.
Nov 17 09:14:59 web01 systemd[1]: Stopping User Manager for UID 1001...
Nov 17 09:16:10 web01 systemd[1]: Started Session 23 of user admin.
EOF

echo "FLAG{base64_is_not_encryption}" | base64 > "$ORIG/obfuscated_note.b64"

echo "[12] Membuat disk image ext4 simulasi..."
IMG="$ORIG/case01-ext4.dd"
dd if=/dev/zero of="$IMG" bs=1M count=192 status=none
mkfs.ext4 -F -L CSIFA_CASE01 "$IMG" >/dev/null

MNT="$(mktemp -d)"
mount -o loop "$IMG" "$MNT"

mkdir -p "$MNT/home/deploy/.cache"
mkdir -p "$MNT/webroot"
mkdir -p "$MNT/var/log"
mkdir -p "$MNT/backup"

cat > "$MNT/home/deploy/.cache/.session_notes.txt" <<'EOF'
Investigator note:
FLAG{hidden_file_found}
Attacker tried to hide artifacts in a dot-directory.
EOF

cat > "$MNT/webroot/index.html" <<'EOF'
<h1>Internal Web Server</h1>
<p>CSIFA training dummy web root.</p>
EOF

cat > "$MNT/backup/customer_dummy.csv" <<'EOF'
customer_id,name,email
1,Alice,alice@example.test
2,Bob,bob@example.test
3,Charlie,charlie@example.test
EOF

(
  cd "$MNT/backup"
  zip -q exfil-demo.zip customer_dummy.csv
)

openssl enc -aes-256-cbc -pbkdf2 -salt \
  -pass pass:'CSIFA2026!' \
  -in "$MNT/backup/customer_dummy.csv" \
  -out "$MNT/backup/customer_dummy.csv.enc"

cat > "$MNT/home/deploy/.bash_history" <<'EOF'
whoami
id
ls -la
tar -czf /tmp/backup.tgz /var/www
openssl enc -d -aes-256-cbc -pbkdf2 -in backup/customer_dummy.csv.enc -out /tmp/customer.csv
# note simulation passphrase: CSIFA2026!
exit
EOF

cat > "$MNT/var/log/app.log" <<'EOF'
2026-11-17T09:11:20+07:00 app=backup result=created file=/backup/exfil-demo.zip
2026-11-17T09:12:00+07:00 app=backup result=accessed user=deploy
EOF

echo "FLAG{deleted_file_recovered}" > "$MNT/home/deploy/deleted_note.txt"
sync

INODE_DELETED="$(stat -c %i "$MNT/home/deploy/deleted_note.txt")"
echo "$INODE_DELETED" > "$BASE/00-admin/instructor-notes/deleted_note_inode_hint.txt"

rm "$MNT/home/deploy/deleted_note.txt"

touch -d "2026-11-17 09:15:00 UTC" "$MNT/webroot/index.html"

sync
umount "$MNT"
rmdir "$MNT"

(
  cd "$ORIG"
  sha256sum "$(basename "$IMG")" > "$(basename "$IMG").sha256"
)

echo "[13] Membuat PCAP loopback lokal..."
mkdir -p "$SCEN/www"
cat > "$SCEN/www/index.html" <<'EOF'
CSIFA local web simulation
EOF
echo "dummy backup file" > "$SCEN/www/backup.zip"

PCAP="$ORIG/case01-loopback.pcap"

(
  cd "$SCEN/www"
  python3 -m http.server 8088 --bind 127.0.0.1 > /tmp/csifa-http.log 2>&1 &
  echo $! > /tmp/csifa-http.pid
)

sleep 1

tcpdump -i lo -nn -s 0 -w "$PCAP" tcp port 8088 > /tmp/csifa-tcpdump.log 2>&1 &
TPID="$!"

sleep 2
curl -s http://127.0.0.1:8088/ >/dev/null || true
curl -s http://127.0.0.1:8088/backup.zip -o /tmp/csifa-backup.zip || true
sleep 2

kill "$TPID" || true
wait "$TPID" 2>/dev/null || true

if [[ -f /tmp/csifa-http.pid ]]; then
  kill "$(cat /tmp/csifa-http.pid)" || true
fi

echo "[14] Membuat core dump proses dummy..."
mkdir -p "$ORIG/core"

CSIFA_MEM_FLAG='FLAG{core_memory_strings}' python3 -c 'import os,time; secret="FLAG{core_memory_strings}"; time.sleep(300)' &
MEM_PID="$!"
sleep 1

gcore -o "$ORIG/core/benign-python" "$MEM_PID" >/tmp/csifa-gcore.log 2>&1 || true
kill "$MEM_PID" || true

echo "[15] Membuat YARA rule sederhana..."
cat > "$BASE/07-tools/rules/csifa_flags.yar" <<'EOF'
rule CSIFA_Flag_Detection
{
    meta:
        description = "Detect dummy flags for CSIFA training"
        author = "CSIFA Instructor"
    strings:
        $flag = "FLAG{"
    condition:
        $flag
}
EOF

echo "[16] Hash seluruh evidence original..."
(
  cd "$ORIG"
  find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS
)

echo "[17] Set permission evidence original..."
chown -R root:evidence "$ORIG"
find "$ORIG" -type d -exec chmod 750 {} \;
find "$ORIG" -type f -exec chmod 440 {} \;

echo "[18] Copy evidence ke working directory tiap tim..."
for n in $(seq -f "%02g" 1 "$TEAMS"); do
  U="team$n"
  W="$BASE/03-working/$U/$CASE"
  mkdir -p "$W"
  cp -a --reflink=auto "$ORIG/." "$W/"
  cp -a "$SCEN/briefing.md" "$W/briefing.md"
  chown -R "$U:$U" "$BASE/03-working/$U"
  chmod -R u+rwX,go-rwx "$BASE/03-working/$U"
done

chgrp -R csifa "$BASE/08-transfer"
chmod 770 "$BASE/08-transfer"

echo "[19] Audit rules untuk forensic readiness..."
cat > /etc/audit/rules.d/csifa.rules <<'EOF'
-w /srv/csifa/02-evidence-original -p wa -k csifa_evidence_change
-w /etc/passwd -p wa -k identity_change
-w /etc/group -p wa -k identity_change
-w /etc/ssh/sshd_config -p wa -k sshd_config_change
EOF

augenrules --load >/dev/null 2>&1 || true
systemctl restart auditd || true

echo "[20] Selesai."
echo "Credential peserta tersimpan di: /root/csifa-credentials.txt"
echo "Base lab: /srv/csifa"
echo "Live response command: sudo csifa-live-collect"
echo "Jumlah tim: $TEAMS"
BASH

chmod +x /root/setup-csifa-lab.sh
