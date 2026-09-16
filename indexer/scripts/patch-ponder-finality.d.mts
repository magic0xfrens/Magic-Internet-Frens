/** Reorg tolerance per chain, in BLOCKS, keyed by chain id. Derived from each
 *  chain's measured `latest - finalized` distance — see the .mjs for why this
 *  cannot live in ponder.config.ts. */
export declare const FINALITY_BLOCKS: Record<number, number>;
export declare function patchFinality(opts?: { quiet?: boolean }): string;
export declare function verifyFinality(opts?: { quiet?: boolean }): Promise<boolean>;
