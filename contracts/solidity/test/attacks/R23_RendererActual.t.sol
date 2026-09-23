// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
// Explicit import allows the existing real-blob suite to run under the
// cauldron dependency/compiler profile despite its path exclusion.
import {FrenRendererTest} from "../FrenRenderer.t.sol";
contract R23RendererActual is FrenRendererTest {}
