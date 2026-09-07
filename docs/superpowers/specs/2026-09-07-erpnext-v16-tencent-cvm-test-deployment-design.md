# ERPNext v16 腾讯云 CVM 测试部署设计

## 1. 目标与固定来源

在 CVM `ins-o105zyb2`（私网 `172.19.1.4`）建立可复现的 ERPNext v16 测试站点 `erptest.jxmhfc.com`。ERPNext 必须来自用户指定仓库 `git@github.com:pk604437000/erpnext.git` 的 `version-16` 分支；部署时固定为 2026-09-07 解析的提交 `0b50853985312bc64977f9324c55b5d8c1ab2e59`，该提交同时标记为 `v16.34.1`。不在 CVM 上跟随移动分支。

Frappe 使用 `https://github.com/frappe/frappe.git` 的 `version-16-hotfix` 提交 `5e44af21ee3d3d9ac9392b7a5f7cc1f92fd04dbe`。该选择满足 ERPNext 元数据的 `frappe >=16.21.0,<17.0.0`。`frappe_docker` 固定为 `380b9d069ab949754fe78331af647b673984dc04`；自定义镜像标签为 `erpnext-v16-test:v16.34.1-0b508539`，实际运行版本以记录的镜像摘要为准。

## 2. 隔离与网络边界

部署根目录为 `/opt/erpnext-v16-test`，Compose 项目名为 `erpnext-v16-test`。不得复用、删除或覆盖此前 v17 尝试在 `/opt/erpnext-test` 留下的工件。容器的 `frontend` 仅映射 `127.0.0.1:8080:8080`；`backend`、`websocket`、MariaDB、Redis、worker 和 scheduler 不映射宿主机端口。

宿主机既有 Nginx 是唯一的公共入口。仅添加 `erptest.jxmhfc.com` 的 HTTPS 443 虚拟主机，代理到 `127.0.0.1:8080`。不新增站点 HTTP 80 虚拟主机，也不开放公网 80、8080、22、3306、6379 或其他应用端口。

DNS A 记录和安全组公网 TCP 443 是独立人工门禁：完成回环 HTTPS、持久化、备份恢复和只读外部状态验证后必须暂停。未经用户届时再次明确确认，绝不调用 DNS 或安全组写 API。

## 3. 资源准备与秘密

本机为 arm64，CVM 为 amd64。所有镜像归档必须使用 `linux/amd64` 拉取，且在本机和 CVM 使用 SHA-256 清单验证。固定源码、NVM、wkhtmltopdf、镜像归档和用户证书 ZIP 经私网 SSH/rsync 传输。CVM 的 Compose 设为 `pull_policy: never`，避免未验证拉取。

证书 ZIP 仅用于安全导入 `jxmhfc.com_bundle.crt` 与 `jxmhfc.com.key`。导入前验证域名、有效期、序列号、证书 SHA-256 指纹 `B0:22:27:35:9F:B8:4B:E1:F2:E8:FA:51:4A:82:E0:56:BF:91:D5:59:4F:F4:7D:DA:07:D6:CB:F3:D4:50:72:FC` 和公私钥匹配；私钥不进入 Git、镜像、日志或普通命令输出。证书目录为 root:root `0700`，私钥为 `0600`。

数据库和 Administrator 密码仅写入 `/opt/erpnext-v16-test/.env` 与 `.credentials`，模式 `0600`，并禁止出现在输出、Git 和镜像历史。

## 4. 运行时与验收

Docker Engine、Compose v2 和 Buildx 先在 CVM 上经只读前置检查确认容量、内存、443 空闲、Nginx 配置和既有 MariaDB、Redis、Java 服务状态。安装或变更不得停止、覆盖、复用这些既有服务。

每日 02:30 运行站点备份；保留七天。部署必须进行一次临时站点 `erptest-v16-restore.local` 的数据库、公共文件和私有文件恢复验证，且只允许删除该精确临时站点。

公网变更前验收包括：全部长期服务运行；`configurator` 成功退出；Docker 日志轮转生效；根文件系统低于 80% 使用率；HTTP 回环 frontend 正常；使用 `--resolve` 的回环 HTTPS 登录页正常；证书指纹匹配；bench doctor、Redis、队列、scheduler 和 websocket 正常；重启 Compose 后数据保留；备份恢复通过；manifest 中的源码、工件哈希、镜像架构/摘要与实际一致。之后仅报告拟创建的 DNS A `erptest -> 111.230.98.71`（TTL 600）及安全组 `sg-olwsx1d7` 的 TCP 443 `0.0.0.0/0` 规则并暂停。
