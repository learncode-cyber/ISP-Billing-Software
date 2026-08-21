import React from "react";
import ReactDOM from "react-dom/client";
import { PlatformApp } from "./PlatformApp";
import "../theme.css";

// No I18nProvider here: the platform console is an internal AR Qudrix
// tool used by staff who work in English, and keeping it monolingual
// avoids translating operational jargon that has no settled Bengali form.
ReactDOM.createRoot(document.getElementById("platform-root")).render(
  <React.StrictMode>
    <PlatformApp />
  </React.StrictMode>
);
