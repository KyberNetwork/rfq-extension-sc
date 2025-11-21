// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {BaseTest} from './Base.t.sol';
import {console} from 'forge-std/console.sol';
import {IOrderMixin} from 'limit-order-protocol/contracts/interfaces/IOrderMixin.sol';
import {BitInvalidatorLib} from 'limit-order-protocol/contracts/libraries/BitInvalidatorLib.sol';
import {TakerTraits} from 'limit-order-protocol/contracts/libraries/TakerTraitsLib.sol';
import {DecayCurveAmountGetter} from 'src/1inch/DecayCurveAmountGetter.sol';

contract DecayCurveAmountGetterTest is BaseTest {
  function testFuzz_WeightedAmountGetter(
    uint256 takingAmount,
    uint256 makingAmount,
    uint256 expiration,
    uint256 startTime,
    uint256 endTime,
    uint256 amplificationFactor,
    uint256 exponent
  ) public {
    takingAmount = bound(takingAmount, 1_000_000, 100_000 ether);
    makingAmount = bound(makingAmount, 1_000_000, 100_000 ether);
    expiration = bound(expiration, block.timestamp, block.timestamp + 1 days);
    startTime = bound(startTime, block.timestamp - 1000, expiration);
    endTime = bound(endTime, startTime, expiration);
    vm.assume(endTime > startTime);
    amplificationFactor = bound(amplificationFactor, 1, 9000);
    exponent = bound(exponent, 0, 3e18);
    _flags = [_HAS_EXTENSION_FLAG];

    bytes memory extraData = abi.encode(startTime, exponent, amplificationFactor);
    bytes memory extension = _buildExtension(extraData, '', '');
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

  function testFuzz_WeightedAmountGetter_MultipleFills(
    uint256 takingAmount,
    uint256 makingAmount,
    uint256 expiration,
    uint256 startTime,
    uint256 endTime,
    uint256 amplificationFactor,
    uint256 exponent
  ) public {
    takingAmount = bound(takingAmount, 1_000_000, 100_000 ether);
    makingAmount = bound(makingAmount, 1_000_000, 100_000 ether);
    expiration = bound(expiration, block.timestamp, block.timestamp + 1 days);
    startTime = bound(startTime, block.timestamp - 1000, expiration);
    endTime = bound(endTime, startTime, expiration);
    vm.assume(endTime > startTime);
    amplificationFactor = bound(amplificationFactor, 1, 9000);
    exponent = bound(exponent, 0, 3e18);
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
    uint256 endTime,
    uint256 amplificationFactor,
    uint256 exponent
  ) public {
    takingAmount = bound(takingAmount, 1_000_000, 100_000 ether);
    makingAmount = bound(makingAmount, 1_000_000, 100_000 ether);
    expiration = bound(expiration, block.timestamp, block.timestamp + 1 days);
    uint256 startTime = block.timestamp;
    endTime = bound(endTime, startTime, expiration);
    vm.assume(endTime > startTime);
    amplificationFactor = bound(amplificationFactor, 1, 9000);
    exponent = bound(exponent, 0, 3e18);
    _flags = [_HAS_EXTENSION_FLAG];

    bytes memory extraData = abi.encode(startTime, exponent, amplificationFactor);
    bytes memory extension = _buildExtension(extraData, '', '');
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
    amplificationFactor = bound(amplificationFactor, 4000, 9000);
    uint256 exponent = 1;
    _flags = [_HAS_EXTENSION_FLAG];
    vm.warp((startTime + expiration) / 2);

    bytes memory extraData = abi.encode(startTime, exponent, amplificationFactor);
    bytes memory extension = _buildExtension(extraData, '', '');
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
    bytes memory extension = _buildExtension('', extraData, '');

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
    uint256 makingAmount = 100;
    uint256 expiration = 100;
    uint256 startTime = 50;
    uint256 amplificationFactor = 4000;
    uint256 exponent = 1e18;
    _flags = [_HAS_EXTENSION_FLAG];
    vm.warp(80);

    bytes memory extraData = abi.encode(startTime, exponent, amplificationFactor);
    bytes memory extension = _buildExtension(extraData, '');
    IOrderMixin.Order memory order = _buildOrder(extension, takingAmount, makingAmount, expiration);
    (, bytes32 r, bytes32 vs) = _signOrder(order);
    TakerTraits takerTraits = _buildTakerTraits(extension.length);

    vm.prank(_taker);
    (uint256 makingAmountFilled, uint256 takingAmountFilled,) =
      _limitOrder.fillOrderArgs(order, r, vs, takingAmount, takerTraits, extension);

    assertEq(makingAmountFilled, 76);
    assertEq(takingAmountFilled, 100);
  }
}
