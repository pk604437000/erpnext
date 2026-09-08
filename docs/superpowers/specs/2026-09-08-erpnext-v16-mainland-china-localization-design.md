# ERPNext V16 中国大陆本地化设计

## 1. 目标与范围

在测试站点 `erptest.jxmhfc.com` 上完成可升级的中国大陆使用习惯适配，且不修改 Frappe 或 ERPNext 的官方源码。最终运行边界固定为：

```text
Frappe V16（官方源码）
  -> ERPNext V16（官方源码）
    -> erpnext_china（中国财务本地化）
      -> company_erp（公司中国化与业务扩展）
```

本设计将以下项目作为独立且可验收的交付批次：系统设置和财务本地化基线；主数据字段与校验；单据、打印和搜索体验。测试站点允许重建初始化公司及测试业务数据，不需要做历史数据迁移。

## 2. 已核验的现状

当前仓库是 ERPNext `version-16` 源码，部署目标版本源自 `v16.34.1`，目录本身不是 Bench：未发现 `sites/`、`site_config.json`、`common_site_config.json` 或 `apps.txt`，所以尚不能从本机读取目标站点的实时已安装 App 与系统设置。

`erpnext_china` 使用 `>=15.0.0,<17.0.0` 的 Frappe/ERPNext 依赖范围，提供简体中文翻译、中国会计科目表、公司默认科目与税费模板、中国资产负债表、利润表和直接法现金流量表。它通过 Company `doc_events` 和四个 `override_whitelisted_methods` 注入中国科目表；不使用 `override_doctype_class`。部署前必须在实际 V16 Bench 运行其测试与安装验收，不能把依赖范围视作通过 V16 回归测试的证明。

其安装代码会在首次初始化时设置 `Asia/Chongqing`、`currency_precision=2`、`float_precision=5`、`yyyy-mm-dd`，但未覆盖时间格式、数字格式或一周首日。因此安装后的最终校准必须由公司 App 执行。

旧 `erpnext_oob` 不进入 App 清单；其历史实现包含核心方法/DocType 类覆盖，版本耦合风险较高。

## 3. App 与部署边界

### 3.1 仓库和版本管理

`erpnext_china` 与 `company_erp` 均为独立 Git 仓库，生产/测试构建均使用明确 commit，不跟踪移动分支。`company_erp` 的私有远端为 `git@github.com:pk604437000/company_erp.git`。ERPNext 仓库只保存部署组合、版本清单、验收脚本和文档；不修改 `erpnext/` 下的官方实现。

日常维护统一以各仓库的 `version-16` 为基线：ERPNext 仓库的 `version-16` 只承载官方 V16 源码与本设计/部署文档；`company_erp` 仓库的 `version-16` 承载公司扩展代码。不将 `company_erp` 的 Python、fixtures 或前端资源合并到 ERPNext 核心仓库。

`company_erp` 的 `pyproject.toml` 声明 Frappe/ERPNext `>=16.21.0,<17.0.0`，并在 App 元数据中声明依赖 `erpnext_china`。构建镜像时将两个 App 的已验证源码放入 Build Context；创建站点后严格按以下顺序安装：

1. `erpnext`
2. `erpnext_china`
3. `company_erp`
4. `bench --site erptest.jxmhfc.com execute company_erp.setup.configure_china_defaults`

部署记录保存四个 App 的仓库 URL、分支、commit、构建镜像摘要及 `bench version` 输出。后续升级先在隔离测试站点运行迁移和完整验收，再替换固定 commit。

对于私有 `company_erp` 仓库，测试/生产构建节点须使用仅限该仓库读取权限的 Deploy Key，并在 `known_hosts` 固定 GitHub 主机公钥。私钥和访问令牌不得进入 `apps.json`、构建参数、镜像层、日志或 Git。完成该凭据配置前，测试环境保持在已经验证的本地 `deploy-pin` 输入；不得把该临时输入描述为远端仓库部署来源。

### 3.2 company_erp 的职责

`company_erp` 只使用 Frappe 官方扩展点：`after_install`、`after_migrate`、`doc_events`、`doctype_js`、`doctype_list_js`、fixtures、Custom Field、Property Setter、Custom DocType、Jinja 方法和必要的 `override_whitelisted_methods`。不使用 monkey patch、`override_doctype_class` 或对 Frappe/ERPNext 文件的补丁。

任何白名单方法覆盖必须同时满足：目标是公开稳定 API、无法以事件或前端扩展实现、被包装的原方法具有可回归的兼容测试。否则使用独立 API、DocType 事件或客户端脚本。

## 4. 系统设置与配置校准

`company_erp.setup.configure_china_defaults` 是站点内可重复执行的命令，支持 `dry_run=True`。它先读取配置、返回差异，再在单一数据库事务中写入目标值；异常向调用端抛出并回滚，不吞掉错误。每个字段只在当前值与目标值不同时更新。

| 位置 | 字段 | 最终值 |
| --- | --- | --- |
| System Settings | Country | `China` |
| System Settings | Language | `zh` |
| System Settings | Time Zone | `Asia/Shanghai` |
| System Settings | Date Format | `yyyy-mm-dd` |
| System Settings | Time Format | `HH:mm:ss` |
| System Settings | Number Format | `#,###.##` |
| System Settings | First Day of the Week | `Monday` |
| System Settings | Currency | `CNY` |
| System Settings | Currency Precision | `2` |
| System Settings | Float Precision | `4` |
| Global Defaults | Country | `China` |
| Global Defaults | Default Currency | `CNY` |
| Currency `CNY` | Number Format | `#,###.##` |

新建公司必须选 China、默认货币 CNY 和 `erpnext_china` 提供的适用中国会计科目表。配置命令仅校准系统/全局默认值和 CNY，不强行修改已有公司已发生业务的默认货币；测试站点的验收公司则从初始化起创建为 CNY。

对日期、时间和数字控件，先在 V16 Desk 中验证原生控件在上述格式下的创建、编辑、列表和打印显示。只有验证到具体字段或视图的行为不符合时，才在 `doctype_js` 中对该 Doctype/field 施加局部增强，不全局替换 Frappe 控件。

## 5. erpnext_china 的使用边界

`erpnext_china` 是唯一的通用中国财务本地化层，负责：

- 简体中文翻译和部分中文界面修订；
- 中国会计准则、小企业会计准则及民间非营利组织会计制度科目表；
- 中国公司创建时的默认科目、库存/费用科目和增值税税种、模板、规则；
- 中国资产负债表、利润表、直接法现金流量表、现金流编码和遗漏科目检查。

`company_erp` 不复制这些功能。验收时需创建中国测试公司，分别检查科目表、税费模板、默认账户和三张财务报表。若 V16 实测到上游兼容问题，先以最小变更提交给上游；只有测试环境需要继续验证时，才在 `company_erp` 留下短期、受测试保护的兼容层。

## 6. company_erp 的功能批次

### 批次一：基线和可审计配置

- 配置校准命令、只读差异报告、安装后校验和版本清单。
- CNY 数字格式验证，以及 China/CNY 测试公司的创建验收。
- `erpnext_china` 科目表、税费模板和三张报表的 V16 兼容性测试。

### 批次二：主数据、联系方式和地址

- 手机号服务：接受裸 11 位、`+86` 前缀、空格或连字符输入；规范化为 `+86 1XXXXXXXXXX` 显示值和 `1XXXXXXXXXX` 存储索引值。服务端拒绝不符合大陆手机号规则的非空值，前端仅提供即时提示。
- 身份证服务：校验 18 位统一格式与校验码，解析有效出生日期和性别。身份证字段以 Custom Field 添加到明确获准的员工/联系人场景，设置为受限权限级别；不将身份证参与通用列表搜索或打印。
- 中文姓名服务：新增显示名生成器，按“姓 + 名”展示；保留 Frappe 原生姓名字段以维持 API 和第三方 App 兼容。仅在创建/更新时同步展示字段，不重写标准姓名模型。
- 地址：在 Address 中增加省、市、区县的结构化 Custom Field 和省市区级联控件，保留 `address_line1`、`city`、`state`、`pincode`、`country`。保存时把结构化值同步到原生兼容字段，国家固定为 China。
- 微信和 QQ：向 Contact、Customer、Lead 添加 Custom Field，并在既有联系人关联流程的事件中单向同步。字段格式和最大长度由服务端验证。

### 批次三：单据和中文操作体验

- 人民币大写：提供纯 Python `amount_to_rmb_upper(amount)` 和 Jinja `rmb_upper`。输出包含“人民币”“元”“角”“分”，正确处理零、零角零分、负数和金额上限错误。销售发票和采购订单打印格式调用该方法。
- 中文打印：提供公共 Jinja 宏、中文字体栈和两份首批标准打印格式（销售发票、采购订单）。日期使用系统格式；金额显示 CNY 格式和人民币大写；地址按省、市、区县、详细地址顺序渲染。
- 中文单据编号：增加 China Naming Settings DocType，配置适用 Doctype、前缀和日期粒度；通过 Frappe Naming Series 生成编号，不改标准 `autoname`。首批适用 Sales Invoice、Purchase Order、Sales Order、Purchase Order。
- 拼音搜索：为明确允许的 Customer、Supplier、Item、Contact 增加全拼和首字母索引字段。保存事件用独立拼音服务更新索引；列表查询仅在用户输入不含汉字时追加受限匹配条件，不改变其他 Doctype 的查询语义。

## 7. 数据流与失败处理

```text
输入控件
  -> 前端即时提示（doctype_js）
  -> Document validate / 服务端纯函数
  -> Custom Field 或兼容原生字段
  -> 打印、列表搜索、报表
```

前端永远不是安全边界。所有格式化、号码、证件、编号和地址规则均由无副作用的 Python 服务函数验证。DocType 事件只调用这些服务函数并更新当前文档，不直接修改 Frappe/ERPNext 代码。配置命令和事件处理报错时返回清晰字段级错误；安装/迁移阶段记录 App、Doctype、字段和异常摘要，但不记录身份证完整号码等敏感值。

Fixtures 只包含 Custom Field、Property Setter、Print Format、Workspace、Role 和配置 DocType 的结构；测试或业务数据不进入 fixtures。卸载 App 默认不删除已有数据，若需要清理仅提供显式命令且先报告待影响记录。

## 8. 测试与验收

每一个新服务函数均采用测试先行：先编写并运行失败测试，再写最小实现，最后运行该测试和所属完整测试集。

| 层级 | 验收内容 |
| --- | --- |
| 单元测试 | 配置差异、手机号规范化、身份证校验、姓名拼接、地址映射、人民币大写、拼音索引、编号规则 |
| Frappe 集成测试 | App 安装、fixtures 同步、配置首跑/重复跑/干跑、字段权限、事件校验、Company 初始化 |
| erpnext_china 兼容测试 | 四个白名单方法、Company 事件、China 科目表、税费模板和财务报表 |
| Desk 浏览器验收 | 中文、日期/时间/数字、姓名、地址、联系方式、编号和打印预览 |
| 业务场景 | CNY 公司、客户、供应商、联系人、销售订单、采购订单、销售发票及采购订单打印 |
| 升级演练 | 站点备份后执行 `bench migrate`，复跑全部测试和配置差异报告 |

回滚基线为站点备份、镜像摘要及四个 App 的固定提交。升级或迁移失败时回退到该基线，不以修改 Frappe/ERPNext 核心文件作为应急手段。

## 9. 非目标

- 不实现中国税务电子发票、金税接口、银行直连或政府申报；这些能力需要另行确认法规和外部接口范围。
- 不将省市区、证件信息和拼音搜索扩展到所有 Doctype；仅覆盖本设计列明的场景。
- 不替换 Frappe 全局日期/数字控件，也不修改官方源码。
