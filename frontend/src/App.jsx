// App.jsx — routes. Authenticated routes render inside AppShell (with the
// capabilities-driven sidebar); /login is outside it. Every module now
// has a real data-bound page (only field-jobs remains a scaffold, as it's
// primarily a mobile/technician surface).

import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom";
import { I18nProvider } from "./i18n";
import { CapabilitiesProvider } from "./context/CapabilitiesContext";
import { AppShell } from "./layouts/AppShell";
import { Login } from "./pages/Login";
import { Dashboard } from "./pages/Dashboard";
import { Customers } from "./pages/Customers";
import { BillCollection } from "./pages/BillCollection";
import { Mikrotik } from "./pages/Mikrotik";
import { Olt } from "./pages/Olt";
import { Monitoring } from "./pages/Monitoring";
import { NetworkDiagram } from "./pages/NetworkDiagram";
import { Tickets } from "./pages/Tickets";
import { Inventory } from "./pages/Inventory";
import { Expenses } from "./pages/Expenses";
import { Employees } from "./pages/Employees";
import { Resellers } from "./pages/Resellers";
import { AiAssistant } from "./pages/AiAssistant";
import { Automation } from "./pages/Automation";
import { Leads } from "./pages/Leads";
import { RegulatoryNews } from "./pages/RegulatoryNews";
import { Ipam } from "./pages/Ipam";
import { ModulePage } from "./pages/ModulePage";
import { SyncConflicts } from "./pages/SyncConflicts";
import { initSync } from "./offline/syncEngine";
import { PortalShell } from "./portal/PortalShell";
import { PortalLogin } from "./portal/PortalLogin";
import { PortalHome } from "./portal/PortalHome";
import { PortalBills } from "./portal/PortalBills";
import { PortalSupport } from "./portal/PortalSupport";
import { PortalAccount } from "./portal/PortalAccount";
import "./theme.css";

initSync();

function RequirePortalAuth({ children }) {
  const token = localStorage.getItem("arq_portal_token");
  return token ? children : <Navigate to="/portal/login" replace />;
}

function RequireAuth({ children }) {
  const token = localStorage.getItem("arq_token");
  return token ? children : <Navigate to="/login" replace />;
}

export default function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/login" element={<Login />} />

        {/* ---- Customer self-service portal (separate auth guard) ---- */}
        <Route path="/portal/login" element={<I18nProvider><PortalLogin /></I18nProvider>} />
        <Route
          path="/portal"
          element={
            <RequirePortalAuth>
              <I18nProvider>
                <PortalShell />
              </I18nProvider>
            </RequirePortalAuth>
          }
        >
          <Route index element={<PortalHome />} />
          <Route path="bills" element={<PortalBills />} />
          <Route path="support" element={<PortalSupport />} />
          <Route path="account" element={<PortalAccount />} />
        </Route>
        <Route
          element={
            <RequireAuth>
              <I18nProvider>
                <CapabilitiesProvider>
                <AppShell />
              </CapabilitiesProvider>
              </I18nProvider>
            </RequireAuth>
          }
        >
          <Route path="/" element={<Dashboard />} />
          <Route path="/customers" element={<Customers />} />
          <Route path="/leads" element={<Leads />} />
          <Route path="/billing" element={<BillCollection />} />
          <Route path="/network/mikrotik" element={<Mikrotik />} />
          <Route path="/network/ipam" element={<Ipam />} />
          <Route path="/network/olt" element={<Olt />} />
          <Route path="/network/monitoring" element={<Monitoring />} />
                    <Route path="/network/diagram" element={<NetworkDiagram />} />
          <Route path="/tickets" element={<Tickets />} />
          <Route path="/field-jobs" element={<ModulePage moduleKey="field-jobs" />} />
          <Route path="/inventory" element={<Inventory />} />
          <Route path="/expenses" element={<Expenses />} />
          <Route path="/employees" element={<Employees />} />
          <Route path="/resellers" element={<Resellers />} />
          <Route path="/ai" element={<AiAssistant />} />
          <Route path="/automation" element={<Automation />} />
          <Route path="/news" element={<RegulatoryNews />} />
          <Route path="/sync" element={<SyncConflicts />} />
        </Route>
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </BrowserRouter>
  );
}
