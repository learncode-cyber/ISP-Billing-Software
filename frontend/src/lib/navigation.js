// navigation.js
//
// The full module tree from the Blueprint, each item annotated with the
// feature key (subscription gate) and permission (RBAC gate) it requires.
// The sidebar renders an item only when hasFeature(feature) && can(perm) —
// so a Starter-plan tenant simply never sees OLT/Reseller/AI, and a
// Billing Operator never sees HR. One declarative source, zero per-page
// plan logic (Blueprint Section 37).

export const NAV_SECTIONS = [
  {
    label: "Overview", i18nKey: "nav.overview",
    items: [
      { key: "dashboard", label: "Dashboard", i18nKey: "nav.dashboard", path: "/", feature: null, perm: null, icon: "grid" },
    ],
  },
  {
    label: "Customers & Billing", i18nKey: "nav.customersBilling",
    items: [
      { key: "customers", label: "Customers", i18nKey: "nav.customers", path: "/customers", feature: "isp.customer.manage", perm: "isp.customer.view", icon: "users" },
      { key: "leads", label: "Leads", i18nKey: "nav.leads", path: "/leads", feature: "crm.core", perm: "crm.core.manage", icon: "target" },
      { key: "billing", label: "Bill Collection", i18nKey: "nav.billing", path: "/billing", feature: "billing.core", perm: "billing.invoice.view", icon: "receipt" },
    ],
  },
  {
    label: "Network", i18nKey: "nav.network",
    items: [
      { key: "mikrotik", label: "MikroTik", i18nKey: "nav.mikrotik", path: "/network/mikrotik", feature: "network.mikrotik.manage", perm: "network.mikrotik.manage", icon: "router" },
      { key: "ipam", label: "IP Management", i18nKey: "nav.ipam", path: "/network/ipam", feature: "network.mikrotik.manage", perm: "network.mikrotik.manage", icon: "network" },
      { key: "olt", label: "OLT / GPON", i18nKey: "nav.olt", path: "/network/olt", feature: "network.olt.manage", perm: "network.olt.manage", icon: "server" },
            { key: "monitoring", label: "Monitoring", i18nKey: "nav.monitoring", path: "/network/monitoring", feature: "network.monitoring", perm: "network.diagram.view", icon: "activity" },
      { key: "diagram", label: "Network Diagram", i18nKey: "nav.diagram", path: "/network/diagram", feature: "network.mikrotik.manage", perm: "network.diagram.view", icon: "share" },
    ],
  },
  {
    label: "Operations", i18nKey: "nav.operations",
    items: [
      { key: "tickets", label: "Complaints", i18nKey: "nav.tickets", path: "/tickets", feature: "support.ticketing", perm: "support.ticket.view", icon: "ticket" },
      { key: "fieldjobs", label: "Field Jobs", i18nKey: "nav.fieldJobs", path: "/field-jobs", feature: "support.field_service", perm: "support.ticket.view", icon: "map-pin" },
      { key: "inventory", label: "Inventory", i18nKey: "nav.inventory", path: "/inventory", feature: "inventory.core", perm: "inventory.stock.manage", icon: "box" },
    ],
  },
  {
    label: "Finance & People", i18nKey: "nav.finance",
    items: [
      { key: "expenses", label: "Expenses", i18nKey: "nav.expenses", path: "/expenses", feature: "accounting.core", perm: "accounting.expense.manage", icon: "trending-down" },
      { key: "employees", label: "Employees", i18nKey: "nav.employees", path: "/employees", feature: "hr.payroll", perm: "hr.employee.view", icon: "id-card" },
      { key: "resellers", label: "Resellers", i18nKey: "nav.resellers", path: "/resellers", feature: "reseller.management", perm: "reseller.account.manage", icon: "network" },
    ],
  },
  {
    label: "Intelligence & Config", i18nKey: "nav.intelligence",
    items: [
      { key: "ai", label: "AI Assistant", i18nKey: "nav.ai", path: "/ai", feature: "ai.nl_analytics", perm: "accounting.statement.view", icon: "sparkles" },
      { key: "automation", label: "Automation", i18nKey: "nav.automation", path: "/automation", feature: "automation.engine", perm: "identity.role.manage", icon: "zap" },
      // BTRC news: no feature gate (free on every plan), only the permission.
      { key: "news", label: "Regulatory News", i18nKey: "nav.news", path: "/news", feature: null, perm: "compliance.news.view", icon: "newspaper" },
      // Always visible: offline sync state is not a licensed feature.
      { key: "sync", label: "Sync", path: "/sync", feature: null, perm: null, icon: "activity" },
    ],
  },
];
