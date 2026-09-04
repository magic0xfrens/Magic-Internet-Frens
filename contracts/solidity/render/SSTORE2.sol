// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title SSTORE2
 * @notice Read/write immutable blobs to contract bytecode. ~200x cheaper to read
 *         than SLOAD-based storage and lets us persist large art blobs on-chain.
 *
 *         Data is deployed as the runtime code of a tiny contract, prefixed with a
 *         single STOP (0x00) byte so the code can never be executed as a function.
 *         Reads slice the deployed bytecode back out via EXTCODECOPY.
 *
 *         Minimal vendored implementation (Solmate/Solady-style). No external deps.
 */
library SSTORE2 {
    error WriteError();

    uint256 private constant DATA_OFFSET = 1; // skip the leading STOP byte

    /// @notice Store `data` as the bytecode of a freshly deployed contract.
    /// @return pointer Address of the deployed data contract.
    function write(bytes memory data) internal returns (address pointer) {
        // Runtime code = STOP (0x00) ++ data, so the payload can never execute.
        bytes memory runtimeCode = abi.encodePacked(hex"00", data);

        // 11-byte creation stub that returns (codesize - 11) bytes from offset 11:
        //   600B  PUSH1 11        (offset of runtime within creation code)
        //   59    MSIZE           -> 0
        //   81    DUP2
        //   38    CODESIZE
        //   03    SUB             -> runtime length
        //   80    DUP1
        //   92    SWAP3
        //   59    MSIZE           -> 0 (mem dest)
        //   39    CODECOPY
        //   F3    RETURN
        bytes memory creationCode = abi.encodePacked(
            hex"60_0B_59_81_38_03_80_92_59_39_F3",
            runtimeCode
        );

        assembly {
            pointer := create(0, add(creationCode, 0x20), mload(creationCode))
        }
        if (pointer == address(0)) revert WriteError();
    }

    /// @notice Read the full data blob back from a pointer.
    function read(address pointer) internal view returns (bytes memory) {
        uint256 size = pointer.code.length;
        if (size <= DATA_OFFSET) return "";
        uint256 dataSize = size - DATA_OFFSET;

        bytes memory data = new bytes(dataSize);
        assembly {
            extcodecopy(pointer, add(data, 0x20), DATA_OFFSET, dataSize)
        }
        return data;
    }
}
