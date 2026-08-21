// ModulePage.jsx — a faithful scaffold for the remaining modules (OLT,
// Monitoring, Tickets, Field Jobs, Inventory, Expenses, Employees,
// Resellers, AI, Automation, Leads, Network Diagram). Each renders its
// real PageHeader + the intended structure so the shell is complete and
// navigable; the data-bound tables/forms drop into these in turn as each
// module's frontend is fleshed out, exactly as Dashboard/Customers/
// BillCollection/MikroTik already are.

import { PageHeader } from "../components/primitives";
import { Icon } from "../components/Icon";

const MODULES = {
  olt: { title: "OLT / GPON", subtitle: "Optical line terminals, PON ports, and ONUs", icon: "server",
    points: ["Register OLT devices (BDCOM, V-SOL, ZTE, Huawei, Fiberhome)", "Check connection over SNMP/Telnet", "Discover ONUs and monitor RX/TX signal, LOS alarms"] },
  monitoring: { title: "Network Monitoring", subtitle: "Uptime, latency, and alerts", icon: "activity",
    points: ["Live reachability for routers and OLTs", "Open / acknowledged / resolved alerts", "Incident grouping for NOC workflow"] },
  diagram: { title: "Network Diagram", subtitle: "Router → OLT → PON → ONU → Customer", icon: "share",
    points: ["Live topology composed from current network data", "Colour-coded by link status", "Replaces the legacy single-node diagram"] },
  tickets: { title: "Complaints", subtitle: "Customer complaint and ticket workflow", icon: "ticket",
    points: ["Create → assign → process → solve", "Priority, category, SLA, escalation", "Customer + assigned-employee SMS, CSAT rating"] },
  "field-jobs": { title: "Field Jobs", subtitle: "Technician installation and repair", icon: "map-pin",
    points: ["Assigned jobs with customer location", "GPS check-in / check-out, photos, signature", "Spare parts drawn from inventory"] },
  inventory: { title: "Inventory", subtitle: "Stock, products, suppliers, purchases", icon: "box",
    points: ["Product categories, serialized ONU/router tracking", "Purchases, sales, returns, warehouses", "Low-stock alerts and customer hardware assignment"] },
  expenses: { title: "Expenses", subtitle: "Expense entries and account heads", icon: "trending-down",
    points: ["Filter by month / year / head", "Approval workflow", "Auto-posts to the general ledger"] },
  employees: { title: "Employees", subtitle: "Staff records and payroll", icon: "id-card",
    points: ["Employee list, designations, departments", "Pay salary (payment, conveyance, punishment)", "Posts to accounting under head “Employee”"] },
  resellers: { title: "Resellers", subtitle: "Dealers, franchises, commission", icon: "network",
    points: ["Reseller / sub-reseller hierarchy", "Wallet, credit limit, settlement", "Commission rules and customer ownership"] },
  ai: { title: "AI Assistant", subtitle: "Natural-language analytics", icon: "sparkles",
    points: ["Ask questions like “which zone had the highest churn?”", "Churn-risk scoring per customer", "Answers stay within your tenant and permissions"] },
  automation: { title: "Automation", subtitle: "Trigger → Condition → Action rules", icon: "zap",
    points: ["Bill overdue → disconnect, payment → reconnect", "New customer → welcome SMS, ONU LOS → ticket", "Full execution log for every run"] },
  leads: { title: "Leads", subtitle: "Pre-sale pipeline and conversion", icon: "target",
    points: ["Capture, follow-up, qualify", "Convert to customer in one step", "Communication history"] },
};

export function ModulePage({ moduleKey }) {
  const m = MODULES[moduleKey] || { title: "Module", subtitle: "", icon: "grid", points: [] };
  return (
    <>
      <PageHeader title={m.title} subtitle={m.subtitle} />
      <div className="card" style={{ padding: 28 }}>
        <div style={{ color: "var(--primary)", marginBottom: 12 }}><Icon name={m.icon} size={26} /></div>
        <p style={{ margin: "0 0 14px", color: "var(--ink-soft)", fontSize: 13.5 }}>
          This module is available on your plan. Its data views:
        </p>
        <ul style={{ margin: 0, paddingLeft: 18, color: "var(--ink)", fontSize: 13.5, lineHeight: 1.9 }}>
          {m.points.map((p, i) => <li key={i}>{p}</li>)}
        </ul>
      </div>
    </>
  );
}
