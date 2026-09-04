import { lazy, Suspense } from "react";
import { Routes, Route, Navigate } from "react-router-dom";

const HomePreview = lazy(() => import("@/components/preview/HomePreview"));
const MyWizards = lazy(() => import("@/components/wizards/MyWizards"));
const Token = lazy(() => import("@/components/token/Token"));
const Cauldrons = lazy(() => import("@/components/cauldron/TheCauldron"));
const XCallback = lazy(() => import("@/components/x-callback/XCallback"));
const LiquidatoorBadgeLab = lazy(() => import("@/components/preview/LiquidatoorBadgeLab"));
const Docs = lazy(() => import("@/components/docs/Docs"));

function PageLoader() {
  return (
    <div className="page-loader">
      <div className="loader-spinner" />
    </div>
  );
}

export function AppRoutes() {
  return (
    <Suspense fallback={<PageLoader />}>
      <Routes>
        <Route path="/" element={<HomePreview />} />
        <Route path="/mint" element={<Navigate to="/" replace />} />
        <Route path="/legacy" element={<Navigate to="/" replace />} />
        <Route path="/marketplace" element={<Navigate to="/" replace />} />
        <Route path="/mi-frens" element={<MyWizards />} />
        <Route path="/token" element={<Token />} />
        <Route path="/cauldrons" element={<Cauldrons />} />
        <Route path="/docs" element={<Docs />} />
        <Route path="/x-callback" element={<XCallback />} />
        <Route path="/badge-lab" element={<LiquidatoorBadgeLab />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </Suspense>
  );
}
