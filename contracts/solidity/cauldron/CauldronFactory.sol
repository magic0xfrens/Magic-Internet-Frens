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
    error NotOwner();

    /// @notice Who may point new collections at a badge renderer. Set to the
    ///         deployer at construction and handed to the governance timelock.
    address public owner = msg.sender;

    /// @notice On-chain Liquidatoor badge renderer applied to every collection
    ///         this factory deploys (address(0) = keep the hosted URI base).
    ///
    ///  Held HERE rather than on the hook or the registry for two reasons: every
    ///  iteration deploys a fresh collection, so a renderer set only at launch
    ///  would leave all later brews on the hosted path; and both of those
    ///  contracts sit against the EIP-170 ceiling while this one has room. The
    ///  factory is also the collection's deployer, which is the only address
    ///  permitted to set it.
    address public liquidatorRenderer;

    event LiquidatorRendererSet(address renderer);

    function setLiquidatorRenderer(address r) external {
        if (msg.sender != owner) revert NotOwner();
        liquidatorRenderer = r;
        emit LiquidatorRendererSet(r);
    }

    function transferOwnership(address to) external {
        if (msg.sender != owner) revert NotOwner();
        owner = to;
    }

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
        // Badge metadata from the chain rather than a metadata server. This
        // factory is the collection's deployer, so it is the only address
        // allowed to set it, and this is the only moment it holds that right.
        if (liquidatorRenderer != address(0)) {
            col.setLiquidatorRenderer(liquidatorRenderer);
        }
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
