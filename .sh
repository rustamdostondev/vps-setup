#!/usr/bin/env bash
# =====================================================================
#
#   ██╗   ██╗██████╗ ███████╗    ███████╗███████╗████████╗██╗   ██╗██████╗
#   ██║   ██║██╔══██╗██╔════╝    ██╔════╝██╔════╝╚══██╔══╝██║   ██║██╔══██╗
#   ██║   ██║██████╔╝███████╗    ███████╗█████╗     ██║   ██║   ██║██████╔╝
#   ╚██╗ ██╔╝██╔═══╝ ╚════██║    ╚════██║██╔══╝     ██║   ██║   ██║██╔═══╝
#    ╚████╔╝ ██║     ███████║    ███████║███████╗   ██║   ╚██████╔╝██║
#     ╚═══╝  ╚═╝     ╚══════╝    ╚══════╝╚══════╝   ╚═╝    ╚═════╝ ╚═╝
#
#   Ubuntu VPS — to'liq backend muhiti, bitta buyruq bilan.
#
#   XUSUSIYATLARI:
#     ✓ IDEMPOTENT   — istalgan serverda, istalgancha marta run qilish
#                      mumkin. Bajarilgan ishlar o'tkazib yuboriladi,
#                      faqat yetishmayotganlari qilinadi.
#     ✓ RESUME-SAFE  — yarim yo'lda xato bo'lsa, qayta run qiling:
#                      skript qolgan joyidan davom etadi.
#     ✓ NON-DESTRUCTIVE — mavjud config topilsa, avval .bak.* ga
#                      backup olinadi, hech narsa yo'qolmaydi.
#
#   O'RNATADI:
#     1. Sistema update + kerakli toollar (git, curl, jq, htop...)
#     2. Swap 2GB
#     3. Node.js 24 LTS
#     4. Docker + Compose + Swarm
#     5. Infra stack (Docker): PostgreSQL 18, Valkey, MinIO
#     6. Kunlik avtomatik Postgres backup
#     7. Nginx (reverse proxy + MinIO fayl serving)
#     8. UFW firewall (SSH lockout himoyasi bilan) + fail2ban
#     9. SSH key (GitHub CI/CD uchun)
#     → Barcha credentiallar: /root/server-credentials.txt
#
#   ISHLATISH:   sudo bash vps-setup.sh
#
#   O'Z PAROLLARINGIZ BILAN (ixtiyoriy — berilmasa avto-generatsiya):
#     sudo POSTGRES_PASSWORD='MeningPgParolim2026' \
#          REDIS_PASSWORD='MeningRedisParolim2026' \
#          MINIO_ROOT_PASSWORD='MeningMinioParolim2026' \
#          bash vps-setup.sh
#
# =====================================================================
set -euo pipefail

# ---------------------------------------------------------------------
# Xato bo'lsa — qaysi bosqichda ekanini ko'rsatamiz va qayta run
# qilishni taklif qilamiz (bajarilganlar avtomatik o'tkazib yuboriladi)
# ---------------------------------------------------------------------
STEP="boshlanish"
on_error() {
  echo -e "\n\033[1;31m✗ XATO: \"${STEP}\" bosqichida to'xtadi (qator: $1)\033[0m"
  echo -e "\033[1;33m→ Muammoni ko'rib chiqing va skriptni QAYTA RUN qiling —"
  echo -e "  bajarilgan bosqichlar o'tkazib yuboriladi, davomidan boshlanadi.\033[0m"
}
trap 'on_error $LINENO' ERR

# ---------------------------------------------------------------------
# Dastlabki tekshiruvlar
# ---------------------------------------------------------------------
[[ $EUID -ne 0 ]] && { echo "❌ Root kerak: sudo bash vps-setup.sh"; exit 1; }
command -v apt-get >/dev/null || { echo "❌ Bu skript faqat Ubuntu/Debian uchun"; exit 1; }

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a   # Ubuntu 22+: "restart services?" so'roviga to'xtamaslik

# apt: config fayllar haqida so'ramasin (mavjudini saqlaydi)
APT="apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"

# IP aniqlash:
#   • LOCAL_IP  — interfeysga bog'langan IP (Swarm advertise-addr uchun; har doim mavjud)
#   • SERVER_IP — tashqi/public IP (creds va ulanish uchun); topilmasa LOCAL_IP ga tushadi
LOCAL_IP=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+' | head -1 || true)
PUBLIC_IP=$(curl -4 -s --max-time 5 ifconfig.me 2>/dev/null || true)
SERVER_IP=${PUBLIC_IP:-$LOCAL_IP}
[[ -z "$SERVER_IP" ]] && SERVER_IP=$(hostname -I | awk '{print $1}')
[[ -z "$LOCAL_IP" ]] && LOCAL_IP="$SERVER_IP"
CREDS_FILE="/root/server-credentials.txt"
INFRA_DIR="/opt/infra"
BACKUP_DIR="/opt/backups"

# ---------------------------------------------------------------------
# Yordamchi funksiyalar
# ---------------------------------------------------------------------
log()  { echo -e "\n\033[1;32m==> $1\033[0m"; }
ok()   { echo -e "\033[0;32m  ✓ $1\033[0m"; }
warn() { echo -e "\033[1;33m  ⚠ $1\033[0m"; }

# apt lock band bo'lsa kutamiz (yangi VPS'da cloud-init apt ishlatayotgan bo'ladi)
wait_for_apt() {
  local n=0
  while ! flock -n /var/lib/dpkg/lock-frontend true 2>/dev/null; do
    ((n++))
    [[ $n -eq 1 ]] && echo -n "  apt band (cloud-init?), kutilmoqda"
    [[ $n -gt 60 ]] && { echo ""; warn "apt lock 5 daqiqadan oshdi, baribir davom etamiz"; break; }
    echo -n "."; sleep 5
  done
  [[ $n -gt 0 && $n -le 60 ]] && echo " ✓"
  return 0
}

# Config yozish: mavjud fayl boshqacha bo'lsa — avval backup olamiz
write_config() {
  local dest="$1" tmp
  tmp=$(mktemp)
  cat > "$tmp"
  if [[ -f "$dest" ]] && ! cmp -s "$tmp" "$dest"; then
    cp "$dest" "${dest}.bak.$(date +%Y%m%d-%H%M%S)"
    warn "Mavjud $(basename "$dest") o'zgartirildi — eski nusxa: ${dest}.bak.*"
  fi
  mv "$tmp" "$dest"
}

echo -e "\033[1;36m"
echo "====================================================="
echo "  VPS SETUP — $(. /etc/os-release && echo "$PRETTY_NAME")"
echo "  Server IP: ${SERVER_IP}"
echo "====================================================="
echo -e "\033[0m"

# =====================================================================
# 1/9 — Sistema update + kerakli toollar
# =====================================================================
STEP="1/9 Sistema va toollar"
log "1/9 Sistema yangilanmoqda..."
wait_for_apt
$APT update
$APT upgrade

log "Kerakli toollar o'rnatilmoqda..."
wait_for_apt
$APT install \
  git curl wget unzip jq htop tmux \
  ca-certificates gnupg openssl \
  ufw fail2ban unattended-upgrades

# =====================================================================
# 2/9 — Swap 2GB
# =====================================================================
STEP="2/9 Swap"
if swapon --show | grep -q .; then
  log "2/9 Swap allaqachon mavjud"; ok "o'tkazib yuborildi"
else
  log "2/9 2GB swap yaratilmoqda..."
  fallocate -l 2G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  echo 'vm.swappiness=10' > /etc/sysctl.d/99-swap.conf
  sysctl -p /etc/sysctl.d/99-swap.conf >/dev/null
  ok "swap faol"
fi

# =====================================================================
# 3/9 — Node.js 24 LTS
# =====================================================================
STEP="3/9 Node.js"
if command -v node >/dev/null && [[ "$(node -v | cut -d. -f1)" == "v24" ]]; then
  log "3/9 Node.js 24 allaqachon mavjud"; ok "$(node -v)"
else
  log "3/9 Node.js 24 LTS o'rnatilmoqda..."
  curl -fsSL https://deb.nodesource.com/setup_24.x | bash - >/dev/null
  wait_for_apt
  $APT install nodejs
  ok "$(node -v)"
fi

# =====================================================================
# 4/9 — Docker + Compose + Swarm
# =====================================================================
STEP="4/9 Docker"
if command -v docker >/dev/null; then
  log "4/9 Docker allaqachon mavjud"; ok "$(docker --version | awk '{print $3}' | tr -d ',')"
else
  log "4/9 Docker o'rnatilmoqda..."
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list
  wait_for_apt
  $APT update
  $APT install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
systemctl enable --now docker >/dev/null 2>&1

# Log rotation — faqat daemon.json YO'Q bo'lsa yozamiz.
# (Mavjud bo'lsa tegmaymiz va dockerni restart qilmaymiz —
#  serverda ishlab turgan konteynerlar uzilmasligi uchun)
if [[ ! -f /etc/docker/daemon.json ]]; then
  cat > /etc/docker/daemon.json <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
EOF
  systemctl restart docker
  ok "log rotation sozlandi"
else
  ok "daemon.json mavjud — tegilmadi (konteynerlar uzilmasligi uchun)"
fi

STEP="4/9 Docker Swarm"
if docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null | grep -q active; then
  ok "Swarm allaqachon faol"
else
  # advertise-addr uchun interfeys IP ishlatamiz — public IP NAT ortida bo'lsa
  # ham init qulamaydi. Bo'lmasa docker o'zi tanlaydi. Swarm bitta node uchun
  # kritik emas, shu sabab oxirida faqat ogohlantirish (skript to'xtamaydi).
  if docker swarm init --advertise-addr "$LOCAL_IP" >/dev/null 2>&1 \
     || docker swarm init >/dev/null 2>&1; then
    ok "Swarm init qilindi (advertise: ${LOCAL_IP})"
  else
    warn "Swarm init o'tmadi — compose stack baribir ishlaydi. Keyin: docker swarm init"
  fi
fi

# =====================================================================
# 5/9 — Infra stack: PostgreSQL 18 + Valkey + MinIO (Docker Compose)
# =====================================================================
STEP="5/9 Infra stack (.env)"
log "5/9 Postgres 18 + Valkey + MinIO sozlanmoqda..."
mkdir -p "$INFRA_DIR" "$BACKUP_DIR"

# ---------------------------------------------------------------
# O'z parollaringizni env orqali berishingiz mumkin (headerga qarang).
# Berilgan bo'lsa — avval tekshiramiz: .env/compose'ni buzadigan
# belgilar va juda qisqa parollar qabul qilinmaydi.
# ---------------------------------------------------------------
validate_password() {
  local name="$1" val="$2"
  if [[ "$val" == *[$'\x27\x22\x24\x60\x5c\x20\t']* ]]; then
    echo "❌ ${name}: taqiqlangan belgi bor (' \" \$ \` \\ yoki bo'shliq) — .env/compose buziladi."
    echo "   Ruxsat etilgan: harflar, raqamlar va - _ . ! @ # % ^ * + = : , belgilari."
    exit 1
  fi
  if [[ ${#val} -lt 12 ]]; then
    echo "❌ ${name} juda qisqa — prod uchun kamida 12 belgi ishlating."
    exit 1
  fi
}
if [[ -n "${POSTGRES_PASSWORD:-}" ]];   then validate_password POSTGRES_PASSWORD "$POSTGRES_PASSWORD"; fi
if [[ -n "${REDIS_PASSWORD:-}" ]];      then validate_password REDIS_PASSWORD "$REDIS_PASSWORD"; fi
if [[ -n "${MINIO_ROOT_PASSWORD:-}" ]]; then validate_password MINIO_ROOT_PASSWORD "$MINIO_ROOT_PASSWORD"; fi

# .env mavjud bo'lsa — parollar SAQLANADI (idempotent)
if [[ ! -f "$INFRA_DIR/.env" ]]; then
  cat > "$INFRA_DIR/.env" <<EOF
POSTGRES_USER=${POSTGRES_USER:-appuser}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)}
POSTGRES_DB=${POSTGRES_DB:-appdb}
REDIS_PASSWORD=${REDIS_PASSWORD:-$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)}
EOF
  if [[ -n "${POSTGRES_PASSWORD:-}${REDIS_PASSWORD:-}" ]]; then
    ok ".env yaratildi — SIZ BERGAN parollar bilan"
  else
    ok ".env yaratildi — avto-generatsiya parollar bilan"
  fi
else
  ok "mavjud .env topildi — undagi parollar saqlanadi"
  if [[ -n "${POSTGRES_PASSWORD:-}${REDIS_PASSWORD:-}${MINIO_ROOT_PASSWORD:-}" ]]; then
    warn "Env orqali bergan parollaringiz QO'LLANILMADI — mavjud .env ustuvor!"
    warn "O'zgartirish: nano $INFRA_DIR/.env  keyin: cd $INFRA_DIR && docker compose up -d"
  fi
fi

# MinIO credentiallari (eski .env da bo'lmasa — qo'shiladi; env override ishlaydi)
grep -q '^MINIO_ROOT_USER=' "$INFRA_DIR/.env" || cat >> "$INFRA_DIR/.env" <<EOF
MINIO_ROOT_USER=${MINIO_ROOT_USER:-minioadmin}
MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD:-$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)}
EOF

chmod 600 "$INFRA_DIR/.env"
# shellcheck disable=SC1091
source "$INFRA_DIR/.env"

STEP="5/9 Infra stack (compose)"
write_config "$INFRA_DIR/docker-compose.yml" <<'COMPOSE'
services:

  postgres:
    image: postgres:18
    container_name: postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
    ports:
      - "5432:5432"        # tashqi toollar (DBeaver, backend) ulanishi uchun
    volumes:
      - pg_data:/var/lib/postgresql/data
    command: >
      postgres
      -c max_connections=100
      -c shared_buffers=256MB
      -c work_mem=8MB
      -c effective_cache_size=768MB
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $$POSTGRES_USER -d $$POSTGRES_DB"]
      interval: 10s
      timeout: 5s
      retries: 10

  valkey:
    image: valkey/valkey:8
    container_name: valkey
    restart: unless-stopped
    environment:
      REDIS_PASSWORD: ${REDIS_PASSWORD}
    ports:
      - "6379:6379"        # tashqi ulanish uchun
    volumes:
      - valkey_data:/data
    command: >
      valkey-server
      --requirepass ${REDIS_PASSWORD}
      --appendonly yes
      --maxmemory 256mb
      --maxmemory-policy allkeys-lru
    healthcheck:
      test: ["CMD-SHELL", "valkey-cli --no-auth-warning -a \"$$REDIS_PASSWORD\" ping | grep -q PONG"]
      interval: 10s
      timeout: 5s
      retries: 10

  minio:
    image: minio/minio:latest
    container_name: minio
    restart: unless-stopped
    environment:
      MINIO_ROOT_USER: ${MINIO_ROOT_USER}
      MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASSWORD}
    ports:
      - "127.0.0.1:9000:9000"   # S3 API  — faqat localhost (tashqariga nginx serve qiladi)
      - "127.0.0.1:9001:9001"   # Console — faqat localhost (SSH tunnel orqali)
    volumes:
      - minio_data:/data
    command: server /data --console-address ":9001"
    # Eslatma: MinIO image distroless (curl/sh yo'q) — shu sabab konteyner
    # healthcheck qo'yilmadi. Tayyorlik host tomonidan tekshiriladi (quyida).

volumes:
  pg_data:
  valkey_data:
  minio_data:
COMPOSE

# Port konflikti tekshiruvi: 5432/6379 ni docker BO'LMAGAN jarayon
# egallagan bo'lsa (masalan, serverda eski native postgres) — ogohlantiramiz
BUSY_PORTS=""
for p in 5432 6379; do
  pinfo=$(ss -ltnp "sport = :$p" 2>/dev/null | tail -n +2 || true)
  if [[ -n "$pinfo" ]] && ! grep -q docker <<<"$pinfo"; then
    BUSY_PORTS+="$p "
  fi
done
if [[ -n "$BUSY_PORTS" ]]; then
  warn "Portlar band (docker emas): ${BUSY_PORTS}— serverda native servis ishlayapti."
  warn "Compose shu portlarda ishga tusha olmasligi mumkin. Native servisni to'xtating"
  warn "yoki compose'dagi portni o'zgartiring: nano $INFRA_DIR/docker-compose.yml"
fi

STEP="5/9 Infra stack (docker compose up)"
cd "$INFRA_DIR"
if docker compose up -d; then
  ok "compose ishga tushdi"
else
  warn "Compose xatosi! Tekshiring: docker compose -f $INFRA_DIR/docker-compose.yml logs"
  warn "Muammoni hal qilib, skriptni qayta run qiling."
fi

# Servislar tayyor bo'lishini kutish (60s timeout, xato bo'lsa davom etadi)
_ready=false
echo -n "  Postgres kutilmoqda"
for _ in $(seq 1 30); do
  if docker exec postgres pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" >/dev/null 2>&1; then
    _ready=true; echo " ✓"; break
  fi
  echo -n "."; sleep 2
done
$_ready || { echo ""; warn "Postgres 60s da tayyor bo'lmadi — docker logs postgres"; }

_ready=false
echo -n "  MinIO kutilmoqda"
for _ in $(seq 1 30); do
  if curl -sf http://127.0.0.1:9000/minio/health/live >/dev/null 2>&1; then
    _ready=true; echo " ✓"; break
  fi
  echo -n "."; sleep 2
done
$_ready || { echo ""; warn "MinIO 60s da tayyor bo'lmadi — docker logs minio"; }

# Default bucket: 'uploads' — public o'qish (nginx orqali serve qilinadi)
# mc buyruqlari idempotent: bucket mavjud bo'lsa xato bermaydi (-p)
STEP="5/9 MinIO bucket"
if docker run --rm --network infra_default --entrypoint sh minio/mc:latest -c "
  mc alias set local http://minio:9000 ${MINIO_ROOT_USER} ${MINIO_ROOT_PASSWORD} >/dev/null &&
  mc mb -p local/uploads >/dev/null &&
  mc anonymous set download local/uploads >/dev/null
" 2>/dev/null; then
  ok "bucket 'uploads' tayyor (public o'qish)"
else
  warn "Bucket init o'tmadi — MinIO hali tayyor emas bo'lishi mumkin, qayta run qiling"
fi

# =====================================================================
# 6/9 — Kunlik avtomatik Postgres backup (7 kun saqlanadi)
# =====================================================================
STEP="6/9 Backup cron"
log "6/9 Kunlik backup sozlanmoqda..."
cat > /etc/cron.daily/pg-backup <<'BACKUP'
#!/usr/bin/env bash
set -e
source /opt/infra/.env
BACKUP_DIR=/opt/backups
mkdir -p "$BACKUP_DIR"
docker exec postgres pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" \
  | gzip > "$BACKUP_DIR/${POSTGRES_DB}_$(date +%F).sql.gz"
find "$BACKUP_DIR" -name "*.sql.gz" -mtime +7 -delete
BACKUP
chmod +x /etc/cron.daily/pg-backup
ok "har kuni /opt/backups ga, 7 kun saqlanadi"

# =====================================================================
# 7/9 — Nginx: reverse proxy (:3000) + MinIO fayl serving (/files/)
# =====================================================================
STEP="7/9 Nginx"
log "7/9 Nginx sozlanmoqda..."
wait_for_apt
$APT install nginx certbot python3-certbot-nginx

write_config /etc/nginx/sites-available/app <<'EOF'
server {
    listen 80 default_server;
    server_name _;

    client_max_body_size 20m;

    # Domen ulagach SSL: sudo certbot --nginx -d domen.uz

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 120s;
    }

    # MinIO — fayllarni serve qilish: http://server/files/<bucket>/<fayl>
    location /files/ {
        proxy_pass http://127.0.0.1:9000/;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        chunked_transfer_encoding off;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_connect_timeout 300;
        proxy_read_timeout 300;
    }
}
EOF
ln -sf /etc/nginx/sites-available/app /etc/nginx/sites-enabled/app
rm -f /etc/nginx/sites-enabled/default

if nginx -t >/dev/null 2>&1; then
  systemctl enable --now nginx >/dev/null 2>&1 \
    || warn "Nginx ishga tushmadi — 80-port band bo'lishi mumkin (apache2?): ss -ltnp 'sport = :80'"
  systemctl reload nginx 2>/dev/null || true
  ok "nginx tayyor (app → :3000, fayllar → /files/)"
else
  warn "nginx -t xato berdi (serverda boshqa buzilgan config bor?): nginx -t"
fi

# =====================================================================
# 8/9 — Firewall (SSH lockout himoyasi bilan) + fail2ban
# =====================================================================
STEP="8/9 Firewall"
log "8/9 Firewall sozlanmoqda..."

# --- SSH LOCKOUT HIMOYASI ---
# SSH portini avtomatik aniqlaymiz (22 yoki o'zgartirilgan bo'lishi mumkin)
SSH_PORT=$(grep -iE "^\s*Port\s+[0-9]+" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | head -1)
SSH_PORT=${SSH_PORT:-22}
# Real tinglayotgan portni ham tekshiramiz (eng ishonchli manba)
LISTEN_PORT=$(ss -tlnp 2>/dev/null | grep -m1 '"sshd"' | awk '{print $4}' | rev | cut -d: -f1 | rev)
[[ -n "${LISTEN_PORT:-}" ]] && SSH_PORT="$LISTEN_PORT"
ok "SSH port aniqlandi: ${SSH_PORT}"

ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
ufw allow "${SSH_PORT}/tcp" comment 'SSH' >/dev/null
ufw allow 80/tcp  >/dev/null
ufw allow 443/tcp >/dev/null
ufw allow 5432/tcp >/dev/null   # Postgres — tashqi ulanish
ufw allow 6379/tcp >/dev/null   # Valkey  — tashqi ulanish
# XAVFSIZROQ variant (statik IP bo'lsa):
#   ufw delete allow 5432/tcp && ufw allow from SIZNING_IP to any port 5432

# HIMOYA: SSH qoidasi tasdiqlanmaguncha firewall YOQILMAYDI
if ufw show added 2>/dev/null | grep -q "${SSH_PORT}/tcp" \
   || ufw status 2>/dev/null | grep -q "${SSH_PORT}/tcp"; then
  ufw --force enable >/dev/null
  ok "firewall faol (SSH:${SSH_PORT}, 80, 443, 5432, 6379 ochiq)"
else
  warn "SSH (${SSH_PORT}/tcp) qoidasi topilmadi — firewall YOQILMADI (lockout oldini olish)"
fi

systemctl enable --now fail2ban >/dev/null 2>&1
dpkg-reconfigure -f noninteractive unattended-upgrades >/dev/null 2>&1

# =====================================================================
# 9/9 — SSH key (GitHub CI/CD deploy uchun)
# =====================================================================
STEP="9/9 SSH key"
log "9/9 CI/CD SSH key..."
CICD_KEY="/root/.ssh/github_cicd"
mkdir -p /root/.ssh && chmod 700 /root/.ssh
if [[ -f "$CICD_KEY" ]]; then
  ok "key allaqachon mavjud"
else
  ssh-keygen -t ed25519 -f "$CICD_KEY" -N "" -C "github-cicd@$(hostname)" >/dev/null
  ok "yangi ed25519 key yaratildi"
fi
touch /root/.ssh/authorized_keys
grep -qF "$(cat "${CICD_KEY}.pub")" /root/.ssh/authorized_keys \
  || cat "${CICD_KEY}.pub" >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

# =====================================================================
# Credentials — hammasi bitta faylda
# =====================================================================
STEP="credentials fayli"
cat > "$CREDS_FILE" <<EOF
=====================================================
 SERVER CREDENTIALS — $(date)
 Server IP: ${SERVER_IP}
=====================================================

--- PostgreSQL 18 (Docker) ---
Host:      ${SERVER_IP}   Port: 5432
User:      ${POSTGRES_USER}
Database:  ${POSTGRES_DB}
Password:  ${POSTGRES_PASSWORD}
URL (tashqi):        postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${SERVER_IP}:5432/${POSTGRES_DB}
URL (serverda):      postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@localhost:5432/${POSTGRES_DB}
URL (docker ichida): postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}
  (app konteynerini 'infra_default' networkga ulang:
   docker network connect infra_default <app_container>)

--- Valkey / Redis (Docker) ---
Host:      ${SERVER_IP}   Port: 6379
Password:  ${REDIS_PASSWORD}
URL (tashqi):        redis://:${REDIS_PASSWORD}@${SERVER_IP}:6379
URL (serverda):      redis://:${REDIS_PASSWORD}@localhost:6379
URL (docker ichida): redis://:${REDIS_PASSWORD}@valkey:6379
Test:                docker exec valkey valkey-cli -a '${REDIS_PASSWORD}' ping

--- MinIO (Docker, fayl xotira) ---
S3 endpoint (serverda):      http://localhost:9000
S3 endpoint (docker ichida): http://minio:9000
Access Key:   ${MINIO_ROOT_USER}
Secret Key:   ${MINIO_ROOT_PASSWORD}
Region:       us-east-1 (default)
Bucket:       uploads  (public o'qish yoqilgan)
Public URL:   http://${SERVER_IP}/files/uploads/<fayl_nomi>
Console (faqat SSH tunnel orqali):
  ssh -L 9001:localhost:9001 root@${SERVER_IP}
  keyin brauzerda: http://localhost:9001
mc bilan boshqarish (yangi bucket, policy va h.k.):
  docker run --rm -it --network infra_default --entrypoint sh minio/mc
  mc alias set local http://minio:9000 ${MINIO_ROOT_USER} ${MINIO_ROOT_PASSWORD}

--- GitHub CI/CD (Settings → Secrets and variables → Actions) ---
SSH_HOST = ${SERVER_IP}
SSH_USER = root
SSH_PRIVATE_KEY = (pastdagini TO'LIQ nusxalang):

$(cat "$CICD_KEY")

--- Boshqaruv ---
Infra papka:     ${INFRA_DIR}  (docker compose up -d / down / logs)
Backuplar:       ${BACKUP_DIR}  (har kuni avtomatik, 7 kun)
Nginx config:    /etc/nginx/sites-available/app  (→ localhost:3000)
SSL olish:       sudo certbot --nginx -d sizning-domen.uz
Swarm worker:    docker swarm join-token worker

=====================================================
MUHIM: Bu faylni xavfsiz joyga ko'chirib oling,
keyin serverdan o'chiring:  rm ${CREDS_FILE}
=====================================================
EOF
chmod 600 "$CREDS_FILE"

# =====================================================================
# Yakuniy hisobot
# =====================================================================
STEP="yakuniy hisobot"
log "HAMMASI TAYYOR ✅"
echo "  node:      $(node -v 2>/dev/null || echo '✗')"
echo "  docker:    $(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',' || echo '✗')"
echo "  postgres:  $(docker exec postgres pg_isready -U "$POSTGRES_USER" >/dev/null 2>&1 && echo 'ishlayapti ✓' || echo 'XATO ✗')"
echo "  valkey:    $(docker exec valkey valkey-cli --no-auth-warning -a "$REDIS_PASSWORD" ping 2>/dev/null || echo 'XATO ✗')"
echo "  minio:     $(curl -sf http://127.0.0.1:9000/minio/health/live >/dev/null 2>&1 && echo 'ishlayapti ✓' || echo 'XATO ✗')"
echo "  nginx:     $(systemctl is-active nginx 2>/dev/null || echo '✗')"
echo "  swarm:     $(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || echo '✗')"
echo "  firewall:  $(ufw status 2>/dev/null | head -1 || echo '✗')"
echo ""
echo "🔑 Barcha credentiallar:  cat ${CREDS_FILE}"
echo "♻  Skriptni qayta run qilish har doim XAVFSIZ."