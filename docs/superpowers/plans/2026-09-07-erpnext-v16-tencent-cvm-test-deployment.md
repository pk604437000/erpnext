# ERPNext v16 腾讯云 CVM 测试部署实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 CVM `ins-o105zyb2` 部署用户仓库 `git@github.com:pk604437000/erpnext.git` 的固定 ERPNext v16.34.1 测试站点，并在 DNS/安全组变更前完成私网验收。

**Architecture:** 以独立 Compose 项目 `erpnext-v16-test` 运行 ERPNext/Frappe v16、MariaDB 和 Redis；宿主机 Nginx 在 443 终止 TLS 并仅代理到 `127.0.0.1:8080`。所有境外依赖先在本机固定、校验并经私网传输。

**Tech Stack:** Ubuntu 24.04、Docker Engine 29.1.3、Docker Compose 2.40.3、Buildx 0.30.1、Nginx 1.24.0、Python 3.14、Node.js 24、MariaDB 11.8、Redis 8.6 Alpine。

**Spec:** `docs/superpowers/specs/2026-09-07-erpnext-v16-tencent-cvm-test-deployment-design.md`

## Global Constraints

- ERPNext source is `git@github.com:pk604437000/erpnext.git`, branch `version-16`, frozen commit `0b50853985312bc64977f9324c55b5d8c1ab2e59` (`v16.34.1`).
- Frappe is frozen at `5e44af21ee3d3d9ac9392b7a5f7cc1f92fd04dbe`; frappe_docker is frozen at `380b9d069ab949754fe78331af647b673984dc04`.
- Use `/opt/erpnext-v16-test` and Compose project `erpnext-v16-test`; never reuse or delete `/opt/erpnext-test`.
- frontend may expose only `127.0.0.1:8080`; no other container host port mappings.
- Keep the host's existing Nginx, MariaDB, Redis and Java services running and isolated.
- DNS A records and security-group rules are Task 8-only manual writes; public HTTP/80 is prohibited.
- Private keys, passwords and tokens must never enter Git, image layers or ordinary logs.

---

### Task 1: 创建 v16 可审阅部署配置

**Files:** Create `deploy/erpnext-v16-test/versions.env`, `.gitignore`, `apps.json`, `compose.override.yaml`, `nginx-erptest.conf`.

**Interfaces:** Produces the only version/configuration input for offline preparation and CVM installation.

- [ ] Write `versions.env` with `SITE_NAME=erptest.jxmhfc.com`, `COMPOSE_PROJECT_NAME=erpnext-v16-test`, `ERPNEXT_REPOSITORY=git@github.com:pk604437000/erpnext.git`, `ERPNEXT_BRANCH=version-16`, `ERPNEXT_COMMIT=0b50853985312bc64977f9324c55b5d8c1ab2e59`, `FRAPPE_COMMIT=5e44af21ee3d3d9ac9392b7a5f7cc1f92fd04dbe`, `FRAPPE_DOCKER_COMMIT=380b9d069ab949754fe78331af647b673984dc04`, `PYTHON_VERSION=3.14`, `NODE_VERSION=24`, `CUSTOM_IMAGE=erpnext-v16-test`, `CUSTOM_TAG=v16.34.1-0b508539`, `MARIADB_IMAGE=mariadb:11.8`, and `REDIS_IMAGE=redis:8.6-alpine`.
- [ ] Write `.gitignore` excluding `.env`, `.credentials`, `manifest.env`, `artifacts/`, `build-context/`, `certs/`, `*.key`, `*.zip`, `*.tar*`, and `*.sha256`.
- [ ] Write `apps.json` as `[ { "url": "/opt/frappe/sources/erpnext", "branch": "deploy-pin" } ]`.
- [ ] Write the Compose override with json-file logging (`max-size: 10m`, `max-file: "3"`) on frontend, backend, websocket, queue-short, queue-long, scheduler, db, redis-cache and redis-queue; only frontend has `127.0.0.1:8080:8080`; db/Redis image values use `mariadb:11.8` and `redis:8.6-alpine`.
- [ ] Write the Nginx HTTPS server for `erptest.jxmhfc.com`: 443 IPv4/IPv6 only, `jxmhfc.com_bundle.crt`/`.key` from `/etc/nginx/ssl/erptest.jxmhfc.com`, TLS 1.2/1.3, 50m client limit, WebSocket map, and proxy headers to `http://127.0.0.1:8080`.
- [ ] Verify with `python3 -m json.tool deploy/erpnext-v16-test/apps.json >/dev/null`, `git diff --check`, and `! rg -n '0\.0\.0\.0:|:80:|:443:' deploy/erpnext-v16-test/compose.override.yaml`; commit `chore: 添加 ERPNext v16 部署配置`.

### Task 2: 添加前置、备份与验收脚本

**Files:** Create `deploy/erpnext-v16-test/bin/preflight.sh`, `backup.sh`, `verify-local.sh`.

**Interfaces:** The scripts consume `/opt/erpnext-v16-test/.env` and generated Compose, and are invoked by Tasks 4 and 7.

- [ ] `preflight.sh` must use `set -euo pipefail`, require x86_64, 100 GiB free root disk and 6 GiB MemAvailable, fail if 443 is occupied, run `sudo nginx -t`, list listening ports and report existing nginx/mariadb/redis/java/Docker state without stopping services.
- [ ] `backup.sh` must use `set -euo pipefail`, `umask 077`, `cd /opt/erpnext-v16-test`, run `bench --site erptest.jxmhfc.com backup --with-files --compress`, copy backend backups to `backups/`, delete only files older than 7 days under `/opt/erpnext-v16-test/backups`, and require a nonempty file newer than one day.
- [ ] `verify-local.sh` must require all eight long-running services, verify each uses json-file log options 10m/3, require root filesystem usage `<80`, test frontend with Host header on 127.0.0.1:8080, verify the exact TLS fingerprint on 127.0.0.1:443, call HTTPS with `--resolve`, and run `bench --site erptest.jxmhfc.com doctor`.
- [ ] Run `bash -n deploy/erpnext-v16-test/bin/*.sh` and `! rg -n 'rm -rf|docker system prune|0\.0\.0\.0' deploy/erpnext-v16-test/bin`; commit `chore: 添加 ERPNext v16 运维脚本`.

### Task 3: 准备并校验 v16 离线工件

**Files:** Create ignored `deploy/erpnext-v16-test/artifacts/`; create remote `/opt/erpnext-v16-test/incoming/` mode 0750.

**Interfaces:** Provides verified source archives, cert ZIP and amd64 image archives to Task 4.

- [ ] Use `git archive` on `0b50853985312bc64977f9324c55b5d8c1ab2e59` for `erpnext.tar.gz`; download Frappe `5e44af21ee3d3d9ac9392b7a5f7cc1f92fd04dbe`, frappe_docker `380b9d069ab949754fe78331af647b673984dc04`, NVM 0.40.6 and wkhtmltox 0.12.6.1-3 archives to artifacts; copy the supplied certificate ZIP without opening it.
- [ ] Use temporary `crane v0.21.7` with `--platform linux/amd64` to pull Python 3.14 slim-bookworm, MariaDB 11.8 and Redis 8.6 Alpine tar archives. If crane is absent, stop and obtain explicit installation authorization; do not install Docker Desktop.
- [ ] Generate `SHA256SUMS` over every source/package/certificate ZIP/image tar; record source, target architecture, byte size and hash in a nonsecret task report.
- [ ] Create remote incoming as `ubuntu:ubuntu` 0750; rsync artifacts and Task 1–2 files over private SSH; set the remote certificate ZIP to 0600 and run remote `sha256sum -c SHA256SUMS`. Do not unpack or print private-key material.

### Task 4: CVM 前置检查、Docker 与构建上下文

**Files:** Create remote `/opt/erpnext-v16-test/build-context/`, `compose.base.yaml`, `compose.mariadb.yaml`, `compose.redis.yaml`, `apps.json`, and `compose.override.yaml`.

**Interfaces:** Consumes verified Task 3 inputs; produces an isolated Docker build context without a public port mapping.

- [ ] Execute the transferred preflight script. Stop on any failed architecture, capacity, memory, 443 or Nginx check.
- [ ] Install exact Docker packages `docker.io=29.1.3-0ubuntu3~24.04.2`, `docker-compose-v2=2.40.3+ds1-0ubuntu1~24.04.1`, and `docker-buildx=0.30.1-0ubuntu1~24.04.1`; enable Docker, add only `ubuntu` to its group, reconnect, and verify versions plus existing host service state.
- [ ] Load each image archive and require image architecture `amd64`.
- [ ] Extract pinned frappe_docker/Frappe/ERPNext archives under build-context; initialize each source directory on local branch `deploy-pin` with a local snapshot commit. Copy NVM and wkhtmltox into offline resources.
- [ ] Copy the pinned custom Containerfile and change it to use the Tencent Debian/PyPI/npm mirrors, offline NVM/wkhtmltox resources, and local Frappe/ERPNext source paths. Search for forbidden external build downloads and stop if build output reaches a foreign dependency source.
- [ ] Install only compose base/overrides and Task 1 inputs. Do not copy or use `compose.noproxy.yaml`.

### Task 5: 构建、冻结并启动 v16 站点

**Files:** Create remote `.env`, `.credentials`, `compose.yaml`, `inventory/`, `manifest.env` under `/opt/erpnext-v16-test`.

**Interfaces:** Produces the running site and immutable version inventory required by TLS and recovery tasks.

- [ ] Generate non-echoed 48-hex database and Administrator passwords into mode-0600 files. Set `COMPOSE_PROJECT_NAME=erpnext-v16-test`, `CUSTOM_IMAGE=erpnext-v16-test`, `CUSTOM_TAG=v16.34.1-0b508539`, and `PULL_POLICY=never`.
- [ ] Build `erpnext-v16-test:v16.34.1-0b508539` using `linux/amd64`, local Frappe source, BuildKit `apps_json` secret and the frozen ERPNext commit. Verify architecture, Python 3.14, Node 24 and `bench version` lists Frappe/ERPNext.
- [ ] Render Compose from the three pinned base/override inputs plus local override; validate it, require only loopback 8080 mapping, then start it. Confirm configurator exits successfully and the eight long-running services remain running.
- [ ] Create `erptest.jxmhfc.com` with the isolated database password and install ERPNext. Generate runtime, pip-freeze and bench-version inventory hashes.
- [ ] Write mode-0600 `manifest.env` with every source/artifact hash, image ID/digest/architecture, Docker/Compose/Buildx/Nginx versions, inventory hash and deployment time; never write secrets.

### Task 6: 安全导入证书并启用回环 HTTPS

**Files:** Create remote certificate directory/files and `/etc/nginx/sites-available/erptest.jxmhfc.com.conf`.

**Interfaces:** Consumes Task 3 certificate ZIP and Task 5 frontend; produces local-only HTTPS validation capability.

- [ ] Extract the certificate ZIP in a 0700 temporary directory; verify certificate subject/SAN/dates/serial, the exact fingerprint, and matching certificate/key public-key digests without emitting key contents.
- [ ] Install only `jxmhfc.com_bundle.crt` and `jxmhfc.com.key` to root:root `/etc/nginx/ssl/erptest.jxmhfc.com` mode 0700; use modes 0644 and 0600 respectively. Install and enable Task 1's 443-only Nginx config.
- [ ] Run `sudo nginx -t && sudo systemctl reload nginx`; verify 443 is listening, frontend remains loopback-only and existing 80 behavior is unchanged.

### Task 7: 备份、恢复与公网变更前验收

**Files:** Create remote `/etc/cron.d/erpnext-v16-test-backup`.

**Interfaces:** Produces all evidence required by the Task 8 manual gate.

- [ ] Install root cron entry `30 2 * * * root /opt/erpnext-v16-test/bin/backup.sh >>/var/log/erpnext-v16-test-backup.log 2>&1`; script ownership is root:root mode 0750.
- [ ] Run backup and require nonempty database, public-file and private-file archives. Restore them only into exact temporary site `erptest-v16-restore.local`; validate the variable before new-site, restore, migrate, doctor and drop-site. Delete only that exact temporary site after success.
- [ ] Run `verify-local.sh`; record PASS/FAIL for services, loopback HTTP/HTTPS, fingerprint, login page, doctor, log rotation and disk threshold. Restart the Compose project once and verify data and loopback frontend persist.
- [ ] Perform read-only DNSPod and security-group queries. Require no `erptest` A record and no public ingress exception before Task 8.

### Task 8: 强制人工门禁

**Files:** No writes without a new explicit user confirmation.

**Interfaces:** Consumes all Task 7 evidence; may produce public HTTPS only after confirmation.

- [ ] Stop and report the complete local evidence, port state, DNS state and security-group state. State the only proposed changes: DNS A `erptest.jxmhfc.com -> 111.230.98.71`, TTL 600; inbound TCP 443 from `0.0.0.0/0` on `sg-olwsx1d7`.
- [ ] End the execution turn without calling DNS/security-group Create/Modify APIs until the user explicitly confirms again.

### Task 9: 受确认后才执行的公网发布与记录

**Files:** After approval only, modify DNSPod/security group and create `docs/deployment/erpnext-v16-test-2026-09-07.md`.

**Interfaces:** Consumes Task 8 approval; produces public HTTPS evidence and a sanitized deployment record.

- [ ] Re-read DNS/security-group state and API help, then add only the approved A record and TCP 443 rule. If a same-name record exists, stop without overwriting it.
- [ ] Validate public DNS, HTTPS fingerprint/login and that 80, 8080, 22, 3306 and 6379 are not publicly reachable.
- [ ] Write the sanitized record with source commits, image digest, inventory hashes, certificate fingerprint/expiry, volumes, backup schedule and all validation results. Scan it and `deploy/erpnext-v16-test` for key/password markers, run `git diff --check`, then commit `docs: 记录 ERPNext v16 测试部署结果`.
