import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { App } from "./app/App";
import "@/assets/styles/main.scss";

const root = document.getElementById("app");
if (!root) throw new Error("Root element #app not found");

createRoot(root).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
