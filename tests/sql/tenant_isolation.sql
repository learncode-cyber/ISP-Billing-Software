\pset tuples_only on
\pset format unaligned
-- Authenticate as Tenant A ONLY
SELECT set_config('app.current_tenant_id','aaaaaaaa-0000-0000-0000-000000000001',false);
SELECT set_config('app.is_platform_admin','false',false);

-- ===== READ isolation across every sensitive table =====
SELECT 'S01 customers        | own='||count(*) FILTER (WHERE tenant_id='aaaaaaaa-0000-0000-0000-000000000001')
   ||' foreign='||count(*) FILTER (WHERE tenant_id<>'aaaaaaaa-0000-0000-0000-000000000001')
   ||' | '||CASE WHEN count(*) FILTER (WHERE tenant_id<>'aaaaaaaa-0000-0000-0000-000000000001')=0 THEN 'PASS' ELSE 'FAIL LEAK' END FROM isp.customers;
SELECT 'S02 invoices         | foreign='||count(*)||' | '||CASE WHEN count(*)=0 THEN 'PASS' ELSE 'FAIL LEAK' END FROM billing.invoices WHERE tenant_id<>'aaaaaaaa-0000-0000-0000-000000000001';
SELECT 'S03 payments         | foreign='||count(*)||' | '||CASE WHEN count(*)=0 THEN 'PASS' ELSE 'FAIL LEAK' END FROM billing.payments WHERE tenant_id<>'aaaaaaaa-0000-0000-0000-000000000001';
SELECT 'S04 tickets          | foreign='||count(*)||' | '||CASE WHEN count(*)=0 THEN 'PASS' ELSE 'FAIL LEAK' END FROM support.tickets WHERE tenant_id<>'aaaaaaaa-0000-0000-0000-000000000001';
SELECT 'S05 employees        | foreign='||count(*)||' | '||CASE WHEN count(*)=0 THEN 'PASS' ELSE 'FAIL LEAK' END FROM hr.employees WHERE tenant_id<>'aaaaaaaa-0000-0000-0000-000000000001';
SELECT 'S06 inventory        | foreign='||count(*)||' | '||CASE WHEN count(*)=0 THEN 'PASS' ELSE 'FAIL LEAK' END FROM inventory.products WHERE tenant_id<>'aaaaaaaa-0000-0000-0000-000000000001';
SELECT 'S07 IPAM subnets     | foreign='||count(*)||' | '||CASE WHEN count(*)=0 THEN 'PASS' ELSE 'FAIL LEAK' END FROM network.ip_subnets WHERE tenant_id<>'aaaaaaaa-0000-0000-0000-000000000001';
SELECT 'S08 audit logs       | foreign='||count(*)||' | '||CASE WHEN count(*)=0 THEN 'PASS' ELSE 'FAIL LEAK' END FROM audit.activity_logs WHERE tenant_id<>'aaaaaaaa-0000-0000-0000-000000000001';
SELECT 'S09 branches         | foreign='||count(*)||' | '||CASE WHEN count(*)=0 THEN 'PASS' ELSE 'FAIL LEAK' END FROM tenancy.branches WHERE tenant_id<>'aaaaaaaa-0000-0000-0000-000000000001';
SELECT 'S10 CPE devices      | foreign='||count(*)||' | '||CASE WHEN count(*)=0 THEN 'PASS' ELSE 'FAIL LEAK' END FROM network.cpe_devices WHERE tenant_id<>'aaaaaaaa-0000-0000-0000-000000000001';
SELECT 'S11 BTRC IP logs     | foreign='||count(*)||' | '||CASE WHEN count(*)=0 THEN 'PASS' ELSE 'FAIL LEAK' END FROM compliance.ip_session_logs WHERE tenant_id<>'aaaaaaaa-0000-0000-0000-000000000001';
SELECT 'S12 automation rules | foreign='||count(*)||' | '||CASE WHEN count(*)=0 THEN 'PASS' ELSE 'FAIL LEAK' END FROM automation.rules WHERE tenant_id<>'aaaaaaaa-0000-0000-0000-000000000001';
SELECT 'S13 resellers        | foreign='||count(*)||' | '||CASE WHEN count(*)=0 THEN 'PASS' ELSE 'FAIL LEAK' END FROM reseller.resellers WHERE tenant_id<>'aaaaaaaa-0000-0000-0000-000000000001';
SELECT 'S14 ledger entries   | foreign='||count(*)||' | '||CASE WHEN count(*)=0 THEN 'PASS' ELSE 'FAIL LEAK' END FROM accounting.ledger_entries WHERE tenant_id<>'aaaaaaaa-0000-0000-0000-000000000001';

-- ===== IDOR: direct UUID access to B and C records =====
SELECT 'S15 IDOR customer B  | rows='||count(*)||' | '||CASE WHEN count(*)=0 THEN 'PASS' ELSE 'FAIL' END FROM isp.customers WHERE id='b4000000-0000-0000-0000-000000000002';
SELECT 'S16 IDOR customer C  | rows='||count(*)||' | '||CASE WHEN count(*)=0 THEN 'PASS' ELSE 'FAIL' END FROM isp.customers WHERE id='c4000000-0000-0000-0000-00000000000c';
SELECT 'S17 IDOR invoice C   | rows='||count(*)||' | '||CASE WHEN count(*)=0 THEN 'PASS' ELSE 'FAIL' END FROM billing.invoices WHERE id='c6000000-0000-0000-0000-00000000000c';
SELECT 'S18 IDOR ticket C    | rows='||count(*)||' | '||CASE WHEN count(*)=0 THEN 'PASS' ELSE 'FAIL' END FROM support.tickets WHERE id='c7000000-0000-0000-0000-00000000000c';

-- ===== Relationship traversal: reach B/C through joins =====
SELECT 'S19 traverse svc->cust | rows='||count(*)||' | '||CASE WHEN count(*)=0 THEN 'PASS' ELSE 'FAIL' END
 FROM isp.customer_services s JOIN isp.customers c ON c.id=s.customer_id WHERE c.tenant_id<>'aaaaaaaa-0000-0000-0000-000000000001';
SELECT 'S20 traverse inv->svc  | rows='||count(*)||' | '||CASE WHEN count(*)=0 THEN 'PASS' ELSE 'FAIL' END
 FROM billing.invoices i JOIN isp.customer_services s ON s.id=i.customer_service_id WHERE i.tenant_id<>'aaaaaaaa-0000-0000-0000-000000000001';
SELECT 'S21 traverse ticket->cust | rows='||count(*)||' | '||CASE WHEN count(*)=0 THEN 'PASS' ELSE 'FAIL' END
 FROM support.tickets t JOIN isp.customers c ON c.id=t.customer_id WHERE c.tenant_id<>'aaaaaaaa-0000-0000-0000-000000000001';

-- ===== Aggregate / export leakage =====
-- First, INSERT a valid customer for Tenant A (must have all required fields)
INSERT INTO isp.customers (
  id, tenant_id, branch_id, customer_code, full_name, mobile, email, status, created_at, updated_at
) VALUES (
  'a3000000-0000-0000-0000-00000000000a',
  'aaaaaaaa-0000-0000-0000-000000000001',
  'a1000000-0000-0000-0000-00000000000a',
  'TEST-CUST-A',
  'Test Customer A',
  '+8801700000001',
  'test-a@example.com',
  'active',
  NOW(),
  NOW()
) ON CONFLICT DO NOTHING;

SELECT 'S22 revenue aggregate | sum='||COALESCE(sum(total_due),0)||' | '||CASE WHEN COALESCE(sum(total_due),0)<=500 THEN 'PASS (own only)' ELSE 'FAIL LEAK' END FROM billing.invoices;
SELECT 'S23 customer count    | n='||count(*)||' | '||CASE WHEN count(*)>=1 THEN 'PASS' ELSE 'FAIL' END FROM isp.customers;

-- ===== WRITE attacks =====
WITH u AS (UPDATE isp.customers SET full_name='PWNED' WHERE id='c4000000-0000-0000-0000-00000000000c' RETURNING 1)
SELECT 'S24 UPDATE C customer | rows='||count(*)||' | '||CASE WHEN count(*)=0 THEN 'PASS' ELSE 'FAIL BREACH' END FROM u;
WITH d AS (DELETE FROM support.tickets WHERE id='c7000000-0000-0000-0000-00000000000c' RETURNING 1)
SELECT 'S25 DELETE C ticket   | rows='||count(*)||' | '||CASE WHEN count(*)=0 THEN 'PASS' ELSE 'FAIL BREACH' END FROM d;
WITH d AS (DELETE FROM network.ip_subnets WHERE id='c8000000-0000-0000-0000-00000000000c' RETURNING 1)
SELECT 'S26 DELETE C subnet   | rows='||count(*)||' | '||CASE WHEN count(*)=0 THEN 'PASS' ELSE 'FAIL BREACH' END FROM d;
WITH u AS (UPDATE network.cpe_devices SET status='error' WHERE id='c9000000-0000-0000-0000-00000000000c' RETURNING 1)
SELECT 'S27 UPDATE C CPE      | rows='||count(*)||' | '||CASE WHEN count(*)=0 THEN 'PASS' ELSE 'FAIL BREACH' END FROM u;

-- ===== Cross-tenant INSERT (forge a row into another tenant) =====

-- Cross-tenant INSERT forge (must raise, so run last)
\set ON_ERROR_STOP off
INSERT INTO isp.customers (tenant_id,branch_id,customer_code,full_name,mobile)
VALUES ('cccccccc-0000-0000-0000-00000000000c','c1000000-0000-0000-0000-00000000000c','FORGED','Injected','000');
\set ON_ERROR_STOP on
