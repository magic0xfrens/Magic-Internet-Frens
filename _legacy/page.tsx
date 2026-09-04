"use client";

import {
  useExploreProfiles,
  useExplorePublications,
  PublicationTypes,
  PublicationSortCriteria,
  PublicationMainFocus,
  useReaction,
  useActiveProfile,
  ReactionType,
} from "@lens-protocol/react-web";

import { useLogin, usePrivy, useWallets } from "@privy-io/react-auth";
import Head from "next/head";
import { useRouter } from "next/router";
import { useState, useEffect } from "react";
import { isAndroid } from "react-device-detect";
import Login from "./Login";
import Referal from "./Referal";
import MainGame from "./MainGame";
import { ethers, Contract } from "ethers";
import InstallAppPrompt from "./InstallAppPrompt";
import referalAbi from "./Referal.json";
import miFrensAbi from "./miFren.json";
import * as dotenv from "dotenv";
import contractAddresses from "./Contracts.json";
export default function Home() {
  dotenv.config();
  const [view, setView] = useState("profiles");
  const [dashboardType, setDashboardType] = useState("dashboard");
  let { data: profiles, loading: loadingProfiles } = useExploreProfiles({
    limit: 50,
  }) as any;

  const { data: profile } = useActiveProfile();

  let { data: musicPubs, loading: loadingMusicPubs } = useExplorePublications({
    limit: 25,
    sortCriteria: PublicationSortCriteria.CuratedProfiles,
    publicationTypes: [PublicationTypes.Post],
    metadataFilter: {
      restrictPublicationMainFocusTo: [PublicationMainFocus.Audio],
    },
  }) as any;

  let { data: publications, loading: loadingPubs } = useExplorePublications({
    limit: 25,
    sortCriteria: PublicationSortCriteria.CuratedProfiles,
    publicationTypes: [PublicationTypes.Post],
    metadataFilter: {
      restrictPublicationMainFocusTo: [PublicationMainFocus.Image],
    },
  }) as any;

  profiles = profiles?.filter((p) => p.picture?.original?.url);

  publications = publications?.filter((p) => {
    if (p.metadata && p.metadata.media[0]) {
      if (p.metadata.media[0].original.mimeType.includes("image")) return true;
      return false;
    }
    return true;
  });

  function openPublication(publication) {
    window.open(`https://share.lens.xyz/p/${publication.id}`, "_blank");
  }
  const [isInstalled, setIsInstalled] = useState(false);
  const [installationPrompt, setInstallationPrompt] = useState<any>();

  useEffect(() => {
    // Helps you prompt your users to install your PWA
    // See https://web.dev/learn/pwa/installation-prompt/
    // iOS Safari does not have this event, so you will have
    // to prompt users to add the PWA via your own UI (e.g. a
    // pop-up modal)
    window.addEventListener("beforeinstallprompt", (e) => {
      e.preventDefault();
      setIsInstalled(false);
      setInstallationPrompt(e);
    });
  }, []);

  useEffect(() => {
    // Detect if the PWA is installed
    // https://web.dev/learn/pwa/detection/#detecting-the-transfer
    window.addEventListener("DOMContentLoaded", () => {
      if (window.matchMedia("(display-mode: standalone)").matches) {
        setIsInstalled(true);
      }
    });
  });

  const promptToInstall = async () => {
    if (!installationPrompt) return;
    installationPrompt.prompt();
    installationPrompt.userChoice.then((response: { outcome: string }) => {
      setIsInstalled(response.outcome === "accepted");
    });
  };

  const { ready, authenticated, user, logout } = usePrivy();

  useEffect(() => {
    // Detect if the PWA is installed
    // https://web.dev/learn/pwa/detection/#detecting-the-transfer
    window.addEventListener("DOMContentLoaded", () => {
      if (window.matchMedia("(display-mode: standalone)").matches) {
        setIsInstalled(true);
      }
    });
  });

  return (
    <main>
      <div style={{ width: "100vw" }}>
        {!isInstalled && <InstallAppPrompt />}
        {!user ? <Login /> : <MainGame />}
      </div>
    </main>
  );
}
