// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {CauldronCollection} from "./CauldronCollection.sol";
import {CauldronVault} from "./CauldronVault.sol";
import {RoyaltyRouter} from "./RoyaltyRouter.sol";
import {MetadataMode} from "./ICauldron.sol";

/**
 * @title CauldronFactory
 * @notice Deploys a brew's NFT collection + floor vault and wires them. Kept
 *         separate from CauldronRegistry so the (large) collection/vault
 *         creation bytecode lives here, keeping the registry under the 24KB
 *         EIP-170 limit.
 */
contract CauldronFactory {
    struct Config {
        string name;
        string symbol;
        address hook;        // the volume hook = the collection minter
        address registry;    // may close the vault on relaunch
        uint256 maxSupply;
        MetadataMode mode;
        string baseURI;
        address renderer;
        address royaltyReceiver; // EIP-2981 receiver (the genesis dividend)
        uint96 royaltyBps;       // secondary-sale royalty (bps)
    }

    /// @notice Deploy collection + vault, wire the vault into the collection.
    /// @return collection The NFT collection (minter = hook).
    /// @return vault The floor vault (registry may close it).
    function deployBrew(Config calldata c)
        external
        returns (address collection, address vault)
    {
        // `c.registry` is passed EXPLICITLY as the collection's controller (audit
        // H-01). Previously the collection inferred it from `msg.sender`, which is
        // THIS factory — leaving `custodyTransfer` (the legacy-floor recycle) and
        // every governed setter permanently unreachable.
        CauldronCollection col = new CauldronCollection(
            c.name, c.symbol, c.hook, c.registry, c.maxSupply, c.mode, c.baseURI, c.renderer,
            c.royaltyReceiver, c.royaltyBps
        );
        CauldronVault v = new CauldronVault(address(col), c.registry, 0); // fresh brew: no offset
        col.setVault(address(v)); // this factory is the collection's deployer
        // UNIFIED FLOOR: route this VOLUME collection's secondary royalties to a
        // RoyaltyRouter → the hook's buyback buffer, so they MARKET-BUY the live
        // token and back this collection's own per-gen TOKEN floor (not inert ETH in
        // the vault). Genesis (MiFrensGenesis) royalties still go to the dividend.
        RoyaltyRouter router = new RoyaltyRouter(c.hook);
        col.setRoyalty(address(router), c.royaltyBps);
        return (address(col), address(v));
    }

    /// @notice Deploy a fresh floor vault for an EXISTING collection. Used when
    ///         iteration #2 continues the genesis MiFrens collection: the
    ///         collection already exists, so only a new per-iteration vault is
    ///         deployed here. The registry wires it in via the collection's
    ///         own `setVault`.
    /// @param collection The existing collection the vault backs.
    /// @param registry   The registry that may close the vault on relaunch.
    function deployVault(address collection, address registry, uint256 floorOffset)
        external
        returns (address vault)
    {
        return address(new CauldronVault(collection, registry, floorOffset));
    }
}
