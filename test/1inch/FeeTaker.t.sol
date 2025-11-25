// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import './Base.t.sol';
import {console} from 'forge-std/console.sol';
import {IOrderMixin} from 'limit-order-protocol/contracts/interfaces/IOrderMixin.sol';
import {BitInvalidatorLib} from 'limit-order-protocol/contracts/libraries/BitInvalidatorLib.sol';
import {TakerTraits} from 'limit-order-protocol/contracts/libraries/TakerTraitsLib.sol';
import {IFeeTaker} from 'src/1inch/interfaces/IFeeTaker.sol';

contract FeeTakerTest is BaseTest {
  function testFuzz_feeTaker(
    uint256 takingAmount,
    uint256 makingAmount,
    uint256 expiration,
    uint256 expectedAmount
  ) public {
    takingAmount = bound(takingAmount, 1_000_000, 100_000 ether);
    makingAmount = bound(makingAmount, 1_000_000, 100_000 ether);
    expiration = bound(expiration, block.timestamp, block.timestamp + 1 days);
    expectedAmount = bound(expectedAmount, 1, takingAmount - 1);

    IFeeTaker.Distribution memory distribution =
      IFeeTaker.Distribution({expectedAmount: expectedAmount, unwrapWeth: false});

    _flags = [_HAS_EXTENSION_FLAG, _POST_INTERACTION_CALL_FLAG];

    bytes memory extraData = abi.encode(distribution);
    bytes memory extension = _buildExtension('', '', extraData);
    IOrderMixin.Order memory order = _buildOrder(extension, takingAmount, makingAmount, expiration);
    order.receiver = Address.wrap(uint256(uint160(address(_feeTaker))));

    (, bytes32 r, bytes32 vs) = _signOrder(order);
    TakerTraits takerTraits = _buildTakerTraits(extension.length);

    vm.recordLogs();

    vm.prank(_taker);
    (uint256 makingAmountFilled, uint256 takingAmountFilled,) =
      _limitOrder.fillOrderArgs(order, r, vs, takingAmount, takerTraits, extension);

    assertEq(_token1.balanceOf(_maker), distribution.expectedAmount);
    assertEq(_token0.balanceOf(_taker), makingAmountFilled);
    assertEq(
      _token1.balanceOf(address(_feeTaker)), takingAmountFilled - distribution.expectedAmount
    );

    {
      Vm.Log[] memory logs = vm.getRecordedLogs();
      for (uint256 j = 0; j < logs.length; j++) {
        if (logs[j].topics[0] == IFeeTaker.TakingAmountTransferred.selector) {
          assertEq(address(uint160(uint256(logs[j].topics[2]))), address(_token1));
          assertEq(address(uint160(uint256(logs[j].topics[3]))), _maker);
          assertEq(abi.decode(logs[j].data, (uint256)), distribution.expectedAmount);
        }
      }
    }
  }

  function testFuzz_feeTaker_partialFill(
    uint256 takingAmount,
    uint256 makingAmount,
    uint256 expiration,
    uint256 expectedAmount,
    uint256 actualFillAmount
  ) public {
    takingAmount = bound(takingAmount, 1_000_000, 100_000 ether);
    makingAmount = bound(makingAmount, 1_000_000, 100_000 ether);
    expiration = bound(expiration, block.timestamp, block.timestamp + 1 days);
    expectedAmount = bound(expectedAmount, 1, takingAmount - 1);

    IFeeTaker.Distribution memory distribution =
      IFeeTaker.Distribution({expectedAmount: expectedAmount, unwrapWeth: false});

    _flags = [_HAS_EXTENSION_FLAG, _POST_INTERACTION_CALL_FLAG];

    bytes memory extraData = abi.encode(distribution);
    bytes memory extension = _buildExtension('', '', extraData);
    IOrderMixin.Order memory order = _buildOrder(extension, takingAmount, makingAmount, expiration);
    order.receiver = Address.wrap(uint256(uint160(address(_feeTaker))));

    (, bytes32 r, bytes32 vs) = _signOrder(order);
    TakerTraits takerTraits = _buildTakerTraits(extension.length);

    vm.recordLogs();

    actualFillAmount = bound(actualFillAmount, takingAmount / makingAmount + 1, takingAmount);

    vm.prank(_taker);
    (uint256 makingAmountFilled, uint256 takingAmountFilled,) =
      _limitOrder.fillOrderArgs(order, r, vs, actualFillAmount, takerTraits, extension);

    assertEq(
      _token1.balanceOf(_maker),
      takingAmountFilled < expectedAmount ? takingAmountFilled : expectedAmount
    );
    assertEq(_token0.balanceOf(_taker), makingAmountFilled);
    assertEq(
      _token1.balanceOf(address(_feeTaker)),
      takingAmountFilled > expectedAmount ? takingAmountFilled - expectedAmount : 0
    );

    {
      Vm.Log[] memory logs = vm.getRecordedLogs();
      for (uint256 j = 0; j < logs.length; j++) {
        if (logs[j].topics[0] == IFeeTaker.TakingAmountTransferred.selector) {
          assertEq(address(uint160(uint256(logs[j].topics[2]))), address(_token1));
          assertEq(address(uint160(uint256(logs[j].topics[3]))), _maker);
          assertEq(
            abi.decode(logs[j].data, (uint256)),
            takingAmountFilled < expectedAmount ? takingAmountFilled : expectedAmount
          );
        }
      }
    }
  }

  function testFuzz_feeTaker_unwrapWeth(
    uint256 takingAmount,
    uint256 makingAmount,
    uint256 expiration,
    uint256 expectedAmount
  ) public {
    takingAmount = bound(takingAmount, 1_000_000, 100_000 ether);
    makingAmount = bound(makingAmount, 1_000_000, 100_000 ether);
    expiration = bound(expiration, block.timestamp, block.timestamp + 1 days);
    expectedAmount = bound(expectedAmount, 1, takingAmount - 1);

    IFeeTaker.Distribution memory distribution =
      IFeeTaker.Distribution({expectedAmount: expectedAmount, unwrapWeth: true});

    _flags = [_HAS_EXTENSION_FLAG, _POST_INTERACTION_CALL_FLAG];

    bytes memory extraData = abi.encode(distribution);
    bytes memory extension = _buildExtension('', '', extraData);
    IOrderMixin.Order memory order = _buildOrder(extension, takingAmount, makingAmount, expiration);
    order.receiver = Address.wrap(uint256(uint160(address(_feeTaker))));
    order.takerAsset = _wrapAddress(address(_weth));

    (, bytes32 r, bytes32 vs) = _signOrder(order);
    TakerTraits takerTraits = _buildTakerTraits(extension.length);

    vm.prank(_taker);
    (uint256 makingAmountFilled, uint256 takingAmountFilled,) =
      _limitOrder.fillOrderArgs(order, r, vs, takingAmount, takerTraits, extension);

    assertEq(payable(_maker).balance, distribution.expectedAmount);
    assertEq(_token0.balanceOf(_taker), makingAmountFilled);
    assertEq(_weth.balanceOf(address(_feeTaker)), takingAmountFilled - distribution.expectedAmount);

    {
      Vm.Log[] memory logs = vm.getRecordedLogs();
      for (uint256 j = 0; j < logs.length; j++) {
        if (logs[j].topics[0] == IFeeTaker.TakingAmountTransferred.selector) {
          assertEq(address(uint160(uint256(logs[j].topics[2]))), address(_token1));
          assertEq(address(uint160(uint256(logs[j].topics[3]))), _maker);
          assertEq(uint256(logs[j].topics[4]), distribution.expectedAmount);
        }
      }
    }
  }
}
