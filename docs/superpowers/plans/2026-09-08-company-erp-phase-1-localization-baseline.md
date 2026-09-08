# Company ERP 中国大陆本地化基线实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 创建独立的 `company_erp` App，在 ERPNext V16 测试站点可重复地配置中国大陆默认值，并验证 `erpnext_china` 的财务本地化基线。

**Architecture:** `company_erp` 是 ERPNext 仓库之外的独立 App 仓库，只以公开 Frappe API 读取和写入单例设置、Global Defaults 与 Currency。测试站点由 Docker Compose 运行，所有 Bench 操作通过 `docker compose exec -T backend bench` 执行；部署仓库只记录固定版本和本地 Build Context 的三个 App 源码，站点先安装 `erpnext_china`，再执行 `company_erp` 的显式、幂等配置命令。

**Tech Stack:** Python 3.14、Frappe V16、ERPNext V16、FrappeTestCase、Bench、Docker Compose、MariaDB。

**Spec:** `docs/superpowers/specs/2026-09-08-erpnext-v16-mainland-china-localization-design.md`

## Global Constraints

- 不修改 `erpnext/` 或 Frappe 官方源码；不使用 monkey patch 或 `override_doctype_class`。
- `company_erp` 在 `/Users/yzf/Project/personal/源代码/company_erp` 独立管理，并固定到明确 Git commit。
- 目标依赖是 Frappe/ERPNext `>=16.21.0,<17.0.0`；`erpnext_china` 必须已安装后才允许配置。
- 测试站点为 `erptest.jxmhfc.com`；所有运行态检查、安装和配置命令都必须在 `/opt/erpnext-v16-test` 通过 `docker compose exec -T backend bench --site erptest.jxmhfc.com` 执行。
- 最终值必须是 China、`zh`、Asia/Shanghai、`yyyy-mm-dd`、`HH:mm:ss`、`#,###.##`、Monday、CNY、Currency Precision 2、Float Precision 4，以及 CNY 的 `#,###.##`。
- 配置命令必须支持 `dry_run=True`，只报告差异；正常执行必须只更新差异字段，并让异常中断事务。
- 所有新行为先写失败测试，再写最小实现；每个任务使用中文 Conventional Commit 独立提交。

---

## 文件结构

| 文件 | 职责 |
| --- | --- |
| `company_erp/pyproject.toml` | App 元数据与 Frappe/ERPNext V16 依赖范围 |
| `company_erp/company_erp/hooks.py` | App 只声明 fixtures；不声明核心类/方法覆盖 |
| `company_erp/company_erp/setup.py` | 依赖检查、差异读取、干跑报告和配置写入 |
| `company_erp/company_erp/tests/test_setup.py` | 真实站点单例配置的集成测试 |
| `company_erp/README.md` | 安装、固定版本和配置命令说明 |
| `erpnext/deploy/erpnext-v16-test/apps.json` | 离线构建时三个 App 的本地源码输入 |
| `erpnext/deploy/erpnext-v16-test/versions.env` | 三个 App 的固定 commit 与镜像版本 |
| `erpnext/deploy/erpnext-v16-test/bin/verify-china-baseline.sh` | 站点 App 顺序、设置、CNY 与财务本地化的只读验收 |

### Task 1: 建立独立 App 与 V16 基础测试

**Files:**
- Create: `/Users/yzf/Project/personal/源代码/company_erp/pyproject.toml`
- Create: `/Users/yzf/Project/personal/源代码/company_erp/company_erp/__init__.py`
- Create: `/Users/yzf/Project/personal/源代码/company_erp/company_erp/hooks.py`
- Create: `/Users/yzf/Project/personal/源代码/company_erp/company_erp/tests/__init__.py`
- Create: `/Users/yzf/Project/personal/源代码/company_erp/company_erp/tests/test_app_metadata.py`
- Create: `/Users/yzf/Project/personal/源代码/company_erp/README.md`

**Interfaces:**
- Consumes: Bench 的 `bench new-app` 生成的标准 App 目录。
- Produces: Python 包 `company_erp`，其版本由 `company_erp.__version__` 提供，后续任务可通过 `frappe.get_installed_apps()` 识别。

- [ ] **Step 1: 在目标 Bench 创建框架生成的 App 骨架**

```bash
cd /opt/erpnext-v16-test/bench
bench new-app company_erp --no-git
```

框架骨架属于生成代码；不得把它直接复制到 ERPNext 源仓库。将生成目录同步到 `/Users/yzf/Project/personal/源代码/company_erp`，在该目录执行 `git init`，并只在该目录创建 `codex/company-erp-china-baseline` 分支。

- [ ] **Step 2: 写入失败的 App 元数据测试**

```python
from frappe.tests.utils import FrappeTestCase


class TestAppMetadata(FrappeTestCase):
    def test_company_erp_is_installed_after_erpnext_china(self):
        apps = frappe.get_installed_apps()
        self.assertIn("erpnext", apps)
        self.assertIn("erpnext_china", apps)
        self.assertIn("company_erp", apps)
        self.assertLess(apps.index("erpnext_china"), apps.index("company_erp"))
```

- [ ] **Step 3: 运行测试并确认因未安装或顺序不符而失败**

```bash
cd /opt/erpnext-v16-test
docker compose exec -T backend bench --site erptest.jxmhfc.com run-tests --app company_erp --module company_erp.tests.test_app_metadata
```

预期：测试失败并明确指出 `company_erp` 尚未安装，或 `erpnext_china` 尚未安装。

- [ ] **Step 4: 写入最小 App 元数据和 hooks**

`pyproject.toml` 必须包含：

```toml
[project]
name = "company_erp"
requires-python = ">=3.10"
dependencies = []

[tool.bench.frappe-dependencies]
frappe = ">=16.21.0,<17.0.0"
erpnext = ">=16.21.0,<17.0.0"
```

`hooks.py` 初始内容仅保留 App 元数据和 `fixtures = []`；不得添加 `override_doctype_class`、`override_whitelisted_methods` 或核心源码补丁。

- [ ] **Step 5: 安装 App 并验证测试通过**

```bash
cd /opt/erpnext-v16-test
docker compose exec -T backend bench --site erptest.jxmhfc.com install-app company_erp
docker compose exec -T backend bench --site erptest.jxmhfc.com run-tests --app company_erp --module company_erp.tests.test_app_metadata
```

预期：`test_company_erp_is_installed_after_erpnext_china` 通过；若 `erpnext_china` 尚未安装，停止并先安装它，不得绕过依赖检查。

- [ ] **Step 6: 提交 App 骨架**

```bash
cd /Users/yzf/Project/personal/源代码/company_erp
git add pyproject.toml company_erp README.md
git commit -m "feat: 创建公司中国化扩展应用"
```

### Task 2: 以测试驱动实现中国默认设置差异与干跑

**Files:**
- Create: `/Users/yzf/Project/personal/源代码/company_erp/company_erp/setup.py`
- Create: `/Users/yzf/Project/personal/源代码/company_erp/company_erp/tests/test_setup.py`
- Modify: `/Users/yzf/Project/personal/源代码/company_erp/company_erp/hooks.py`

**Interfaces:**
- Consumes: `frappe.get_installed_apps()`、System Settings、Global Defaults 和 Currency `CNY`。
- Produces: `get_china_defaults_diff() -> list[dict[str, object]]`、`configure_china_defaults(dry_run: bool = False) -> list[dict[str, object]]` 与 `assert_china_localization_dependencies() -> None`。

- [ ] **Step 1: 写入依赖和干跑的失败测试**

```python
from unittest.mock import patch

import frappe
from frappe.tests.utils import FrappeTestCase

from company_erp.setup import (
    assert_china_localization_dependencies,
    configure_china_defaults,
    get_china_defaults_diff,
)


class TestChinaDefaults(FrappeTestCase):
    tracked_documents = {
        "System Settings": (
            "country", "language", "time_zone", "date_format", "time_format", "number_format",
            "first_day_of_the_week", "currency", "currency_precision", "float_precision",
        ),
        "Global Defaults": ("country", "default_currency"),
        "Currency": ("number_format",),
    }

    def setUp(self):
        super().setUp()
        self.original_values = {
            (doctype, name, field): frappe.db.get_value(doctype, name, field)
            for doctype, fields in self.tracked_documents.items()
            for name in ([doctype] if doctype != "Currency" else ["CNY"])
            for field in fields
        }

    def tearDown(self):
        for (doctype, name, field), value in self.original_values.items():
            frappe.db.set_value(doctype, name, field, value)
        frappe.db.commit()
        super().tearDown()

    def test_dependency_check_requires_erpnext_china(self):
        with patch("company_erp.setup.frappe.get_installed_apps", return_value=["frappe", "erpnext"]):
            self.assertRaises(frappe.ValidationError, assert_china_localization_dependencies)

    def test_dry_run_reports_but_does_not_write_target_values(self):
        settings = frappe.get_doc("System Settings")
        original_timezone = settings.time_zone
        settings.time_zone = "Asia/Chongqing"
        settings.save(ignore_permissions=True)

        changes = configure_china_defaults(dry_run=True)

        self.assertIn(
            {
                "doctype": "System Settings",
                "name": "System Settings",
                "field": "time_zone",
                "current": "Asia/Chongqing",
                "target": "Asia/Shanghai",
            },
            changes,
        )
        self.assertEqual(frappe.db.get_single_value("System Settings", "time_zone"), "Asia/Chongqing")

    def test_diff_is_empty_after_apply(self):
        configure_china_defaults()
        self.assertEqual(get_china_defaults_diff(), [])
```

- [ ] **Step 2: 运行测试并确认失败原因是模块尚不存在**

```bash
cd /opt/erpnext-v16-test
docker compose exec -T backend bench --site erptest.jxmhfc.com run-tests --app company_erp --module company_erp.tests.test_setup
```

预期：导入 `company_erp.setup` 失败，而不是测试环境错误。

- [ ] **Step 3: 实现目标常量、依赖检查和只读差异函数**

```python
SYSTEM_SETTINGS_TARGETS = {
    "country": "China",
    "language": "zh",
    "time_zone": "Asia/Shanghai",
    "date_format": "yyyy-mm-dd",
    "time_format": "HH:mm:ss",
    "number_format": "#,###.##",
    "first_day_of_the_week": "Monday",
    "currency": "CNY",
    "currency_precision": 2,
    "float_precision": 4,
}
GLOBAL_DEFAULTS_TARGETS = {"country": "China", "default_currency": "CNY"}
CNY_NUMBER_FORMAT = "#,###.##"


def assert_china_localization_dependencies() -> None:
    if "erpnext_china" not in frappe.get_installed_apps():
        frappe.throw("company_erp requires erpnext_china to be installed first")


def _append_changes(
    changes: list[dict[str, object]], doctype: str, name: str, document, targets: dict[str, object]
) -> None:
    for field, target in targets.items():
        current = document.get(field)
        if current != target:
            changes.append(
                {"doctype": doctype, "name": name, "field": field, "current": current, "target": target}
            )


def get_china_defaults_diff() -> list[dict[str, object]]:
    if not frappe.db.exists("Currency", "CNY"):
        raise frappe.DoesNotExistError("Currency CNY does not exist")

    changes: list[dict[str, object]] = []
    _append_changes(
        changes,
        "System Settings",
        "System Settings",
        frappe.get_doc("System Settings"),
        SYSTEM_SETTINGS_TARGETS,
    )
    _append_changes(
        changes,
        "Global Defaults",
        "Global Defaults",
        frappe.get_doc("Global Defaults"),
        GLOBAL_DEFAULTS_TARGETS,
    )
    _append_changes(
        changes,
        "Currency",
        "CNY",
        frappe.get_doc("Currency", "CNY"),
        {"number_format": CNY_NUMBER_FORMAT},
    )
    return changes
```

在文件头部导入 `frappe`。每条记录固定使用键 `doctype`、`name`、`field`、`current`、`target`；若 CNY 不存在，先抛出 `frappe.DoesNotExistError`，不得创建不完整的 Currency 记录。

- [ ] **Step 4: 运行失败测试，确认只剩写入函数未实现**

```bash
cd /opt/erpnext-v16-test
docker compose exec -T backend bench --site erptest.jxmhfc.com run-tests --app company_erp --module company_erp.tests.test_setup
```

预期：依赖测试与 dry-run 测试通过，`test_diff_is_empty_after_apply` 因配置未写入失败。

- [ ] **Step 5: 实现事务性写入函数**

```python
def configure_china_defaults(dry_run: bool = False) -> list[dict[str, object]]:
    assert_china_localization_dependencies()
    changes = get_china_defaults_diff()
    if dry_run or not changes:
        return changes

    try:
        for change in changes:
            document = frappe.get_doc(change["doctype"], change["name"])
            document.set(change["field"], change["target"])
            document.save(ignore_permissions=True)
        remaining_changes = get_china_defaults_diff()
        if remaining_changes:
            frappe.throw(f"China defaults were not fully applied: {remaining_changes}")
        frappe.db.commit()
        return remaining_changes
    except Exception:
        frappe.db.rollback()
        raise
```

对 Single DocType 使用名称 `"System Settings"` 和 `"Global Defaults"`，对 Currency 使用名称 `"CNY"`。只在复查无差异后提交；任何异常调用 `frappe.db.rollback()` 后重新抛出。

- [ ] **Step 6: 运行完整配置测试并检查 dry-run/正常写入**

```bash
cd /opt/erpnext-v16-test
docker compose exec -T backend bench --site erptest.jxmhfc.com run-tests --app company_erp --module company_erp.tests.test_setup
docker compose exec -T backend bench --site erptest.jxmhfc.com execute company_erp.setup.configure_china_defaults --kwargs '{"dry_run": true}'
docker compose exec -T backend bench --site erptest.jxmhfc.com execute company_erp.setup.configure_china_defaults
```

预期：测试全部通过；第一次命令只输出差异，第二次命令输出空数组，第三次重复执行仍输出空数组。

- [ ] **Step 7: 提交配置模块**

```bash
cd /Users/yzf/Project/personal/源代码/company_erp
git add company_erp/setup.py company_erp/tests/test_setup.py
git commit -m "feat: 添加中国系统默认配置"
```

### Task 3: 将固定 App 源码接入离线部署并提供只读验收

**Files:**
- Create: `deploy/erpnext-v16-test/apps.json`
- Create: `deploy/erpnext-v16-test/versions.env`
- Create: `deploy/erpnext-v16-test/bin/verify-china-baseline.sh`
- Modify: `docs/superpowers/specs/2026-09-08-erpnext-v16-mainland-china-localization-design.md`

**Interfaces:**
- Consumes: 三个已验证本地源码目录及其 Git commit、目标站点的 Bench。
- Produces: 不访问公网的离线 App 输入清单，以及退出码可用于部署门禁的验收脚本。

- [ ] **Step 1: 写入验收脚本的失败条件测试（ShellCheck/静态检查）**

```bash
test -f deploy/erpnext-v16-test/apps.json
test -f deploy/erpnext-v16-test/versions.env
test -x deploy/erpnext-v16-test/bin/verify-china-baseline.sh
python3 -m json.tool deploy/erpnext-v16-test/apps.json >/dev/null
! rg -n 'https?://|git@' deploy/erpnext-v16-test/apps.json
```

预期：文件不存在时失败，表明部署基线尚未纳入版本控制。

- [ ] **Step 2: 创建离线 App 清单和版本文件**

`apps.json` 内容必须为：

```json
[
  {"url": "/opt/frappe/sources/erpnext", "branch": "deploy-pin"},
  {"url": "/opt/frappe/sources/erpnext_china", "branch": "deploy-pin"},
  {"url": "/opt/frappe/sources/company_erp", "branch": "deploy-pin"}
]
```

`versions.env` 必须包含 `ERPNEXT_COMMIT`、`ERPNEXT_CHINA_COMMIT`、`COMPANY_ERP_COMMIT` 和 `COMPANY_ERP_REPOSITORY`。三个 `*_COMMIT` 都必须是 40 位十六进制 SHA；构建前以 `git rev-parse --verify "$SHA^{commit}"` 验证。不得将仓库访问令牌或密码写入该文件。

- [ ] **Step 3: 实现只读验收脚本**

```bash
#!/usr/bin/env bash
set -euo pipefail

compose_dir=/opt/erpnext-v16-test
site_name=erptest.jxmhfc.com

cd "$compose_dir"
docker compose exec -T backend bench --site "$site_name" list-apps | rg -x 'erpnext_china|company_erp'
docker compose exec -T backend bench --site "$site_name" execute company_erp.setup.get_china_defaults_diff | rg -x '\[\]'
docker compose exec -T backend bench --site "$site_name" execute frappe.db.get_value --args '["Currency", "CNY", "number_format"]' | rg -x '#,###.##'
docker compose exec -T backend bench --site "$site_name" run-tests --app company_erp --module company_erp.tests.test_setup
```

脚本不得写入数据库、重建资产或调用迁移。

- [ ] **Step 4: 运行静态检查并在目标站点执行只读验收**

```bash
bash -n deploy/erpnext-v16-test/bin/verify-china-baseline.sh
python3 -m json.tool deploy/erpnext-v16-test/apps.json >/dev/null
! rg -n 'https?://|git@|password|secret|token' deploy/erpnext-v16-test/apps.json deploy/erpnext-v16-test/versions.env
/opt/erpnext-v16-test/bin/verify-china-baseline.sh
```

预期：静态检查与站点验收退出码均为 0；若配置存在差异，脚本必须失败并由 `get_china_defaults_diff()` 输出具体字段。

- [ ] **Step 5: 提交部署基线**

```bash
git add deploy/erpnext-v16-test docs/superpowers/specs/2026-09-08-erpnext-v16-mainland-china-localization-design.md
git commit -m "chore: 接入中国本地化应用基线"
```

### Task 4: 运行 erpnext_china 财务本地化验收并记录结果

**Files:**
- Create: `deploy/erpnext-v16-test/bin/verify-erpnext-china.sh`
- Create: `docs/deployment/erpnext-v16-test-china-baseline.md`

**Interfaces:**
- Consumes: 已安装的 `erpnext_china`、China/CNY 测试公司和 Task 3 的配置基线。
- Produces: 中国会计科目表、税费模板、默认账户和三张报表的可复现验收记录。

- [ ] **Step 1: 写入应失败的验收检查**

```bash
cd /opt/erpnext-v16-test
docker compose exec -T backend bench --site erptest.jxmhfc.com execute erpnext_china.chart_of_accounts.custom_accounts.custom_account.get_charts_for_country --kwargs '{"country": "China", "with_standard": true}'
```

预期：在 `erpnext_china` 未安装或其白名单方法不可调用时失败；不得以直接修改 ERPNext 科目表代码解决。

- [ ] **Step 2: 创建 China/CNY 测试公司并选择中国科目表**

通过 Desk 创建名称 `中国化验收测试公司`、国家 China、货币 CNY、会计科目表 `小企业会计准则` 的公司。记录模板名、公司缩写和创建时间到验收文档；不要把管理员密码、数据库密码写入文档。

- [ ] **Step 3: 实现只读财务验收脚本**

脚本必须检查以下项目，任一缺失立即退出非零：

```bash
docker compose exec -T backend bench --site "$site_name" list-apps | rg -x 'erpnext_china'
docker compose exec -T backend bench --site "$site_name" execute erpnext_china.chart_of_accounts.custom_accounts.custom_account.get_charts_for_country --kwargs '{"country":"China","with_standard":true}' | rg '会计'
docker compose exec -T backend bench --site "$site_name" execute frappe.db.exists --args '["Sales Taxes and Charges Template", {"company": "中国化验收测试公司"}]' | rg -x 'True'
docker compose exec -T backend bench --site "$site_name" execute frappe.db.exists --args '["Report", "Fin Balance Sheet"]' | rg -x 'True'
docker compose exec -T backend bench --site "$site_name" execute frappe.db.exists --args '["Report", "Fin Profit and Loss Statement"]' | rg -x 'True'
docker compose exec -T backend bench --site "$site_name" execute frappe.db.exists --args '["DocType", "Cash Flow"]' | rg -x 'True'
```

报表名固定为 `Fin Balance Sheet`、`Fin Profit and Loss Statement`，直接法现金流量表入口固定为 `Cash Flow` DocType。脚本只能读数据。

- [ ] **Step 4: 运行并记录验收**

```bash
bash -n deploy/erpnext-v16-test/bin/verify-erpnext-china.sh
/opt/erpnext-v16-test/bin/verify-erpnext-china.sh
```

将 App commit、Company 名称、科目模板、税费模板数量、默认账户存在性、三张报表名称与每条命令退出码写入 `docs/deployment/erpnext-v16-test-china-baseline.md`。

- [ ] **Step 5: 提交财务验收记录**

```bash
git add deploy/erpnext-v16-test/bin/verify-erpnext-china.sh docs/deployment/erpnext-v16-test-china-baseline.md
git commit -m "test: 验证中国财务本地化基线"
```

## 计划自检

- 覆盖：本计划完整覆盖 Spec 第 2–5 节及第 8 节中的配置、App 安装、CNY 和 `erpnext_china` 财务基线；主数据与单据体验留给后续独立计划。
- 无占位：每项命令、目标字段、函数接口、测试名称、会计科目表和提交信息均已确定。
- 接口一致性：Task 2 定义的 `get_china_defaults_diff`、`configure_china_defaults`、`assert_china_localization_dependencies` 被 Task 3 的部署验收脚本以相同全限定名调用。
