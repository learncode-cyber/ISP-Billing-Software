import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App";

// Register the service worker (app shell caching + offline fallback).
if ("serviceWorker" in navigator) {
  window.addEventListener("load", () => {
    navigator.serviceWorker.register("/sw.js").then((reg) => {
      // Safe migration: tell the user rather than swapping the app mid-use.
      reg.addEventListener("updatefound", () => {
        const nw = reg.installing;
        nw?.addEventListener("statechange", () => {
          if (nw.state === "installed" && navigator.serviceWorker.controller) {
            window.dispatchEvent(new CustomEvent("arq:update-available", { detail: reg }));
          }
        });
      });
    }).catch(() => { /* SW unavailable (e.g. non-HTTPS) — app still works online */ });

    // Background Sync asks the page to drain the outbox.
    navigator.serviceWorker.addEventListener("message", (e) => {
      if (e.data?.type === "SYNC_NOW") import("./offline/syncEngine").then((m) => m.sync());
    });
  });
}

ReactDOM.createRoot(document.getElementById("root")).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
