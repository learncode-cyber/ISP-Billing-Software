-- Grants the CI application role exactly what the running app gets:
-- full DML on tenant tables, but no UPDATE/DELETE on append-only logs.
DO $$ DECLARE s TEXT; BEGIN
  FOR s IN SELECT nspname FROM pg_namespace WHERE nspname IN
    ('platform','tenancy','subscription','identity','crm','isp','billing','network','support',
     'accounting','hr','inventory','reseller','communication','automation','analytics',
     'compliance','audit','integrations','ai') LOOP
    EXECUTE format('GRANT USAGE ON SCHEMA %I TO arq_app_role, arq_platform_admin_role', s);
    EXECUTE format('GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA %I TO arq_app_role, arq_platform_admin_role', s);
    EXECUTE format('GRANT USAGE ON ALL SEQUENCES IN SCHEMA %I TO arq_app_role, arq_platform_admin_role', s);
  END LOOP;
END $$;
REVOKE UPDATE, DELETE ON audit.activity_logs FROM arq_app_role;
REVOKE UPDATE, DELETE ON compliance.ip_session_logs FROM arq_app_role;
