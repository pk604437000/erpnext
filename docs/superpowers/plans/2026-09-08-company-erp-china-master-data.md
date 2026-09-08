# Company ERP China Master Data Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add mainland-China contact and address data conventions without modifying Frappe or ERPNext source.

**Architecture:** `company_erp` installs Custom Field fixtures for existing Contact, Address, Customer and Lead DocTypes. Small pure validation and normalization services are called through `doc_events`; browser code only provides address-field interaction and never replaces server validation.

**Tech Stack:** Frappe V16 fixtures, Custom Field, `doc_events`, `doctype_js`, Python unittest/FrappeTestCase.

**Spec:** `docs/superpowers/specs/2026-09-08-erpnext-v16-mainland-china-localization-design.md`

## Global Constraints

- Do not modify Frappe V16 or ERPNext V16 core source.
- Keep `erpnext_china` as the shared localization layer and `company_erp` as company-specific code.
- Use fixtures, hooks, document events and custom JS; do not monkey patch or override DocType classes.
- Reject invalid mainland mobile phone and PRC identity-card input on the server; empty optional values remain valid.
- Preserve `Address.address_line1`, `city`, `state`, `pincode` and `country`; structured fields synchronize to those compatibility fields.

---

### Task 1: Pure mainland-China validators

**Files:**
- Create: `company_erp/company_erp/china/validators.py`
- Create: `company_erp/company_erp/tests/test_validators.py`

**Interfaces:**
- Produces `normalize_mobile(value: str | None) -> str | None`, `validate_prc_id(value: str | None) -> None`, `validate_social_handle(field: str, value: str | None) -> None`.

- [ ] **Step 1: Write failing tests** for `13800138000`, `+86 13800138000`, invalid mobile prefix/length, known valid `11010519491231002X`, checksum failure, and QQ/WeChat length/character limits.
- [ ] **Step 2: Run** `bench --site erptest.jxmhfc.com run-tests --app company_erp --module company_erp.tests.test_validators`; expect import failure.
- [ ] **Step 3: Implement** the mobile regex `^1[3-9]\\d{9}$`, GB 11643 checksum weights, and bounded handles (QQ `^[1-9]\\d{4,11}$`; WeChat `^[A-Za-z][A-Za-z0-9_-]{5,19}$`).
- [ ] **Step 4: Re-run** the validator module; expect all tests pass.
- [ ] **Step 5: Commit** `feat: 添加中国主数据校验`.

### Task 2: Fixture-backed fields and server synchronization

**Files:**
- Create: `company_erp/company_erp/fixtures/custom_field.json`
- Create: `company_erp/company_erp/china/master_data.py`
- Modify: `company_erp/company_erp/hooks.py`
- Create: `company_erp/company_erp/tests/test_master_data.py`

**Interfaces:**
- Consumes validator functions and custom fields `china_mobile_no`, `china_id_number`, `china_wechat`, `china_qq`, `china_province`, `china_city`, `china_district`.
- Produces `validate_contact(doc, method=None)`, `sync_address(doc, method=None)`, `sync_contact_channels(doc, method=None)` through `doc_events`.

- [ ] **Step 1: Write failing Frappe tests** that save a Contact with normalized mobile/valid ID, reject invalid values, and save an Address whose province/city/district synchronizes `state`, `city`, `country="China"`.
- [ ] **Step 2: Run** the module; expect fields/events unavailable.
- [ ] **Step 3: Add fixtures** for optional Contact fields, optional Customer/Lead WeChat+QQ fields, and optional Address province/city/district fields; fixture filters only `fieldname` beginning `china_`.
- [ ] **Step 4: Implement hooks** for Contact `validate`, Address `validate`, Customer/Lead `validate`; normalize Contact mobile, validate ID/channels, synchronize address compatibility fields, and copy non-empty Contact channels only to linked Customer/Lead when their fields are empty.
- [ ] **Step 5: Re-run** tests and `bench --site erptest.jxmhfc.com migrate`; expect fixtures installed and all tests pass.
- [ ] **Step 6: Commit** `feat: 添加中国联系人和地址字段`.

### Task 3: Address form interaction and deployment verification

**Files:**
- Create: `company_erp/company_erp/public/js/address.js`
- Modify: `company_erp/company_erp/hooks.py`
- Create: `company_erp/company_erp/tests/test_hooks.py`

**Interfaces:**
- Produces `doctype_js = {"Address": "public/js/address.js"}` and client behavior that clears dependent city/district values when an upstream administrative level changes.

- [ ] **Step 1: Write a hook test** asserting the `Address` JS registration remains declarative and no class override/monkey patch hooks are set.
- [ ] **Step 2: Run** the test; expect registration failure.
- [ ] **Step 3: Implement** concise Form handlers for `china_province` and `china_city` that clear only downstream custom fields; server `sync_address` remains authoritative.
- [ ] **Step 4: Run** all `company_erp` tests, `bench --site erptest.jxmhfc.com migrate`, and create/validate a Contact and Address through Frappe APIs.
- [ ] **Step 5: Commit** `feat: 添加中国地址表单交互`.

### Task 4: Remaining China document experience

**Files:**
- Create: `docs/superpowers/plans/2026-09-08-company-erp-china-documents.md`

- [ ] **Step 1: Write the follow-up plan** covering RMB uppercase Jinja filter, Chinese print format, naming series, pinyin indexes and list query restrictions as separate testable components.
- [ ] **Step 2: Commit** `docs: 添加中国单据体验计划`.
