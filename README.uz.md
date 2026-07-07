<div align="center">

```
██╗   ██╗██████╗ ███████╗    ███████╗███████╗████████╗██╗   ██╗██████╗
██║   ██║██╔══██╗██╔════╝    ██╔════╝██╔════╝╚══██╔══╝██║   ██║██╔══██╗
██║   ██║██████╔╝███████╗    ███████╗█████╗     ██║   ██║   ██║██████╔╝
╚██╗ ██╔╝██╔═══╝ ╚════██║    ╚════██║██╔══╝     ██║   ██║   ██║██╔═══╝
 ╚████╔╝ ██║     ███████║    ███████║███████╗   ██║   ╚██████╔╝██║
  ╚═══╝  ╚═╝     ╚══════╝    ╚══════╝╚══════╝   ╚═╝    ╚═════╝ ╚═╝
```

**Yangi Ubuntu VPS'ni production-ga tayyor backend serverga aylantiruvchi chiroyli interaktiv CLI.**

Terminal menyusidan servislarni birma-bir tanlang — yoki butun stackni bitta buyruq bilan o'rnating.

[English README](README.md) · [O'rnatish](#ornatish) · [Servislar](#nima-ornatadi) · [Ishlatish](#ishlatish)

</div>

---

## O'rnatish

Yangi Ubuntu serverda (20.04 / 22.04 / 24.04) bitta qator:

```bash
curl -fsSL https://raw.githubusercontent.com/rustamdostondev/vps-setup/main/install.sh | sudo bash
```

Keyin menyuni oching:

```bash
sudo vps
```

```
  ╭──────────────────────────────────────────────────────────╮
  │  VPS SETUP  v1.0.0                                       │
  │  Ubuntu 24.04 LTS | IP 203.0.113.10 | 2/11 tayyor        │
  ╰──────────────────────────────────────────────────────────╯

  ❯ ◉ Tizim va bazaviy toollar      ✓ o'rnatilgan
    ○ Swap (2GB)                    · o'rnatilmagan
    ○ Node.js                       ◐ qisman
    ◉ Docker + Compose + Swarm      ✓ o'rnatilgan
    ○ PostgreSQL                    · o'rnatilmagan
    ○ Valkey (Redis)                · o'rnatilmagan
    ○ MinIO (S3 xotira)             · o'rnatilmagan
    ○ Kunlik Postgres backup        · o'rnatilmagan
    ○ Nginx reverse proxy           · o'rnatilmagan
    ○ UFW firewall + fail2ban       ◐ qisman
    ○ SSH key (CI/CD)               · o'rnatilmagan

  [space] tanlash   [enter] o'rnatish   [a] hammasi/hech biri   [r] yangilash
  [c] credentiallar   [l] til   [q] chiqish
```

**↑/↓** bilan yuring, **space** bilan belgilang, **enter** bosing —
dependencylar avtomatik hal qilinadi (PostgreSQL tanlasangiz, Docker o'zi qo'shiladi).
Interfeys **O'zbekcha** va **English** tillarida.

### Har bir tool uchun versiya tanlash

Node.js, PostgreSQL, Valkey yoki MinIO o'rnatayotganingizda tool **rasmiy
versiyalar ro'yxatini** ko'rsatadi (NodeSource / Docker Hub'dan jonli olinadi,
offline uchun zaxira ro'yxat bilan) va birini tanlash imkonini beradi — yoki
**Boshqa** ni tanlab istalgan versiyani yozasiz:

```
  Versiyani tanlang — PostgreSQL
  rasmiy versiyalar — birini tanlang yoki o'zingiznikini kiriting

  ❯ 18 (hozirgi)
    17
    16
    15
    14
    Boshqa (o'zingiz kiriting)…

  [↑/↓] harakat   [enter] OK
```

Tanlovingiz eslab qolinadi (`/etc/vps-setup/versions`), shuning uchun qayta
o'rnatishda o'sha versiya saqlanadi. Savol-javobsiz xohlaysizmi? Versiyani env
o'zgaruvchisi orqali bering:

```bash
sudo NODE_MAJOR=22 POSTGRES_VERSION=17 VALKEY_VERSION=7.2 vps install all
```

> ⚠️ **Allaqachon o'rnatilgan** bazaning major versiyasini o'zgartirish mavjud
> data volume'ni o'qib bo'lmaydigan qilishi mumkin — avval backup oling
> (`vps info`) yoki yangi volume'dan boshlang. Tool buni qilishdan oldin
> ogohlantiradi.

## Nima o'rnatadi

| Servis | Nima beradi |
|---|---|
| **Tizim va toollar** | `apt` update/upgrade + git, curl, jq, htop, tmux, fail2ban, ufw |
| **Swap (2GB)** | swapfile + `vm.swappiness=10`, fstab orqali doimiy |
| **Node.js** | NodeSource'dan — **versiya tanlanadi** (default 24 LTS) |
| **Docker** | Docker CE + Compose v2 + bitta-node Swarm + log rotation |
| **PostgreSQL** | Docker'da, 5432-port, kichik VPS uchun sozlangan — **versiya tanlanadi** (default 18) |
| **Valkey (Redis)** | 6379-port, AOF, 256MB LRU kesh — **versiya tanlanadi** (default 8) |
| **MinIO** | S3'ga mos fayl xotira, console SSH tunnel orqali, public `uploads` bucket — **versiya tanlanadi** |
| **Kunlik backup** | `pg_dump \| gzip` → `/opt/backups`, 7 kun saqlanadi |
| **Nginx** | reverse proxy :80 → app :3000, `/files/` → MinIO, certbot tayyor |
| **Firewall** | UFW **SSH lockout himoyasi bilan** + fail2ban + avto yangilanishlar |
| **SSH key** | GitHub Actions CI/CD uchun ed25519 deploy key |

Barcha credentiallar (ulanish URL'lari, parollar, CI/CD private key)
**`/root/server-credentials.txt`** faylga tushadi — istalgan payt `sudo vps creds` bilan ko'ring.

### Serveringizni biling — `vps info`

Har bir o'rnatilgan servis uchun `sudo vps info` **nima qayerda turibdi va uni
qanday boshqarish** kerakligini ko'rsatadi — compose fayl, `.env`, Docker
ma'lumot volume'lari, portlar, log buyruqlari, restart buyruqlari,
backup/restore, SSL va boshqalar. Server ustida ishlayotgan developer uchun
tayyor shpargalka:

```
  PostgreSQL 18  ✓ o'rnatilgan
     Compose fayl:  /opt/infra/docker-compose.yml
     Maxfiy (.env): /opt/infra/.env   (chmod 600)
     Ma'lumot (volume): infra_pg_data → /var/lib/docker/volumes/infra_pg_data/_data
     Port:          5432
     Ulanish:       docker exec -it postgres psql -U appuser -d appdb
     Qayta ishga tushirish: cd /opt/infra && docker compose restart postgres
     Loglar:        docker logs -f postgres
     Backuplar:     /opt/backups
```

`sudo vps info <servis>` bitta servisga toraytiradi va u servis hali
o'rnatilmagan bo'lsa ham ishlaydi (fayllar qayerga tushishini oldindan bilish
uchun). Menyuda istalgan servis ustida **`i`** tugmasini bosing.

## Ishlatish

```bash
sudo vps                        # interaktiv menyu (tavsiya etiladi)
sudo vps install all            # butun stack, savol-javobsiz
sudo vps install postgres       # bitta servis (+ dependencylari)
sudo vps install valkey minio   # bir nechtasini birdan
sudo vps status                 # serverda nima o'rnatilgan
sudo vps info                   # fayllar, portlar, boshqaruv buyruqlari (hammasi)
sudo vps info postgres          # bitta servis uchun
sudo vps creds                  # credentiallarni ko'rish
sudo vps logs                   # o'rnatish logining oxiri
sudo vps lang en|uz             # interfeys tili
sudo vps update                 # GitHub'dan o'zini yangilash
vps help                        # qolgan hammasi
```

### O'z parollaringiz bilan

Parollar default avto-generatsiya qilinadi. O'zingiznikini bermoqchi bo'lsangiz:

```bash
sudo POSTGRES_PASSWORD='MeningParolim26' \
     REDIS_PASSWORD='RedisParolim2026' \
     MINIO_ROOT_PASSWORD='MinioParolim26' \
     vps install all
```

Kamida 12 belgi; faqat harflar, raqamlar va `- _ . ! @ # % ^ * + = : ,`
qabul qilinadi (`` ' " $ ` \ `` kabi belgilar va bo'shliq `.env` ni buzadi).
Serverda `.env` allaqachon bo'lsa — **undagi parollar saqlanadi**, tool hech
qachon credentiallarni indamay ustidan yozmaydi.

## Kafolatlar

- **Idempotent** — istalgan serverda, istalgancha marta run qiling. Bajarilgan
  bosqichlar aniqlanadi va o'tkazib yuboriladi; faqat yetishmayotgani qilinadi.
- **Resume-safe** — bosqich yarim yo'lda xato bersa, muammoni hal qilib qayta
  run qiling. To'xtagan joyidan davom etadi.
- **Non-destructive** — mavjud configlar o'zgarishdan oldin `*.bak.<vaqt>` ga
  backup olinadi. Mavjud Docker `daemon.json` ga tegilmaydi — ishlab turgan
  konteynerlar hech qachon restart bo'lmaydi.
- **SSH lockout himoyasi** — firewall haqiqiy SSH portingizni (o'zgartirilgan
  bo'lsa ham) aniqlaydi va o'sha port ochilmaguncha o'zini yoqmaydi.

## Xavfsizlik eslatmalari

- PostgreSQL (5432) va Valkey (6379) tashqi toollar (DBeaver, lokal backend)
  ulanishi uchun ochiq. Statik IP'ingiz bo'lsa, cheklang:
  `sudo ufw delete allow 5432/tcp && sudo ufw allow from SIZNING_IP to any port 5432`
- Firewall 5432/6379 ni faqat o'sha servislar haqiqatda o'rnatilgan bo'lsa ochadi.
- MinIO S3 API va console faqat localhost'ga bog'langan; fayllar nginx orqali
  (`/files/`) tarqatiladi, console'ga SSH tunnel bilan kiriladi:
  `ssh -L 9001:localhost:9001 root@SERVER_IP` keyin `http://localhost:9001`.
- **MinIO console'ni ommaga ochish** (tunnel'siz browserdan kirish) —
  `http://SERVER_IP:9001` va firewall portini ochadi:
  ```bash
  sudo MINIO_CONSOLE_PUBLIC=1 vps install minio
  # localhost'ga qaytarish:
  sudo MINIO_CONSOLE_PUBLIC=0 vps install minio && sudo ufw delete allow 9001/tcp
  ```
  ⚠️ Bu console'ni shifrsiz HTTP orqali beradi — login paroli shifrlanmagan
  holda ketadi. Kuchli `MINIO_ROOT_PASSWORD` ishlating; jiddiy narsa uchun
  domen + TLS (`certbot`) afzal. S3 API (9000) baribir localhost'da qoladi.
- `/root/server-credentials.txt` ni xavfsiz joyga ko'chirib olgach, o'chiring:
  `sudo rm /root/server-credentials.txt` (qayta o'rnatishda yana yaratiladi).

## Maintainerlar / fork qiluvchilar uchun

O'z nusxangizni chiqarish:

1. Repo'ni GitHub'ga push qiling (yoki fork qiling).
2. `rustamdostondev` ni **to'rt faylda** almashtiring: `vps`
   (`REPO_SLUG` o'zgaruvchisi), `install.sh` (`REPO` o'zgaruvchisi va header
   kommentidagi bir qatorli buyruq), `README.md` va `README.uz.md`
   (o'rnatish buyruqlari). Repo ildizidan bitta buyruq:
   ```bash
   sed -i '' 's/rustamdostondev/sizning-username/g' vps install.sh README.md README.uz.md   # macOS
   sed -i 's/rustamdostondev/sizning-username/g' vps install.sh README.md README.uz.md      # Linux
   ```
3. Tayyor — bir qatorli installer va `vps update` endi sizning repo'ingizga qaraydi.

Serversiz lokal ishlab chiqish:

```bash
VPS_DEMO=1 ./vps            # to'liq TUI, mock statuslar va soxta installlar bilan
VPS_DEMO=1 ./vps install all
shellcheck vps install.sh   # lint
```

## Litsenziya

[MIT](LICENSE)
