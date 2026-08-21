import React from "react";
import ReactDOM from "react-dom/client";
import { PortalApp } from "./PortalApp";
import { I18nProvider } from "../i18n";
import "../theme.css";

// The portal reuses the staff app's token store, but under a distinct
// localStorage key and a distinct auth guard on the server, so the two
// sessions can never be confused for one another.
if (localStorage.getItem("arq_portal_token")) {
  // hydrate the api client with the portal token
  const t = localStorage.getItem("arq_portal_token");
  localStorage.setItem("arq_token", t);
}

ReactDOM.createRoot(document.getElementById("portal-root")).render(
  <React.StrictMode>
    <I18nProvider>
      <PortalApp />
    </I18nProvider>
  </React.StrictMode>
);
