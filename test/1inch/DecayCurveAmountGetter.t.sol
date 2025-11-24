// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {BaseTest} from './Base.t.sol';
import {console} from 'forge-std/console.sol';
import {IOrderMixin} from 'limit-order-protocol/contracts/interfaces/IOrderMixin.sol';
import {BitInvalidatorLib} from 'limit-order-protocol/contracts/libraries/BitInvalidatorLib.sol';
import {
  MakerTraits,
  MakerTraitsLib
} from 'limit-order-protocol/contracts/libraries/MakerTraitsLib.sol';
import {TakerTraits} from 'limit-order-protocol/contracts/libraries/TakerTraitsLib.sol';
import {DecayCurveAmountGetter} from 'src/1inch/DecayCurveAmountGetter.sol';

contract DecayCurveAmountGetterTest is BaseTest {
  using MakerTraitsLib for MakerTraits;

  /* Test corresponds to the Desmos curve visualization: https://www.desmos.com/calculator/klbg4dubcu */
  function testFuzz_DecayCurveAmountGetter(
    uint256 takingAmount,
    uint256 makingAmount, /* R0 */
    uint256 expiration, /* D */
    uint256 startTime, /* T */
    uint256 blockTimestamp, /* t */
    uint256 amplificationFactor, /* A */
    uint256 exponent /* E */
  ) public {
    vm.warp(0);
    takingAmount = bound(takingAmount, 1 ether, 100 ether);
    makingAmount = bound(makingAmount, 1 ether, 100 ether);
    expiration = bound(expiration, 100, 200);
    startTime = bound(startTime, 0, expiration / 2);
    blockTimestamp = bound(blockTimestamp, startTime, expiration - 1);
    amplificationFactor = bound(amplificationFactor, 1, 1e18);
    exponent = bound(exponent, 0.01e18, 4e18);
    vm.warp(blockTimestamp);
    console.log('R0 =', makingAmount);
    console.log('D =', expiration);
    console.log('T =', startTime);
    console.log('t =', blockTimestamp);
    console.log('A =', amplificationFactor);
    console.log('E =', exponent);
    _flags = [_HAS_EXTENSION_FLAG];

    bytes memory extraData = abi.encode(startTime, exponent, amplificationFactor);
    bytes memory extension = _buildExtension(extraData, '');
    IOrderMixin.Order memory order = _buildOrder(extension, takingAmount, makingAmount, expiration);
    (, bytes32 r, bytes32 vs) = _signOrder(order);
    TakerTraits takerTraits = _buildTakerTraits(extension.length);

    vm.prank(_taker);
    (uint256 makingAmountFilled, uint256 takingAmountFilled,) =
      _limitOrder.fillOrderArgs(order, r, vs, takingAmount, takerTraits, extension);

    uint256 makerBalanceAfter = _token1.balanceOf(_maker);
    uint256 takerBalanceAfter = _token0.balanceOf(_taker);
    assertTrue(makingAmountFilled <= makingAmount);
    assertEq(makerBalanceAfter, takingAmountFilled);
    assertEq(takerBalanceAfter, makingAmountFilled);
  }

  function testFuzz_DecayCurveAmountGetter_MultipleFills(
    uint256 takingAmount,
    uint256 makingAmount,
    uint256 expiration,
    uint256 startTime,
    uint256 endTime,
    uint256 amplificationFactor,
    uint256 exponent
  ) public {
    vm.warp(0);
    takingAmount = bound(takingAmount, 1_000_000, 100_000 ether);
    makingAmount = bound(makingAmount, 1_000_000, 100_000 ether);
    expiration = bound(expiration, block.timestamp, block.timestamp + 1 days);
    startTime = bound(startTime, block.timestamp, expiration / 2);
    amplificationFactor = bound(amplificationFactor, 1, 1e18);
    exponent = bound(exponent, 0.5e18, 3e18);
    _flags = [_HAS_EXTENSION_FLAG, _ALLOW_MULTIPLE_FILLS_FLAG];

    bytes memory extraData = abi.encode(startTime, exponent, amplificationFactor);
    bytes memory extension = _buildExtension(extraData, '');
    IOrderMixin.Order memory order = _buildOrder(extension, takingAmount, makingAmount, expiration);
    (, bytes32 r, bytes32 vs) = _signOrder(order);
    TakerTraits takerTraits = _buildTakerTraits(extension.length);

    uint256 requestedTakingAmount = bound(takingAmount, takingAmount / 5, takingAmount / 2);
    vm.prank(_taker);
    (uint256 makingAmountFilled, uint256 takingAmountFilled,) =
      _limitOrder.fillOrderArgs(order, r, vs, requestedTakingAmount, takerTraits, extension);

    uint256 makerBalanceAfter = _token1.balanceOf(_maker);
    uint256 takerBalanceAfter = _token0.balanceOf(_taker);
    assertEq(makerBalanceAfter, takingAmountFilled);
    assertEq(takerBalanceAfter, makingAmountFilled);

    vm.prank(_taker);
    (uint256 makingAmountFilled2, uint256 takingAmountFilled2,) = _limitOrder.fillOrderArgs(
      order, r, vs, takingAmount - requestedTakingAmount, takerTraits, extension
    );
  }

  function testFuzz_MakingAmount_NotChanged(
    uint256 takingAmount,
    uint256 makingAmount,
    uint256 expiration,
    uint256 amplificationFactor,
    uint256 exponent
  ) public {
    takingAmount = bound(takingAmount, 1_000_000, 100_000 ether);
    makingAmount = bound(makingAmount, 1_000_000, 100_000 ether);
    expiration = bound(expiration, block.timestamp, block.timestamp + 1 days);
    uint256 startTime = block.timestamp;
    amplificationFactor = bound(amplificationFactor, 1, 1e18);
    exponent = bound(exponent, 0, 3e18);
    _flags = [_HAS_EXTENSION_FLAG];

    bytes memory extraData = abi.encode(startTime, exponent, amplificationFactor);
    bytes memory extension = _buildExtension(extraData, '');
    IOrderMixin.Order memory order = _buildOrder(extension, takingAmount, makingAmount, expiration);
    (, bytes32 r, bytes32 vs) = _signOrder(order);
    TakerTraits takerTraits = _buildTakerTraits(extension.length);

    vm.prank(_taker);
    (uint256 makingAmountFilled, uint256 takingAmountFilled,) =
      _limitOrder.fillOrderArgs(order, r, vs, takingAmount, takerTraits, extension);

    uint256 makerBalanceAfter = _token1.balanceOf(_maker);
    uint256 takerBalanceAfter = _token0.balanceOf(_taker);
    assertEq(makingAmountFilled, makingAmount);
    assertEq(makerBalanceAfter, takingAmountFilled);
    assertEq(takerBalanceAfter, makingAmountFilled);
  }

  function testFuzz_MakingAmount_LessThanOriginal(
    uint256 takingAmount,
    uint256 makingAmount,
    uint256 expiration,
    uint256 amplificationFactor
  ) public {
    takingAmount = bound(takingAmount, 1_000_000, 100_000 ether);
    makingAmount = bound(makingAmount, 1_000_000, 100_000 ether);
    expiration = bound(expiration, block.timestamp + 1 days, block.timestamp + 2 days);
    uint256 startTime = block.timestamp;
    amplificationFactor = bound(amplificationFactor, 0.4e18, 0.9e18);
    uint256 exponent = 1;
    _flags = [_HAS_EXTENSION_FLAG];
    vm.warp((startTime + expiration) / 2);

    bytes memory extraData = abi.encode(startTime, exponent, amplificationFactor);
    bytes memory extension = _buildExtension(extraData, '');
    IOrderMixin.Order memory order = _buildOrder(extension, takingAmount, makingAmount, expiration);
    (, bytes32 r, bytes32 vs) = _signOrder(order);
    TakerTraits takerTraits = _buildTakerTraits(extension.length);

    vm.prank(_taker);
    (uint256 makingAmountFilled, uint256 takingAmountFilled,) =
      _limitOrder.fillOrderArgs(order, r, vs, takingAmount, takerTraits, extension);

    uint256 makerBalanceAfter = _token1.balanceOf(_maker);
    uint256 takerBalanceAfter = _token0.balanceOf(_taker);
    assertLt(makingAmountFilled, makingAmount);
    assertEq(makerBalanceAfter, takingAmountFilled);
    assertEq(takerBalanceAfter, makingAmountFilled);

    vm.prank(_taker);
    // order should be invalidated
    vm.expectRevert(abi.encodeWithSelector(BitInvalidatorLib.BitInvalidatedOrder.selector));
    _limitOrder.fillOrderArgs(order, r, vs, takingAmount, takerTraits, extension);
  }

  function testRevert_TakingAmount_NotSupported() public {
    _flags = [_HAS_EXTENSION_FLAG];
    bytes memory extraData = abi.encode(0, 0, 0, 0);
    bytes memory extension = _buildExtension('', extraData);

    IOrderMixin.Order memory order =
      _buildOrder(extension, 10_000, 10_000, block.timestamp + 1 days);
    (, bytes32 r, bytes32 vs) = _signOrder(order);
    TakerTraits takerTraits = _buildTakerTraits(extension.length);
    uint256 makeFlag = 1 << 255;
    assembly {
      takerTraits := or(takerTraits, makeFlag)
    }

    vm.prank(_taker);
    vm.expectRevert(
      abi.encodeWithSelector(DecayCurveAmountGetter.TakingAmountNotSupported.selector)
    );
    (uint256 makingAmountFilled, uint256 takingAmountFilled,) =
      _limitOrder.fillOrderArgs(order, r, vs, 10_000, takerTraits, extension);
  }

  function test_DecayCurveExactValue() public {
    vm.warp(0);
    uint256 takingAmount = 100;
    uint256 makingAmount = 1000;
    uint256 expiration = 1000;
    uint256 startTime = 400;
    uint256 amplificationFactor = 0.4e18;
    uint256 exponent = 1e18;
    _flags = [_HAS_EXTENSION_FLAG];
    vm.warp(800);

    bytes memory extraData = abi.encode(startTime, exponent, amplificationFactor);
    bytes memory extension = _buildExtension(extraData, '');
    IOrderMixin.Order memory order = _buildOrder(extension, takingAmount, makingAmount, expiration);
    (, bytes32 r, bytes32 vs) = _signOrder(order);
    TakerTraits takerTraits = _buildTakerTraits(extension.length);

    vm.prank(_taker);
    (uint256 makingAmountFilled, uint256 takingAmountFilled,) =
      _limitOrder.fillOrderArgs(order, r, vs, takingAmount, takerTraits, extension);

    assertEq(makingAmountFilled, 734);
    assertEq(takingAmountFilled, 100);
  }

  function test_DecayCurve_ExponentIntValue(
    uint256 exponent,
    uint256 takingAmount,
    uint256 makingAmount,
    uint256 expiration,
    uint256 amplificationFactor
  ) public {
    vm.warp(0);
    takingAmount = bound(takingAmount, 100, 100_000);
    makingAmount = bound(makingAmount, 1e6, 1000 ether);
    expiration = bound(expiration, 50, 100);
    amplificationFactor = bound(amplificationFactor, 0.1e6, 0.5e6);
    uint256 startTime = block.timestamp;
    exponent = bound(exponent, 1, 4);
    _flags = [_HAS_EXTENSION_FLAG];
    vm.warp(bound(amplificationFactor, startTime, expiration));

    bytes memory extraData = abi.encode(startTime, exponent * 1e18, amplificationFactor * 1e12);
    bytes memory extension = _buildExtension(extraData, '');
    IOrderMixin.Order memory order = _buildOrder(extension, takingAmount, makingAmount, expiration);
    (, bytes32 r, bytes32 vs) = _signOrder(order);
    TakerTraits takerTraits = _buildTakerTraits(extension.length);

    vm.prank(_taker);
    (uint256 makingAmountFilled, uint256 takingAmountFilled,) =
      _limitOrder.fillOrderArgs(order, r, vs, takingAmount, takerTraits, extension);

    uint256 confidence =
      (block.timestamp - startTime) * 1e6 / (order.makerTraits.getExpirationTime() - startTime);

    uint256 reductionPercent = amplificationFactor * (confidence ** exponent) / (1e6 ** exponent);
    uint256 reductionAmount = makingAmount * reductionPercent / 1e6;

    assertApproxEqRel(makingAmountFilled, makingAmount - reductionAmount, 1e13); // 0.001%;
  }
}
