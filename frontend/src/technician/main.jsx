import React from "react";
import ReactDOM from "react-dom/client";
import { TechnicianApp } from "./TechnicianApp";
import { I18nProvider } from "../i18n";
import { initSync } from "../offline/syncEngine";
import "../theme.css";

// Technicians are the heaviest offline users, so the sync engine starts
// immediately: any queued job updates, photos and signatures from the last
// shift begin draining as soon as the device sees a network.
initSync();

ReactDOM.createRoot(document.getElementById("tech-root")).render(
  <React.StrictMode>
    <I18nProvider>
      <TechnicianApp />
    </I18nProvider>
  </React.StrictMode>
);
