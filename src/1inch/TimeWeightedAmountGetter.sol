// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {
  AmountGetterBase,
  IOrderMixin
} from 'limit-order-protocol/contracts/extensions/AmountGetterBase.sol';
import {
  MakerTraits,
  MakerTraitsLib
} from 'limit-order-protocol/contracts/libraries/MakerTraitsLib.sol';
import {Math} from 'openzeppelin-contracts/contracts/utils/math/Math.sol';

contract TimeWeightedAmountGetter is AmountGetterBase {
  using MakerTraitsLib for MakerTraits;
  error TakingAmountNotSupported();

  function _getMakingAmount(
    IOrderMixin.Order calldata order,
    bytes calldata,
    /* extension */
    bytes32,
    /* orderHash */
    address,
    /* taker */
    uint256,
    /* takingAmount */
    uint256 remainingMakingAmount,
    bytes calldata extraData
  ) internal view override returns (uint256) {
    (uint256 startTime, uint256 endTime, uint256 exponent, uint256 maxVarianceBps) =
      decodeConfidenceValue(extraData);
    uint256 expirationTime = order.makerTraits.getExpirationTime();

    if (exponent > 0 && block.timestamp > startTime) {
      uint256 deadline = endTime == 0 ? expirationTime : endTime;

      uint256 confidence =
        ((Math.min(block.timestamp, deadline) - startTime) * 1e6) / (deadline - startTime);
      uint256 amplifiedRatio = confidence ** exponent;
      uint256 baseAmplifier = 1e6 ** exponent;
      uint256 varianceMetric = (amplifiedRatio * maxVarianceBps * 10_000) / (baseAmplifier * 10_000);
      remainingMakingAmount =
        remainingMakingAmount * (10_000 - Math.min(varianceMetric, maxVarianceBps)) / 10_000;
    }

    return remainingMakingAmount;
  }

  function _getTakingAmount(
    IOrderMixin.Order calldata,
    bytes calldata,
    bytes32,
    address,
    uint256,
    uint256,
    bytes calldata
  ) internal view override returns (uint256) {
    revert TakingAmountNotSupported();
  }

  // @dev equivalent to abi.decode(extraData, (uint256, uint256, uint256, uint256))
  function decodeConfidenceValue(bytes calldata extraData)
    internal
    pure
    returns (uint256 startTime, uint256 endTime, uint256 exponent, uint256 maxVarianceBps)
  {
    assembly ('memory-safe') {
      startTime := calldataload(extraData.offset)
      endTime := calldataload(add(extraData.offset, 0x20))
      exponent := calldataload(add(extraData.offset, 0x40))
      maxVarianceBps := calldataload(add(extraData.offset, 0x60))
    }
  }
}
