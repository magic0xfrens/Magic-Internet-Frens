"use client";

import { PrivyProvider } from "@privy-io/react-auth";

export default function Provider({ children }) {
  return (
    <PrivyProvider
      appId={process.env.NEXT_PUBLIC_PRIVY_APP_ID || ""}
      config={{
        loginMethods: ["email", "wallet", "twitter", "google"],
        appearance: {
          theme: "dark",
          accentColor: "#676FFF",
          logo: "https://pbs.twimg.com/profile_images/1726545828532142080/YZVEWZl2_400x400.jpg",
        },
        embeddedWallets: {
          createOnLogin: "all-users",
          noPromptOnSignature: false,
        },
      }}
    >
      {children}
    </PrivyProvider>
  );
}
