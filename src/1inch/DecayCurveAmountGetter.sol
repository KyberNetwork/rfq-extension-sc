// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {CalldataDecoder} from 'ks-common-sc/src/libraries/calldata/CalldataDecoder.sol';
import {
  AmountGetterBase,
  IOrderMixin
} from 'limit-order-protocol/contracts/extensions/AmountGetterBase.sol';
import {
  AmountCalculatorLib
} from 'limit-order-protocol/contracts/libraries/AmountCalculatorLib.sol';
import {
  MakerTraits,
  MakerTraitsLib
} from 'limit-order-protocol/contracts/libraries/MakerTraitsLib.sol';
import {FixedPointMathLib} from 'solady/src/utils/FixedPointMathLib.sol';

contract DecayCurveAmountGetter is AmountGetterBase {
  using MakerTraitsLib for MakerTraits;
  using FixedPointMathLib for int256;
  using CalldataDecoder for bytes;

  error TakingAmountNotSupported();
  error AmplificationFactorTooHigh();
  error TooMuchMakingAmount();
  error ExponentTooHigh();

  uint256 public constant WAD = 1e18;
  uint256 public constant MAX_EXPONENT = 4e18;

  /**
   * @notice Calculates the adjusted making amount based on time-weighted decay curve
   * @dev Implements a decay formula: R_new = R_0 - R_0 * (c^E) * A / 1e36
   *      where c = normalized time progress (0-1), E = exponent, A = Amplification factor
   * @dev The formula reduces maker amount as time progresses, creating a curve where:
   *      - Higher exponents create more aggressive decay near expiration
   *      - Reduction is capped at Amplification factor basis points
   */
  function _getMakingAmount(
    IOrderMixin.Order calldata order,
    bytes calldata,
    /* extension */
    bytes32,
    /* orderHash */
    address,
    /* taker */
    uint256 requestedTakingAmount,
    uint256 remainingMakingAmount,
    bytes calldata extraData
  ) internal view override returns (uint256) {
    (uint256 startTime, uint256 exponent, uint256 amplificationFactor) =
      (extraData.decodeUint256(0), extraData.decodeUint256(1), extraData.decodeUint256(2));

    uint256 makingAmount = AmountCalculatorLib.getMakingAmount(
      order.makingAmount, order.takingAmount, requestedTakingAmount
    );

    // Only apply decay if exponent > 0 and current time is past the start time
    if (exponent > 0 && block.timestamp > startTime) {
      require(amplificationFactor <= WAD, AmplificationFactorTooHigh());
      require(exponent <= MAX_EXPONENT, ExponentTooHigh());
      // Step 1: Calculate normalized time progress (0 to 1, scaled by 1e18 for precision)
      // Formula: confidence = (elapsed_time / total_time_window) * 1e18
      uint256 confidence =
        ((block.timestamp - startTime) * WAD) / (order.makerTraits.getExpirationTime() - startTime);
      uint256 reductionAmount;
      // Step 2: Calculate reduction amount
      // Formula: R0 * (c^E) * A / 1e36
      // gas savings for exponent is a multiple of 1e18
      if (exponent % WAD == 0) {
        reductionAmount = (makingAmount * amplificationFactor) / WAD;
        exponent /= WAD;
        for (uint256 i = 0; i < exponent; i++) {
          reductionAmount = (reductionAmount * confidence) / WAD;
        }
      } else {
        // Both amplificationFactor and powWad output are WAD, so divide by WAD^2 to rescale
        reductionAmount =
          (makingAmount
              * amplificationFactor
              * uint256(int256(confidence).powWad(int256(exponent)))) / (WAD ** 2);
      }
      makingAmount -= reductionAmount;
    }
    require(makingAmount <= remainingMakingAmount, TooMuchMakingAmount());
    return makingAmount;
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
