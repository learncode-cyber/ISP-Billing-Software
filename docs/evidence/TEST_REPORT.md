# TEST REPORT — AR Qudrix ISP OS
**Executed:** 2026-08-10 · PHP 8.3.6 · PostgreSQL 16.14 · Node 22 / Vite 5

## Summary

| Suite | Total | Passed | Failed | Evidence |
|---|---|---|---|---|
| Migrations (execute against live PG) | 23 | 23 | 0 | all schemas/tables created |
| Seeders | 2 | 2 | 0 | permissions, roles, plans, features |
| migrate:fresh (drop + full re-run) | 1 | 1 | 0 | 106 tables, 97 RLS — reproducible |
| Tenant isolation penetration | 17 | 17 | 0 | `TENANT_ISOLATION_SECURITY_REPORT.md` |
| Entitlement resolver (live SQL) | 6 | 6 | 0 | below |
| Audit append-only enforcement | 2 | 2 | 0 | UPDATE + DELETE both denied |
| Business-logic triggers | 5 | 5 | 0 | below |
| Automation seed fidelity | 3 | 3 | 0 | matches AS-IS audit exactly |
| PHP lint (all source) | 102 | 102 | 0 | `php -l` |
| Frontend production build | 1 | 1 | 0 | vite, 58 modules |
| Frontend component render | 12 | 12 | 0 | react-dom/server, incl. edge cases |
| Responsive contract lint | 16 | 16 | 0 | `RESPONSIVE_QA_REPORT.md` |
| **TOTAL** | **190** | **190** | **0** | |

## Entitlement engine (live)
| Test | Expected | Actual | Result |
|---|---|---|---|
| Starter plan + `network.olt.manage` | deny | false | PASS |
| Enterprise + `network.olt.manage` | allow | true | PASS |
| Starter + `billing.core` | allow | true | PASS |
| Starter + `compliance.news.view` (BTRC news free on all plans) | allow | true | PASS |
| Unknown feature key | deny (secure default) | false | PASS |
| Tenant feature override grants OLT to Starter | allow | true | PASS |

## Business logic (live DB triggers)
| Test | Expected | Actual | Result |
|---|---|---|---|
| Partial payment 200/500 | status=partial | partial, paid=200.00 | PASS |
| Second payment 300 | status=paid | paid, paid=500.00 | PASS |
| Duplicate invoice same period | rejected | unique-constraint violation | PASS |
| Expense → GL auto-post | 1 ledger row, debit 1500 | exact | PASS |
| Salary → expense → GL (20000+1000−500) | 20500 | 20500.00 | PASS |

## Automation seed fidelity (AS-IS audit preservation)
| Test | Result |
|---|---|
| 10 default rules per tenant | PASS |
| Complaint SMS + Advance Paid SMS seeded **disabled** (matching audit's observed "Status: Inactive") | PASS |
| Auto-disconnect rule seeded **active** (verified client behaviour preserved) | PASS |

## Not executed — see FINAL_RELEASE_REPORT.md
HTTP-layer API tests, browser viewport tests, E2E business workflows through the UI. These require `composer install` (no Composer/Packagist access in this environment) and a headless browser (unavailable).
