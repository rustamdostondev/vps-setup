<div align="center">

```
██╗   ██╗██████╗ ███████╗    ███████╗███████╗████████╗██╗   ██╗██████╗
██║   ██║██╔══██╗██╔════╝    ██╔════╝██╔════╝╚══██╔══╝██║   ██║██╔══██╗
██║   ██║██████╔╝███████╗    ███████╗█████╗     ██║   ██║   ██║██████╔╝
╚██╗ ██╔╝██╔═══╝ ╚════██║    ╚════██║██╔══╝     ██║   ██║   ██║██╔═══╝
 ╚████╔╝ ██║     ███████║    ███████║███████╗   ██║   ╚██████╔╝██║
  ╚═══╝  ╚═╝     ╚══════╝    ╚══════╝╚══════╝   ╚═╝    ╚═════╝ ╚═╝
```

**A beautiful interactive CLI that turns a fresh Ubuntu VPS into a production-ready backend server.**

Pick services one by one from a terminal menu — or install the whole stack with one command.

[O'zbekcha README](README.uz.md) · [Install](#install) · [Services](#what-it-installs) · [Usage](#usage)

</div>

---

## Install

One line on a fresh Ubuntu server (20.04 / 22.04 / 24.04):

```bash
curl -fsSL https://raw.githubusercontent.com/rustamdostondev/vps-setup/main/install.sh | sudo bash
```

Then launch the menu:

```bash
sudo vps
```

```
  ╭──────────────────────────────────────────────────────────╮
  │  VPS SETUP  v1.0.0                                       │
  │  Ubuntu 24.04 LTS | IP 203.0.113.10 | 2/11 ready         │
  ╰──────────────────────────────────────────────────────────╯

  ❯ ◉ System & base tools           ✓ installed
    ○ Swap (2GB)                    · not installed
    ○ Node.js                       ◐ partial
    ◉ Docker + Compose + Swarm      ✓ installed
    ○ PostgreSQL                    · not installed
    ○ Valkey (Redis)                · not installed
    ○ MinIO (S3 storage)            · not installed
    ○ Daily Postgres backup         · not installed
    ○ Nginx reverse proxy           · not installed
    ○ UFW firewall + fail2ban       ◐ partial
    ○ SSH key (CI/CD)               · not installed

  [space] select   [enter] install   [a] all/none   [r] refresh
  [c] credentials   [l] language     [q] quit
```

Navigate with **↑/↓**, mark services with **space**, hit **enter** — dependencies
are resolved automatically (choose PostgreSQL and Docker comes with it).
Interface available in **English** and **O'zbekcha**.

### Choose a version per tool

When you install Node.js, PostgreSQL, Valkey or MinIO, the tool shows the
**official release list** (fetched live from NodeSource / Docker Hub, with an
offline fallback) and lets you pick one — or choose **Custom** to type any
version you want:

```
  Choose a version — PostgreSQL
  official releases — pick one or enter your own

  ❯ 18 (current)
    17
    16
    15
    14
    Custom (type your own)…

  [↑/↓] move   [enter] OK
```

Your choice is remembered (`/etc/vps-setup/versions`), so re-installs keep the
same version. Prefer non-interactive? Pass the version as an env var:

```bash
sudo NODE_MAJOR=22 POSTGRES_VERSION=17 VALKEY_VERSION=7.2 vps install all
```

> ⚠️ Changing an **already-installed** database's major version can make the
> existing data volume unreadable — back up first (`vps info`) or start from a
> fresh volume. The tool warns you before doing this.

## What it installs

| Service | What you get |
|---|---|
| **System & base tools** | `apt` update/upgrade + git, curl, jq, htop, tmux, fail2ban, ufw |
| **Swap (2GB)** | swapfile + `vm.swappiness=10`, persistent via fstab |
| **Node.js** | from NodeSource — **version selectable** (default 24 LTS) |
| **Docker** | Docker CE + Compose v2 + single-node Swarm + log rotation |
| **PostgreSQL** | in Docker, port 5432, tuned for small VPSes — **version selectable** (default 18) |
| **Valkey (Redis)** | port 6379, AOF persistence, 256MB LRU cache — **version selectable** (default 8) |
| **MinIO** | S3-compatible storage, console via SSH tunnel, public `uploads` bucket — **version selectable** |
| **Daily backup** | `pg_dump \| gzip` → `/opt/backups`, 7 days retained |
| **Nginx** | reverse proxy :80 → your app :3000, `/files/` → MinIO, certbot ready |
| **Firewall** | UFW **with SSH-lockout protection** + fail2ban + unattended-upgrades |
| **SSH key** | ed25519 deploy key for GitHub Actions CI/CD |

All credentials (connection URLs, passwords, the CI/CD private key) land in
**`/root/server-credentials.txt`** — view them any time with `sudo vps creds`.

### Know your server — `vps info`

For each installed service, `sudo vps info` shows exactly **where things live and
how to manage them** — compose file, `.env`, Docker data volumes, ports, log
commands, restart commands, backup/restore, SSL, and more. It's a cheat-sheet
for the developer working on the box:

```
  PostgreSQL 18  ✓ installed
     Compose file:  /opt/infra/docker-compose.yml
     Secrets (.env): /opt/infra/.env   (chmod 600)
     Data (volume): infra_pg_data → /var/lib/docker/volumes/infra_pg_data/_data
     Port:          5432
     Connect:       docker exec -it postgres psql -U appuser -d appdb
     Restart:       cd /opt/infra && docker compose restart postgres
     Logs:          docker logs -f postgres
     Backups:       /opt/backups
```

`sudo vps info <service>` narrows it to one service, and it works even before a
service is installed (as a reference for where it *will* put things). In the
menu, press **`i`** on any highlighted service.

## Usage

```bash
sudo vps                        # interactive menu (recommended)
sudo vps install all            # full stack, non-interactive
sudo vps install postgres       # one service (+ its dependencies)
sudo vps install valkey minio   # several at once
sudo vps status                 # what is installed on this server
sudo vps info                   # paths, ports & management commands (all installed)
sudo vps info postgres          # same, for one service
sudo vps creds                  # show credentials
sudo vps logs                   # tail the install log
sudo vps lang en|uz             # interface language
sudo vps update                 # self-update from GitHub
vps help                        # everything else
```

### Bring your own passwords

Passwords are auto-generated by default. To use your own:

```bash
sudo POSTGRES_PASSWORD='MySecret2026x' \
     REDIS_PASSWORD='MyRedisSecret26' \
     MINIO_ROOT_PASSWORD='MyMinioSecret26' \
     vps install all
```

At least 12 characters; only letters, digits and `- _ . ! @ # % ^ * + = : ,`
are accepted (characters like `` ' " $ ` \ `` or whitespace would break
`.env`). If a `.env` already exists on the server, **its passwords are
kept** — the tool never silently overwrites credentials.

## Guarantees

- **Idempotent** — run it as many times as you want, on any server. Finished
  steps are detected and skipped; only what's missing gets done.
- **Resume-safe** — if a step fails halfway, fix the issue and re-run. It
  continues where it stopped.
- **Non-destructive** — existing configs are backed up to `*.bak.<timestamp>`
  before any change. An existing Docker `daemon.json` is left untouched so
  running containers are never restarted.
- **SSH-lockout protected** — the firewall detects your real SSH port (even a
  custom one) and refuses to enable itself until that port is allowed.

## Security notes

- PostgreSQL (5432) and Valkey (6379) are exposed publicly so external tools
  (DBeaver, your local backend) can connect. On a static IP, restrict them:
  `sudo ufw delete allow 5432/tcp && sudo ufw allow from YOUR_IP to any port 5432`
- The firewall only opens 5432/6379 if those services are actually installed.
- MinIO's S3 API and console bind to localhost only; files are served through
  nginx (`/files/`), and the console is reached via SSH tunnel:
  `ssh -L 9001:localhost:9001 root@SERVER_IP` then open `http://localhost:9001`.
- **Expose the MinIO console publicly** (browser access without a tunnel) —
  opens `http://SERVER_IP:9001` and the firewall port for it:
  ```bash
  sudo MINIO_CONSOLE_PUBLIC=1 vps install minio
  # revert to localhost-only:
  sudo MINIO_CONSOLE_PUBLIC=0 vps install minio && sudo ufw delete allow 9001/tcp
  ```
  ⚠️ This serves the console over plain HTTP — the login password travels
  unencrypted. Use a strong `MINIO_ROOT_PASSWORD`, and for anything sensitive
  prefer a domain + TLS (`certbot`) instead.
- **Expose the MinIO S3 API publicly** (so an external app / S3 client can
  reach `http://SERVER_IP:9000`) — opens 9000 and the firewall port:
  ```bash
  sudo MINIO_API_PUBLIC=1 vps install minio
  # revert to localhost-only:
  sudo MINIO_API_PUBLIC=0 vps install minio && sudo ufw delete allow 9000/tcp
  ```
  If your app runs on the **same** server you don't need this — point it at
  `localhost:9000` (or `minio:9000` inside Docker). When exposed, S3 clients
  must use **path-style** access (`forcePathStyle: true`); credentials are
  signed (not sent in clear) but object data is unencrypted over plain HTTP —
  prefer a domain + TLS for production.
- After copying `/root/server-credentials.txt` somewhere safe, delete it:
  `sudo rm /root/server-credentials.txt` (re-generate any time by re-running an install).

## For maintainers / forks

Publishing your own copy:

1. Fork or push this repo to GitHub.
2. Replace `rustamdostondev` in **four files**: `vps` (the `REPO_SLUG`
   variable), `install.sh` (the `REPO` variable and the one-liner in its
   header comment), `README.md` and `README.uz.md` (the install one-liners).
   One command from the repo root:
   ```bash
   sed -i '' 's/rustamdostondev/youruser/g' vps install.sh README.md README.uz.md   # macOS
   sed -i 's/rustamdostondev/youruser/g' vps install.sh README.md README.uz.md      # Linux
   ```
3. Done — the one-liner and `vps update` now point at your repo.

Local development without a server:

```bash
VPS_DEMO=1 ./vps            # full TUI with mocked statuses & fake installs
VPS_DEMO=1 ./vps install all
shellcheck vps install.sh   # lint
```

## License

[MIT](LICENSE)
