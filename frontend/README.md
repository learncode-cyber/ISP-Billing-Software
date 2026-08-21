# AR Qudrix ISP OS — Frontend (Admin Console)

React + Vite admin console for the ARQ ISP OS platform. Consumes the
`/api/v1` surface. Installable/PWA-ready. An operations tool — dense,
fast, status-colour-coded — not a marketing site.

## The signature: capabilities-driven navigation

The sidebar renders each module link only when
`hasFeature(feature) && can(permission)`, both resolved from a single
`GET /api/v1/me/capabilities` call (see `context/CapabilitiesContext.jsx`
and `lib/navigation.js`). A Starter-plan tenant never sees OLT/Reseller/
AI; a Billing Operator never sees HR. No component hard-codes plan logic
(Blueprint Section 37). The backend still enforces every rule for real —
this just avoids showing dead UI.

## Run

```bash
npm install
VITE_API_TARGET=http://localhost:8000 npm run dev   # proxies /api to Laravel
npm run build                                        # production static build
```

## Structure

```
src/
├── lib/
│   ├── api.js              # fetch wrapper; handles 402 (plan) vs 403 (permission)
│   └── navigation.js       # module tree annotated with feature + permission gates
├── context/
│   └── CapabilitiesContext.jsx  # single source of truth for nav visibility
├── layouts/AppShell.jsx    # capabilities-driven sidebar + top bar
├── components/
│   ├── Icon.jsx            # dependency-free inline SVG icons
│   └── primitives.jsx      # StatCard, StatusPill, DataTable, PageHeader, PlanRequired
├── pages/
│   ├── Dashboard.jsx       # verified cards (Total/Active/Inactive/Free/Collected)
│   ├── Customers.jsx       # verified filter bar + table + pagination
│   ├── BillCollection.jsx  # verified 4 tabs + Pay modal
│   ├── Mikrotik.jsx        # verified Online/Offline/Due-disconnect/Unmatched
│   ├── RegulatoryNews.jsx  # BTRC feed (free on every plan)
│   ├── ModulePage.jsx      # faithful scaffold for remaining modules
│   └── Login.jsx
└── App.jsx                 # routes
```

## Design tokens (`theme.css`)

Functional palette — colour carries meaning: `--ok` (online/paid/active),
`--danger` (due/offline/discontinue), `--warn` (partial/pending), `--info`
(free/trial). Tabular numbers so money and counts align in tables.
Accessibility floor: visible keyboard focus, reduced-motion respected.

## Fully data-bound vs scaffolded

Dashboard, Customers, Bill Collection, and MikroTik are wired to real
endpoints (or the exact verified shape where the list endpoint lands
next). The remaining modules render their real headers + intended data
views via `ModulePage`, and each gets fleshed out the same way in turn.
