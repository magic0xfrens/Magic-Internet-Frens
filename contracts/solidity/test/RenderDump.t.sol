// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {TraitStorage} from "../render/TraitStorage.sol";
import {FrenRenderer} from "../render/FrenRenderer.sol";

/// @dev Not an assertion suite: writes the renderer's real output to disk so the
///      on-chain art can be eyeballed against the source PNGs.
contract RenderDump is Test {
    TraitStorage store;
    FrenRenderer renderer;
    bool wrote = true;
    string constant DIR = "../../compressed-traits/";

    function setUp() public {
        store = new TraitStorage();
        renderer = new FrenRenderer(store);
        store.storePalette(vm.readFileBinary(string.concat(DIR, "palette-rgb.bin")));
    }

    function _try(uint8 lt, uint8 ci, uint8 li) internal returns (bool) {
        string memory p = string.concat(
            DIR, "trait-", vm.toString(lt), "-", vm.toString(ci), "-", vm.toString(li), ".bin"
        );
        try vm.readFileBinary(p) returns (bytes memory blob) {
            store.storeTrait(store.traitKey(lt, ci, li), blob);
            return true;
        } catch { return false; }
    }

    function _dump(uint8 ci, uint8 li) internal {
        // Writing is only permitted under the `render` profile. This is a
        // diagnostic that dumps art for eyeballing, not an assertion, so under
        // any other profile it should stay quiet rather than fail the suite.
        try vm.writeFile(
            string.concat("render-out/fren-c", vm.toString(ci), "-", vm.toString(li), ".svg"),
            renderer.renderSVG(ci, li, li, li)
        ) {} catch { wrote = false; }
    }

    function test_DumpFrens() public {
        // class 0..3, first few items of each — enough to judge fidelity.
        for (uint8 ci = 0; ci < 4; ci++) {
            for (uint8 li = 0; li < 3; li++) {
                if (!_try(0, ci, li)) continue;
                if (!_try(1, ci, li)) continue;
                if (!_try(2, ci, li)) continue;
                _dump(ci, li);
            }
        }
    }
}
