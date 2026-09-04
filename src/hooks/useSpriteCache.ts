import { useState, useEffect, useRef, useCallback } from "react";
import { BODIES, FACES, GNOME_FACES, ELF_FACES, ITEMS, type FrenClass, CLASS_ORDER } from "@/data/frens";

const SPRITE_SIZE = 120;

/** Collects every unique SVG filename from the trait catalogue. */
function getAllSvgFiles(): string[] {
  const set = new Set<string>();
  for (const cls of CLASS_ORDER) {
    for (const b of BODIES[cls]) set.add(b.file);
    for (const i of ITEMS[cls]) set.add(i.file);
  }
  for (const f of FACES) set.add(f.file);
  for (const f of GNOME_FACES) set.add(f.file);
  for (const f of ELF_FACES) set.add(f.file);
  return Array.from(set);
}

export interface SpriteCache {
  ready: boolean;
  progress: number;
  getComposite: (bodyFile: string, faceFile: string, itemFile: string) => HTMLCanvasElement | null;
}

export function useSpriteCache(): SpriteCache {
  const images = useRef<Map<string, HTMLImageElement>>(new Map());
  const compositeCache = useRef<Map<string, HTMLCanvasElement>>(new Map());
  const [progress, setProgress] = useState(0);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    let cancelled = false;
    const files = getAllSvgFiles();
    let loaded = 0;

    const promises = files.map(
      (file) =>
        new Promise<void>((resolve) => {
          const img = new Image();
          img.onload = () => {
            if (!cancelled) {
              images.current.set(file, img);
              loaded++;
              setProgress(Math.round((loaded / files.length) * 100));
            }
            resolve();
          };
          img.onerror = () => {
            loaded++;
            if (!cancelled) setProgress(Math.round((loaded / files.length) * 100));
            resolve();
          };
          img.src = `/frens/${file}`;
        }),
    );

    Promise.all(promises).then(() => {
      if (!cancelled) setReady(true);
    });

    return () => {
      cancelled = true;
    };
  }, []);

  const getComposite = useCallback(
    (bodyFile: string, faceFile: string, itemFile: string): HTMLCanvasElement | null => {
      const key = `${bodyFile}|${faceFile}|${itemFile}`;
      const cached = compositeCache.current.get(key);
      if (cached) return cached;

      const bodyImg = images.current.get(bodyFile);
      const faceImg = images.current.get(faceFile);
      const itemImg = images.current.get(itemFile);
      if (!bodyImg) return null;

      const canvas = document.createElement("canvas");
      canvas.width = SPRITE_SIZE;
      canvas.height = SPRITE_SIZE;
      const ctx = canvas.getContext("2d")!;
      ctx.imageSmoothingEnabled = false;

      /* Layer order: face (bottom) → body (middle) → item (top) */
      if (faceImg) ctx.drawImage(faceImg, 0, 0, SPRITE_SIZE, SPRITE_SIZE);
      ctx.drawImage(bodyImg, 0, 0, SPRITE_SIZE, SPRITE_SIZE);
      if (itemImg) ctx.drawImage(itemImg, 0, 0, SPRITE_SIZE, SPRITE_SIZE);

      compositeCache.current.set(key, canvas);
      return canvas;
    },
    [],
  );

  return { ready, progress, getComposite };
}
