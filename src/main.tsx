import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { App } from "./app/App";
import { rewriteLegacyHashUrl } from "./app/legacyHashUrl";
import "@/assets/styles/main.scss";

// Must run before the router reads `window.location` for the first time.
rewriteLegacyHashUrl();

const root = document.getElementById("app");
if (!root) throw new Error("Root element #app not found");

createRoot(root).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
