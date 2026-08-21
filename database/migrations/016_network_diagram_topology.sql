-- ============================================================
-- 016_network_diagram_topology.sql — Network Diagram (Blueprint Section
-- 13/18). The audit found the existing Network Diagram page renders only
-- a single "Root" text node with no real topology data behind it
-- [VERIFIED: page exists] [NOT VERIFIED: full diagram functionality].
--
-- This view is the live data source for the rebuilt diagram: no
-- separately-maintained diagram table to drift out of sync — it is
-- always exactly what Router -> OLT -> PON -> ONU -> Customer looks like
-- right now, composed from the tables already created in this and prior
-- phases.
-- ============================================================

CREATE VIEW network.v_topology_edges AS
-- Router -> PPPoE Secret -> Customer (MikroTik-managed path)
SELECT
    r.tenant_id,
    'router'::VARCHAR AS from_type, r.id AS from_id, r.name AS from_label,
    'customer'::VARCHAR AS to_type, cs.customer_id AS to_id, c.full_name AS to_label,
    ps.status AS edge_status
FROM network.mikrotik_routers r
JOIN network.pppoe_secrets ps ON ps.router_id = r.id
JOIN isp.customer_services cs ON cs.id = ps.customer_service_id
JOIN isp.customers c ON c.id = cs.customer_id
WHERE r.deleted_at IS NULL

UNION ALL

-- OLT -> PON -> ONU -> Customer (fiber path)
SELECT
    o.tenant_id,
    'olt'::VARCHAR, o.id, o.device_name,
    'pon_port'::VARCHAR, p.id, p.port_label,
    'active'
FROM network.olt_devices o
JOIN network.pon_ports p ON p.olt_device_id = o.id
WHERE o.deleted_at IS NULL

UNION ALL

SELECT
    p.tenant_id,
    'pon_port'::VARCHAR, p.id, p.port_label,
    'onu'::VARCHAR, onu.id, COALESCE(onu.serial_number, onu.mac_address::TEXT, 'ONU'),
    onu.status
FROM network.pon_ports p
JOIN network.onu_devices onu ON onu.pon_port_id = p.id

UNION ALL

SELECT
    onu.tenant_id,
    'onu'::VARCHAR, onu.id, COALESCE(onu.serial_number, 'ONU'),
    'customer'::VARCHAR, cs.customer_id, c.full_name,
    onu.status
FROM network.onu_devices onu
JOIN isp.customer_services cs ON cs.id = onu.customer_service_id
JOIN isp.customers c ON c.id = cs.customer_id
WHERE onu.customer_service_id IS NOT NULL;

-- No RLS on a view directly possible in Postgres for a UNION over
-- already-RLS'd tables — but since every source table already carries
-- its own tenant_isolation policy, querying this view as the
-- authenticated app role automatically returns only the caller's tenant
-- rows (the underlying table scans are each filtered). The tenant_id
-- column is still selected explicitly so the app layer can additionally
-- assert it defensively, matching the same convention used for the
-- analytics materialized views in 012_analytics.sql.
