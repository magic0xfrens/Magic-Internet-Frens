import { useReducer, useEffect, useRef, useCallback } from "react";
import type { FrenClass } from "@/data/frens";
import { BODIES, FACES, GNOME_FACES, ELF_FACES, ITEMS } from "@/data/frens";
import {
  CLASS_SPECS,
  TOTAL_SUPPLY,
  BLOCKS_PER_EPOCH,
  MINTS_PER_BLOCK,
  calcFee,
  compositeBytes,
} from "@/data/visualizerConfig";

export interface MintedFrog {
  id: number;
  class: FrenClass;
  bodyFile: string;
  faceFile: string;
  itemFile: string;
  bodyLabel: string;
  faceLabel: string;
  itemLabel: string;
  bytes: number;
  fee: number;
  taxPct: number;
  governance: number;
  epoch: number;
  block: number;
  mintedAt: number;
}

interface SimState {
  frogs: MintedFrog[];
  epoch: number;
  block: number;
  classCounts: Record<FrenClass, number>;
  totalBytes: number;
  totalFees: number;
  totalGovernance: number;
  playing: boolean;
  speed: number;
}

type SimAction =
  | { type: "TICK" }
  | { type: "TOGGLE_PLAY" }
  | { type: "SET_SPEED"; speed: number }
  | { type: "RESET" };

function pick<T>(arr: T[]): T {
  return arr[Math.floor(Math.random() * arr.length)];
}

function pickClass(): FrenClass {
  const r = Math.random() * 100;
  let cum = 0;
  for (const spec of CLASS_SPECS) {
    cum += spec.supplyPct;
    if (r < cum) return spec.class;
  }
  return "Peasant";
}

function randInRange(min: number, max: number): number {
  return Math.floor(min + Math.random() * (max - min));
}

const INITIAL: SimState = {
  frogs: [],
  epoch: 1,
  block: 1,
  classCounts: { Wizard: 0, King: 0, Knight: 0, Gnome: 0, Elf: 0, Apprentice: 0, Peasant: 0 },
  totalBytes: 0,
  totalFees: 0,
  totalGovernance: 0,
  playing: true,
  speed: 1,
};

function reducer(state: SimState, action: SimAction): SimState {
  switch (action.type) {
    case "TOGGLE_PLAY":
      return { ...state, playing: !state.playing };

    case "SET_SPEED":
      return { ...state, speed: action.speed };

    case "RESET":
      return { ...INITIAL };

    case "TICK": {
      if (state.frogs.length >= TOTAL_SUPPLY) return { ...state, playing: false };

      const mintCount = randInRange(MINTS_PER_BLOCK[0], MINTS_PER_BLOCK[1] + 1);
      const newFrogs: MintedFrog[] = [];
      const newCounts = { ...state.classCounts };
      let addedBytes = 0;
      let addedFees = 0;
      let addedGov = 0;

      for (let i = 0; i < mintCount; i++) {
        if (state.frogs.length + newFrogs.length >= TOTAL_SUPPLY) break;

        const cls = pickClass();
        const spec = CLASS_SPECS.find((s) => s.class === cls)!;
        const body = pick(BODIES[cls]);
        const face = pick(cls === "Gnome" ? GNOME_FACES : cls === "Elf" ? ELF_FACES : FACES);
        const item = pick(ITEMS[cls]);
        const bytes = compositeBytes(body.file, face.file, item.file);
        const fee = calcFee(bytes);

        newCounts[cls]++;
        addedBytes += bytes;
        addedFees += fee;
        addedGov += spec.governance;

        newFrogs.push({
          id: state.frogs.length + newFrogs.length + 1,
          class: cls,
          bodyFile: body.file,
          faceFile: face.file,
          itemFile: item.file,
          bodyLabel: body.label,
          faceLabel: face.label,
          itemLabel: item.label,
          bytes,
          fee,
          taxPct: spec.taxPct,
          governance: spec.governance,
          epoch: state.epoch,
          block: state.block,
          mintedAt: Date.now(),
        });
      }

      const nextBlock = state.block >= BLOCKS_PER_EPOCH ? 1 : state.block + 1;
      const nextEpoch = state.block >= BLOCKS_PER_EPOCH ? state.epoch + 1 : state.epoch;

      return {
        ...state,
        frogs: [...state.frogs, ...newFrogs],
        epoch: nextEpoch,
        block: nextBlock,
        classCounts: newCounts,
        totalBytes: state.totalBytes + addedBytes,
        totalFees: state.totalFees + addedFees,
        totalGovernance: state.totalGovernance + addedGov,
      };
    }

    default:
      return state;
  }
}

export function useMintSimulation() {
  const [state, dispatch] = useReducer(reducer, INITIAL);
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

  useEffect(() => {
    if (intervalRef.current) clearInterval(intervalRef.current);

    if (state.playing && state.frogs.length < TOTAL_SUPPLY) {
      intervalRef.current = setInterval(
        () => dispatch({ type: "TICK" }),
        2000 / state.speed,
      );
    }

    return () => {
      if (intervalRef.current) clearInterval(intervalRef.current);
    };
  }, [state.playing, state.speed, state.frogs.length]);

  const togglePlay = useCallback(() => dispatch({ type: "TOGGLE_PLAY" }), []);
  const setSpeed = useCallback((s: number) => dispatch({ type: "SET_SPEED", speed: s }), []);
  const reset = useCallback(() => dispatch({ type: "RESET" }), []);

  return { ...state, togglePlay, setSpeed, reset };
}
