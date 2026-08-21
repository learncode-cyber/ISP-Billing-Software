// CapabilitiesContext.jsx
//
// Blueprint Section 37: navigation visibility derives from feature
// entitlement + permission, fetched ONCE from /api/v1/me/capabilities.
// No component ever hard-codes plan logic — they ask can() / hasFeature().
// This is the frontend half of the "subscription AND permission" rule;
// the backend enforces it for real, this just avoids showing dead UI.

import { createContext, useContext, useEffect, useState } from "react";
import { api } from "../lib/api";

const CapabilitiesContext = createContext(null);

export function CapabilitiesProvider({ children }) {
  const [caps, setCaps] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    api
      .get("/me/capabilities")
      .then((c) => {
        // The tenant id namespaces every IndexedDB record — set it before
        // any offline read/write happens.
        if (c?.tenant_id) localStorage.setItem("arq_tenant_id", c.tenant_id);
        setCaps(c);
      })
      .catch(() => setCaps({ features: {}, permissions: {} }))
      .finally(() => setLoading(false));
  }, []);

  const value = {
    loading,
    scope: caps?.scope,
    // hasFeature: is this feature on the tenant's plan (or a platform default)?
    hasFeature: (key) => Boolean(caps?.features?.[key]),
    // can: does the user's role grant this permission (any data scope)?
    can: (permKey) => Array.isArray(caps?.permissions?.[permKey]),
    // scopeFor: the widest data scope the user has for a permission
    scopeFor: (permKey) => {
      const scopes = caps?.permissions?.[permKey] || [];
      return ["ALL", "BRANCH", "ASSIGNED", "OWN"].find((s) => scopes.includes(s)) || null;
    },
  };

  return <CapabilitiesContext.Provider value={value}>{children}</CapabilitiesContext.Provider>;
}

export function useCapabilities() {
  const ctx = useContext(CapabilitiesContext);
  if (!ctx) throw new Error("useCapabilities must be used within CapabilitiesProvider");
  return ctx;
}
