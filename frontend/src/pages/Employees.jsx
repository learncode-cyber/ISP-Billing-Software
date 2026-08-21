import { useEffect, useState } from "react";
import { repo, mutate } from "../offline/repository";
import { PageHeader, DataTable, StatusPill, FormModal } from "../components/primitives";

export function Employees() {
  const [employees, setEmployees] = useState([]);
  const [creating, setCreating] = useState(false);
  const [payTarget, setPayTarget] = useState(null);
  const load = () => repo.employees().then(({ rows }) => setEmployees(rows)).catch(() => setEmployees([]));
  useEffect(() => { load(); }, []);
  const columns = [
    { key: "name", label: "Name", render: (r) => <strong>{r.name}</strong> },
    { key: "mobile", label: "Mobile", num: true },
    { key: "monthly_salary", label: "Salary", align: "right", num: true, render: (r) => `৳ ${Number(r.monthly_salary).toLocaleString()}` },
    { key: "status", label: "Status", render: (r) => <StatusPill status={r.status} /> },
    { key: "actions", label: "", align: "right", render: (r) => <button className="btn btn-ghost" style={{ padding: "4px 10px", fontSize: 12 }} onClick={() => setPayTarget(r)}>Pay Salary</button> },
  ];
  return (
    <>
      <PageHeader title="Employees" subtitle="Staff and payroll" action={<button className="btn btn-primary" onClick={() => setCreating(true)}>+ Add Employee</button>} />
      <DataTable columns={columns} rows={employees} empty="No employees yet." />
      {creating && (
        <FormModal title="Add Employee" submitLabel="Create"
          fields={[
            { name: "name", label: "Name", required: true },
            { name: "mobile", label: "Mobile" },
            { name: "email", label: "Email" },
            { name: "nid", label: "NID" },
            { name: "joining_date", label: "Joining Date", type: "date" },
            { name: "monthly_salary", label: "Monthly Salary", type: "number", required: true },
            { name: "status", label: "Status", type: "select", options: ["active", "inactive"], default: "active" },
            { name: "address", label: "Address" },
          ]}
          onSubmit={(v) => mutate("CREATE_EMPLOYEE", { payload: v, optimistic: { ...v, status: v.status || "active" } })}
          onClose={(saved) => { setCreating(false); if (saved) load(); }} />
      )}
      {payTarget && (
        <FormModal title={`Pay Salary — ${payTarget.name}`} submitLabel="Pay"
          fields={[
            { name: "period_month", label: "Month (1-12)", type: "number", required: true, default: new Date().getMonth() + 1 },
            { name: "period_year", label: "Year", type: "number", required: true, default: new Date().getFullYear() },
            { name: "payment_amount", label: "Payment Amount", type: "number", required: true, default: payTarget.monthly_salary },
            { name: "conveyance_amount", label: "Conveyance", type: "number", default: 0 },
            { name: "punishment_amount", label: "Punishment", type: "number", default: 0 },
          ]}
          onSubmit={(v) => mutate("PAY_SALARY", { targetId: payTarget.id, payload: v })}
          onClose={(saved) => { setPayTarget(null); if (saved) load(); }} />
      )}
    </>
  );
}
