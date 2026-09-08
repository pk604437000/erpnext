# Company ERP China Document Experience Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the remaining mainland-China search, printing and numbering gaps while reusing capabilities already supplied by `erpnext_china`.

**Architecture:** Hidden Custom Fields hold full-pinyin and initial indexes for four master DocTypes; normal Frappe search reads them through fixture-backed Property Setters. `erpnext_china.print_utils` remains the RMB-uppercase source and its existing naming-series Property Setters remain authoritative. Company print helpers are additive Jinja functions only.

**Tech Stack:** Frappe V16 fixtures/hooks, Python, pypinyin 0.55.0, Jinja.

**Spec:** `docs/superpowers/specs/2026-09-08-erpnext-v16-mainland-china-localization-design.md`

## Global Constraints

- No Frappe/ERPNext core modifications, monkey patches or DocType-class overrides.
- Do not duplicate RMB uppercase and naming-series behavior already supplied by `erpnext_china`.
- Limit pinyin indexing to Customer, Supplier, Item and Contact.

---

### Task 1: Pinyin indexes

**Files:**
- Modify: `pyproject.toml`
- Create: `company_erp/china/pinyin.py`
- Modify: `company_erp/hooks.py`
- Modify: `company_erp/fixtures/custom_field.json`
- Create: `company_erp/fixtures/property_setter.json`
- Create: `company_erp/tests/test_pinyin.py`

- [ ] Write failing tests proving `徐福记食品` produces `xufujishipin` and `xfjsp`, and each supported DocType selects its native display text.
- [ ] Run the test and confirm the missing-module failure.
- [ ] Add `pypinyin==0.55.0`, implement `build_pinyin_indexes(text)` and `update_pinyin_indexes(doc, method=None)`, and register validate events.
- [ ] Add hidden/read-only/search-index Custom Fields and Property Setters that preserve each original `search_fields` value while appending both indexes.
- [ ] Migrate and run tests; query metadata to prove fields are searchable.
- [ ] Commit `feat: 添加中文拼音搜索索引`.

### Task 2: Printing and existing-localization verification

**Files:**
- Create: `company_erp/china/print_utils.py`
- Modify: `company_erp/hooks.py`
- Create: `company_erp/tests/test_print_utils.py`

- [ ] Write failing tests for compact China address rendering and confirm missing implementation.
- [ ] Implement `format_china_address(doc) -> str`, HTML-escape components, omit empty components, and expose it through the Jinja methods hook.
- [ ] Run tests and verify `erpnext_china.print_utils.cncurrency('1234.56')` and its naming-series Property Setters on the live site.
- [ ] Commit `feat: 添加中文打印辅助方法`.

### Task 3: Final immutable deployment

- [ ] Build a commit-pinned `company_erp` image, switch only app containers, migrate, build assets and clear cache.
- [ ] Run all Company ERP tests and read-only checks for apps, settings, Custom Fields, Property Setters and service health.
- [ ] Commit deployment documentation changes with `docs: 更新中国本地化部署记录`.
