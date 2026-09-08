# ERPNext v16 测试站点发布记录（2026-09-07）

## 1. 发布范围

- 站点：`https://erptest.jxmhfc.com/login`
- CVM：`ins-o105zyb2`（广州七区，Ubuntu 24.04 LTS，4 vCPU / 16 GiB）
- 部署目录：`/opt/erpnext-v16-test`
- Compose 项目：`erpnext-v16-test`
- 发布状态：已部署并完成本机验收、备份恢复验证、DNS 记录与 HTTPS 可用性验证。

本记录不包含管理员密码、数据库密码、私钥、令牌或证书私钥内容。

## 2. 固定版本与可复现性

| 项目 | 固定值 |
| --- | --- |
| ERPNext 源码 | `git@github.com:pk604437000/erpnext.git`，`version-16` |
| ERPNext 发布提交 | `0b50853985312bc64977f9324c55b5d8c1ab2e59`（`v16.34.1`） |
| Frappe 提交 | `5e44af21ee3d3d9ac9392b7a5f7cc1f92fd04dbe` |
| frappe_docker 提交 | `380b9d069ab949754fe78331af647b673984dc04` |
| 自定义镜像 | `erpnext-v16-test:v16.34.1-0b508539` |
| 镜像 ID / 索引摘要 | `sha256:019afb3f8d60f0fd10a47267650929e459a7494732e7b959acc7b86f92be017b` |
| 镜像清单摘要 | `sha256:3b3d22bc0f1df0c1941b5fdfeb1887c41b238f6b58aff133873ba53e2ed38d9e` |
| 镜像架构 | `linux/amd64` |
| Python / Node.js | `3.14` / `24` |
| Docker / Compose / Buildx | `29.1.3` / `2.40.3+ds1-0ubuntu1~24.04.1` / `0.30.1` |
| Nginx | `1.24.0 (Ubuntu)` |
| 部署时间（UTC） | `2026-09-07T09:31:54.137594+00:00` |

运行时清单总哈希为
`5d3d854cd4c9541efe16d920f25fc44a864fe86acc1371fe091b973e4a8ebdf4`。
其对应的文件为 `/opt/erpnext-v16-test/inventory/SHA256SUMS`；该清单覆盖
`bench version`、依赖锁文件、镜像、运行时、服务和源码补丁等库存文件。

## 3. 网络、TLS 与访问边界

- DNSPod 已存在且启用记录：`erptest.jxmhfc.com A → 111.230.98.71`，TTL `600`（记录 ID `2397728063`）。
- Nginx 是 ERPNext 唯一入口：IPv4/IPv6 `443` 反向代理至 `127.0.0.1:8080`。
- Compose 仅发布 `127.0.0.1:8080:8080`；数据库、Redis、backend、worker、scheduler 和 websocket 均未映射宿主机端口。
- 证书 SHA-256 指纹：`B0:22:27:35:9F:B8:4B:E1:F2:E8:FA:51:4A:82:E0:56:BF:91:D5:59:4F:F4:7D:DA:07:D6:CB:F3:D4:50:72:FC`。
- 证书 SAN：`*.jxmhfc.com`、`jxmhfc.com`；到期时间：`2027-01-17 15:59:59 UTC`。
- 主机没有 TCP 80 监听；在主机回环访问 `127.0.0.1:80` 得到连接失败。TCP 443 仅由 Nginx 监听，TCP 8080 仅绑定回环地址。

### 安全组的已授权偏差

该实例关联 `sg-ldqxap8r`（`徐福记-公网web服务`）及既有的
`sg-olwsx1d7`。按用户在发布期间的明确授权，前者当前对 IPv4/IPv6
开放 TCP `80` 与 `443`。这与早期计划中“安全组不开放 80”的约束不同；
本记录如实保留该偏差。

安全组开放 TCP 80 不会使本主机自动提供 HTTP 服务，因为主机未监听 80。
后续若要收紧攻击面，应在不影响其他同组业务的前提下，为本实例使用仅含
TCP 443 的专用安全组；这属于云端变更，需单独确认后执行。

## 4. 数据持久化、备份与凭据边界

| 内容 | 位置 / 策略 |
| --- | --- |
| MariaDB 数据 | Docker 卷 `erpnext-v16-test_db-data` |
| 站点与文件 | Docker 卷 `erpnext-v16-test_sites` |
| Redis 队列数据 | Docker 卷 `erpnext-v16-test_redis-queue-data` |
| 自动备份 | 每日 `02:30`，由 `/etc/cron.d/erpnext-v16-test-backup` 调用 `/opt/erpnext-v16-test/bin/backup.sh` |
| 备份执行上下文 | cron 的 `PATH` 显式包含 `/opt/erpnext-v16-test/bin`；该目录中的 `bench` 是 root:root、`0750` 的 Compose 包装器，固定在 backend 容器执行 `bench` |
| 备份源路径 | `/opt/erpnext-v16-test/sites` 是指向 `erpnext-v16-test_sites` 命名卷数据目录的符号链接，故备份脚本读取的是运行中站点数据 |
| 保留策略 | 仅清理 `/opt/erpnext-v16-test/backups` 下超过 7 天的备份 |
| 恢复演练 | 数据库、public files、private files 已恢复至临时站点 `erptest-v16-restore.local`，验证后已删除该临时站点 |
| 密码文件 | `/opt/erpnext-v16-test/.env` 与 `.credentials`，均为部署账户所有且权限 `0600`；不纳入 Git、镜像或本文档 |

## 5. 发布验收证据

| 检查 | 结果 |
| --- | --- |
| 九个长期运行服务与 scheduler/worker 健康检查 | 通过；`verify-local.sh` 返回 `0`，当时显示 2 个 worker online |
| 本机前端、TLS 指纹、`bench doctor`、日志轮转与磁盘阈值 | 通过 `verify-local.sh` 验证 |
| Compose 重启后的持久化 | 已验证通过 |
| 备份及临时恢复 | 已验证通过 |
| 直连发布 IP 的 HTTPS 登录页 | `https_status=200`、`tls_verify=0` |
| DNSPod A 记录 | 已查询确认，值为 `111.230.98.71`、状态 `ENABLE` |
| HTTP 80 主机监听 | 未监听；回环 HTTP 连接失败 |

“直连发布 IP”的 HTTPS 检查由该 CVM 发起，能够验证目标地址、证书与应用响应，
但不构成来自独立互联网出口的端口扫描。由于当前 Web 安全组有 TCP 80/443
公网放通，本文档不将“80 对互联网不可达”作为已验证结论。

## 6. 日常运维

以下命令均在 CVM 上执行；先确认当前目录和项目名，避免误操作其他 Compose 项目。

```bash
cd /opt/erpnext-v16-test
docker compose --project-name erpnext-v16-test --env-file .env -f compose.yaml ps
sudo /opt/erpnext-v16-test/bin/verify-local.sh
sudo env PATH=/opt/erpnext-v16-test/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  /opt/erpnext-v16-test/bin/backup.sh
```

查看或重启本项目时，不要使用会影响全局 Docker 资源的清理命令，也不要修改
`/opt/erpnext-test` 中的旧工件。需要修改 DNS、安全组、证书或管理员密码时，
应单独完成变更评审、备份和验证。
