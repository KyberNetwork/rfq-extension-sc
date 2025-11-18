// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {AmountGetterBase, IOrderMixin} from "limit-order-protocol/contracts/extensions/AmountGetterBase.sol";
import {MakerTraitsLib, MakerTraits} from "limit-order-protocol/contracts/libraries/MakerTraitsLib.sol";

contract KSAmountGetter is AmountGetterBase {
    using MakerTraitsLib for MakerTraits;

    function _getMakingAmount(
        IOrderMixin.Order calldata order,
        bytes calldata extension,
        bytes32 orderHash,
        address taker,
        uint256 takingAmount,
        uint256 remainingMakingAmount,
        bytes calldata extraData
    ) internal view override returns (uint256) {}

    function _getTakingAmount(
        IOrderMixin.Order calldata order,
        bytes calldata extension,
        bytes32 orderHash,
        address taker,
        uint256 makingAmount,
        uint256 remainingMakingAmount,
        bytes calldata extraData
    ) internal view override returns (uint256) {
        uint256 deadline = order.makerTraits.getExpirationTime();
    }

    // @dev equivalent to abi.decode(extraData, (uint256, uint256, uint256, uint256))
    function decodeConfidenceValue(bytes calldata extraData)
        internal
        pure
        returns (
            uint256 confidenceExtractedValueT,
            uint256 confidenceExtractedValueN,
            uint256 confidenceExtractedValueE,
            uint256 confidenceExtractedValueM
        )
    {
        assembly ("memory-safe") {
            confidenceExtractedValueT := calldataload(extraData.offset)
            confidenceExtractedValueN := calldataload(add(extraData.offset, 0x20))
            confidenceExtractedValueE := calldataload(add(extraData.offset, 0x40))
            confidenceExtractedValueM := calldataload(add(extraData.offset, 0x60))
        }
    }
}
