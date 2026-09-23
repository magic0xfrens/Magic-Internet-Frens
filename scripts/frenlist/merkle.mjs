/**
 * The frenlist Merkle tree: one leaf per wallet, (wallet, allowance).
 *
 * Leaf = keccak256(bytes.concat(keccak256(abi.encode(wallet, allowance)))) —
 * the OpenZeppelin StandardMerkleTree encoding, rebuilt by
 * `MiFrensGenesis.mintDiscounted` from `msg.sender`. Pairs hash sorted (OZ
 * `MerkleProof`), so proofs carry no left/right flags.
 */
import { concat, encodeAbiParameters, keccak256 } from "viem";

export function leafHash(wallet, allowance) {
  return keccak256(keccak256(encodeAbiParameters([{ type: "address" }, { type: "uint256" }], [wallet, allowance])));
}

function hashPair(a, b) {
  return BigInt(a) < BigInt(b) ? keccak256(concat([a, b])) : keccak256(concat([b, a]));
}

/** `entries` = [{ wallet, allowance }]. Leaves are sorted, so input order never changes the root. */
export function buildTree(entries) {
  if (entries.length === 0) throw new Error("empty frenlist");
  const leaves = entries.map((e) => ({ ...e, leaf: leafHash(e.wallet, e.allowance) }));
  leaves.sort((x, y) => (BigInt(x.leaf) < BigInt(y.leaf) ? -1 : 1));

  const layers = [leaves.map((l) => l.leaf)];
  while (layers.at(-1).length > 1) {
    const layer = layers.at(-1);
    const next = [];
    // An odd node out is carried up unhashed; its proof skips that level.
    for (let i = 0; i < layer.length; i += 2) next.push(i + 1 < layer.length ? hashPair(layer[i], layer[i + 1]) : layer[i]);
    layers.push(next);
  }

  const proofOf = (index) => {
    const proof = [];
    for (let d = 0, idx = index; d < layers.length - 1; d++, idx >>= 1) {
      if ((idx ^ 1) < layers[d].length) proof.push(layers[d][idx ^ 1]);
    }
    return proof;
  };
  return { root: layers.at(-1)[0], items: leaves.map((l, i) => ({ ...l, proof: proofOf(i) })) };
}

/** Independent re-check, folding the proof the way OZ `MerkleProof.processProof` does. */
export function verifyProof(proof, root, leaf) {
  return proof.reduce((acc, p) => hashPair(acc, p), leaf) === root;
}
