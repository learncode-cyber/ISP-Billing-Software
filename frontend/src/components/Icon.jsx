// Icon.jsx — minimal inline SVG icons (stroke-based, 1.6px) so the shell
// has zero icon-library dependency and stays fast on cheap office
// hardware. Only the icons referenced in navigation.js are included.

const PATHS = {
  grid: "M3 3h7v7H3zM14 3h7v7h-7zM14 14h7v7h-7zM3 14h7v7H3z",
  users: "M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM23 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75",
  target: "M12 12m-10 0a10 10 0 1 0 20 0 10 10 0 1 0-20 0M12 12m-6 0a6 6 0 1 0 12 0 6 6 0 1 0-12 0M12 12m-2 0a2 2 0 1 0 4 0 2 2 0 1 0-4 0",
  receipt: "M4 2v20l2-1 2 1 2-1 2 1 2-1 2 1 2-1 2 1V2l-2 1-2-1-2 1-2-1-2 1-2-1-2 1zM8 7h8M8 11h8M8 15h5",
  router: "M6 15h12M6 15a2 2 0 0 0-2 2v2a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-2a2 2 0 0 0-2-2M9 18h.01M13 18h4M12 3v6M8 6l4-3 4 3",
  server: "M4 4h16v6H4zM4 14h16v6H4zM8 7h.01M8 17h.01",
  activity: "M22 12h-4l-3 9L9 3l-3 9H2",
  share: "M18 8a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM6 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM18 22a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM8.6 13.5l6.8 4M15.4 6.5l-6.8 4",
  ticket: "M3 9a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2 2 2 0 0 0 0 6 2 2 0 0 1-2 2H5a2 2 0 0 1-2-2 2 2 0 0 0 0-6zM13 5v2M13 17v2M13 11v2",
  "map-pin": "M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0zM12 10m-3 0a3 3 0 1 0 6 0 3 3 0 1 0-6 0",
  box: "M21 8l-9-5-9 5v8l9 5 9-5V8zM3 8l9 5 9-5M12 13v8",
  "trending-down": "M23 18l-9.5-9.5-5 5L1 6M17 18h6v-6",
  "id-card": "M3 5h18v14H3zM7 9h4M7 13h10M7 17h6M16 9h1",
  network: "M9 5a3 3 0 1 0 6 0 3 3 0 0 0-6 0zM3 19a3 3 0 1 0 6 0 3 3 0 0 0-6 0zM15 19a3 3 0 1 0 6 0 3 3 0 0 0-6 0zM12 8v4M12 12l-6 4M12 12l6 4",
  sparkles: "M12 3l1.9 5.1L19 10l-5.1 1.9L12 17l-1.9-5.1L5 10l5.1-1.9zM19 15l.9 2.1L22 18l-2.1.9L19 21l-.9-2.1L16 18l2.1-.9z",
  zap: "M13 2L3 14h9l-1 8 10-12h-9z",
  newspaper: "M4 4h13v16H4zM17 8h3v10a2 2 0 0 1-2 2h-1M7 8h7M7 12h7M7 16h4",
  search: "M11 11m-8 0a8 8 0 1 0 16 0 8 8 0 1 0-16 0M21 21l-4.35-4.35",
};

export function Icon({ name, size = 18, color = "currentColor" }) {
  const d = PATHS[name] || PATHS.grid;
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none"
      stroke={color} strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"
      style={{ flexShrink: 0 }}>
      {d.split("M").filter(Boolean).map((seg, i) => <path key={i} d={"M" + seg} />)}
    </svg>
  );
}
