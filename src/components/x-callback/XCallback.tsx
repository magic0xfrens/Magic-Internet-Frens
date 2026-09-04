import { useEffect, useRef } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import { useXAuth } from "@/hooks/useXAuth";

export default function XCallback() {
  const [params] = useSearchParams();
  const { handleCallback, error } = useXAuth();
  const navigate = useNavigate();
  const ran = useRef(false);

  useEffect(() => {
    if (ran.current) return;
    ran.current = true;

    const code = params.get("code");
    const state = params.get("state");

    if (!code || !state) {
      navigate("/", { replace: true });
      return;
    }

    handleCallback(code, state).then(() => {
      navigate("/", { replace: true });
    });
  }, []);

  return (
    <div style={{ display: "flex", alignItems: "center", justifyContent: "center", minHeight: "60vh" }}>
      <div style={{ textAlign: "center" }}>
        {error ? (
          <p style={{ color: "#ff4d6d", fontFamily: '"DM Sans", sans-serif', fontSize: 13 }}>{error}</p>
        ) : (
          <p style={{ color: "#8A7BAA", fontFamily: '"DM Sans", sans-serif', fontSize: 13 }}>
            Connecting to X...
          </p>
        )}
      </div>
    </div>
  );
}
