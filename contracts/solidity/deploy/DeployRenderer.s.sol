// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {TraitStorage} from "../render/TraitStorage.sol";
import {FrenRenderer} from "../render/FrenRenderer.sol";

interface IPegRenderer {
    function setRenderer(address) external;
}

/**
 * @title DeployRenderer
 * @notice Deploys the on-chain art stack and uploads the real compressed trait
 *         blobs produced by scripts/compress-traits.mjs.
 *
 *  Steps:
 *    1. Deploy TraitStorage + FrenRenderer.
 *    2. Store the raw RGB palette (compressed-traits/palette-rgb.bin).
 *    3. Batch-upload every trait blob listed in
 *       compressed-traits/upload-manifest.json (parallel keys[]/files[]).
 *    4. If PEG is set, wire the renderer into MagicFrensPeg.setRenderer().
 *    5. Optionally freeze() the store when FREEZE=true.
 *
 *  Env:
 *    PRIVATE_KEY   deployer key (required)
 *    PEG           MagicFrensPeg address to wire (optional, 0 = skip)
 *    FREEZE        "true" to permanently lock the trait set (optional)
 *    BATCH         blobs per storeTraits() tx (optional, default 12)
 *
 *  Run (from contracts/solidity):
 *    forge script deploy/DeployRenderer.s.sol \
 *      --rpc-url $ETH_RPC --broadcast -vvv
 */
contract DeployRenderer is Script {
    string constant ART_DIR = "../../compressed-traits/";

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address peg = vm.envOr("PEG", address(0));
        bool doFreeze = vm.envOr("FREEZE", false);
        uint256 batch = vm.envOr("BATCH", uint256(12));

        vm.startBroadcast(pk);

        TraitStorage store = new TraitStorage();
        FrenRenderer renderer = new FrenRenderer(store);
        console2.log("TraitStorage:", address(store));
        console2.log("FrenRenderer:", address(renderer));

        // --- Palette ---
        store.storePalette(vm.readFileBinary(string.concat(ART_DIR, "palette-rgb.bin")));
        console2.log("palette stored");

        // --- Trait blobs (parallel arrays from upload-manifest.json) ---
        string memory manifest = vm.readFile(string.concat(ART_DIR, "upload-manifest.json"));
        uint256[] memory keys = vm.parseJsonUintArray(manifest, ".keys");
        string[] memory files = vm.parseJsonStringArray(manifest, ".files");
        require(keys.length == files.length, "manifest length mismatch");
        console2.log("uploading trait blobs:", keys.length);

        for (uint256 i = 0; i < keys.length; i += batch) {
            uint256 end = i + batch;
            if (end > keys.length) end = keys.length;
            uint256 n = end - i;

            uint256[] memory bKeys = new uint256[](n);
            bytes[] memory bBlobs = new bytes[](n);
            for (uint256 j = 0; j < n; j++) {
                bKeys[j] = keys[i + j];
                bBlobs[j] = vm.readFileBinary(string.concat(ART_DIR, files[i + j]));
            }
            store.storeTraits(bKeys, bBlobs);
            console2.log("  batch stored up to index", end);
        }

        // --- Wire into Peg ---
        if (peg != address(0)) {
            IPegRenderer(peg).setRenderer(address(renderer));
            console2.log("renderer wired into peg:", peg);
        }

        // --- Freeze ---
        if (doFreeze) {
            store.freeze();
            console2.log("trait store FROZEN");
        }

        vm.stopBroadcast();
    }
}
