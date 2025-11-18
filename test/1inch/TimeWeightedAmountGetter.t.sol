// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {BaseTest} from './Base.t.sol';
import {console} from 'forge-std/console.sol';
import {IOrderMixin} from 'limit-order-protocol/contracts/interfaces/IOrderMixin.sol';
import {BitInvalidatorLib} from 'limit-order-protocol/contracts/libraries/BitInvalidatorLib.sol';
import {TakerTraits} from 'limit-order-protocol/contracts/libraries/TakerTraitsLib.sol';
import {TimeWeightedAmountGetter} from 'src/1inch/TimeWeightedAmountGetter.sol';

contract TimeWeightedAmountGetterTest is BaseTest {
  function testFuzz_WeightedAmountGetter(
    uint256 takingAmount,
    uint256 makingAmount,
    uint256 expiration,
    uint256 startTime,
    uint256 endTime,
    uint256 maxVarianceBps,
    uint256 exponent
  ) public {
    takingAmount = bound(takingAmount, 1_000_000, 100_000 ether);
    makingAmount = bound(makingAmount, 1_000_000, 100_000 ether);
    expiration = bound(expiration, block.timestamp, block.timestamp + 1 days);
    startTime = bound(startTime, block.timestamp - 1000, expiration);
    endTime = bound(endTime, startTime, expiration);
    vm.assume(endTime > startTime);
    maxVarianceBps = bound(maxVarianceBps, 1, 9000);
    exponent = bound(exponent, 1, 10);
    _flags = [_HAS_EXTENSION_FLAG];

    bytes memory extraData = abi.encode(startTime, endTime, exponent, maxVarianceBps);
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

  function testFuzz_MakingAmount_NotChanged(
    uint256 takingAmount,
    uint256 makingAmount,
    uint256 expiration,
    uint256 endTime,
    uint256 maxVarianceBps,
    uint256 exponent
  ) public {
    takingAmount = bound(takingAmount, 1_000_000, 100_000 ether);
    makingAmount = bound(makingAmount, 1_000_000, 100_000 ether);
    expiration = bound(expiration, block.timestamp, block.timestamp + 1 days);
    uint256 startTime = block.timestamp;
    endTime = bound(endTime, startTime, expiration);
    vm.assume(endTime > startTime);
    maxVarianceBps = bound(maxVarianceBps, 1, 9000);
    exponent = bound(exponent, 1, 10);
    _flags = [_HAS_EXTENSION_FLAG];

    bytes memory extraData = abi.encode(startTime, endTime, exponent, maxVarianceBps);
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
    uint256 maxVarianceBps
  ) public {
    takingAmount = bound(takingAmount, 1_000_000, 100_000 ether);
    makingAmount = bound(makingAmount, 1_000_000, 100_000 ether);
    expiration = bound(expiration, block.timestamp + 1 days, block.timestamp + 2 days);
    uint256 startTime = block.timestamp;
    maxVarianceBps = bound(maxVarianceBps, 4000, 9000);
    uint256 exponent = 1;
    _flags = [_HAS_EXTENSION_FLAG];
    vm.warp((startTime + expiration) / 2);

    bytes memory extraData = abi.encode(startTime, 0, exponent, maxVarianceBps);
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
      abi.encodeWithSelector(TimeWeightedAmountGetter.TakingAmountNotSupported.selector)
    );
    (uint256 makingAmountFilled, uint256 takingAmountFilled,) =
      _limitOrder.fillOrderArgs(order, r, vs, 10_000, takerTraits, extension);
  }
}
