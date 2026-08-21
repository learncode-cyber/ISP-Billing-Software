\pset tuples_only on
\pset format unaligned
-- Entitlement engine: plan gating, platform defaults, overrides, secure default.
SELECT 'E1 starter+OLT denied      | '||CASE WHEN NOT subscription.resolve_feature_access(
  (SELECT id FROM tenancy.tenants WHERE slug='tenant-a'),'network.olt.manage') THEN 'PASS' ELSE 'FAIL' END;
SELECT 'E2 BTRC news free on all   | '||CASE WHEN subscription.resolve_feature_access(
  (SELECT id FROM tenancy.tenants WHERE slug='tenant-a'),'compliance.news.view') THEN 'PASS' ELSE 'FAIL' END;
SELECT 'E3 unknown key denies      | '||CASE WHEN NOT subscription.resolve_feature_access(
  (SELECT id FROM tenancy.tenants WHERE slug='tenant-a'),'nope.does.not.exist') THEN 'PASS' ELSE 'FAIL' END;
