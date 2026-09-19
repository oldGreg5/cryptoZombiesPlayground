// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract MockKittyContract {
    function getKitty(uint256 _id)
        external
        pure
        returns (
            bool isGestating,
            bool isReady,
            uint256 cooldownIndex,
            uint256 nextActionAt,
            uint256 siringWithId,
            uint256 birthTime,
            uint256 matronId,
            uint256 sireId,
            uint256 generation,
            uint256 genes
        )
    {
        isGestating = false;
        isReady = true;
        genes = _id;
        // cooldownIndex, nextActionAt, siringWithId, birthTime, matronId, sireId
        // default to 0 automatically — no need to assign them
    }
}
