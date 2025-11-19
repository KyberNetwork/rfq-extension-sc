// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {CalldataDecoder} from 'ks-common-sc/src/libraries/calldata/CalldataDecoder.sol';
import {
  AmountGetterBase,
  IOrderMixin
} from 'limit-order-protocol/contracts/extensions/AmountGetterBase.sol';
import {
  MakerTraits,
  MakerTraitsLib
} from 'limit-order-protocol/contracts/libraries/MakerTraitsLib.sol';
import {Math} from 'openzeppelin-contracts/contracts/utils/math/Math.sol';

contract DecayCurveAmountGetter is AmountGetterBase {
  using MakerTraitsLib for MakerTraits;
  using CalldataDecoder for bytes;
  error TakingAmountNotSupported();

  /**
   * @notice Calculates the adjusted making amount based on time-weighted decay curve
   * @dev Implements a decay formula: R_new = R_0 * (1 - (c^E) * M / 10^4)
   *      where c = normalized time progress (0-1), E = exponent, M = maxReductionBps
   * @dev The formula reduces maker amount as time progresses, creating a curve where:
   *      - Higher exponents create more aggressive decay near expiration
   *      - Reduction is capped at maxReductionBps basis points
   */
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
    (uint256 startTime, uint256 exponent, uint256 maxReductionBps) =
      (extraData.decodeUint256(0), extraData.decodeUint256(1), extraData.decodeUint256(2));
    uint256 expirationTime = order.makerTraits.getExpirationTime();

    // Only apply decay if exponent > 0 and current time is past the start time
    if (exponent > 0 && block.timestamp > startTime) {
      // Step 1: Calculate normalized time progress (0 to 1, scaled by 1e6 for precision)
      // Formula: confidence = (elapsed_time / total_time_window) * 1e6
      uint256 confidence = ((Math.min(block.timestamp, expirationTime) - startTime) * 1e6)
        / (expirationTime - startTime);

      // Step 2: Apply exponent to create non-linear curve
      // exponentiatedProgress = confidence^exponent (still scaled by 1e6)
      uint256 exponentiatedProgress = confidence ** exponent;
      uint256 normalizationFactor = 1e6 ** exponent;

      // Step 3: Calculate reduction percentage in basis points
      uint256 reductionBps = (exponentiatedProgress * maxReductionBps) / normalizationFactor;

      // Step 4: Apply the reduction to remaining making amount
      remainingMakingAmount =
        (remainingMakingAmount * (10_000 - Math.min(reductionBps, maxReductionBps))) / 10_000;
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
}
