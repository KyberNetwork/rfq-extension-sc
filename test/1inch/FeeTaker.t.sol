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
    uint256[5] calldata seeds,
    uint256 expectedAmount
  ) public {
    takingAmount = bound(takingAmount, 1_000_000, 100_000 ether);
    makingAmount = bound(makingAmount, 1_000_000, 100_000 ether);
    expiration = bound(expiration, block.timestamp, block.timestamp + 1 days);

    address[] memory recipients = new address[](5);
    recipients[0] = _alice;
    recipients[1] = _bob;
    recipients[2] = _charlie;
    recipients[3] = _david;
    recipients[4] = _eve;

    uint256[] memory shareBps = new uint256[](5);
    shareBps[0] = bound(seeds[0], 1, 5000);
    shareBps[1] = bound(seeds[1], 1, 2000);
    shareBps[2] = bound(seeds[2], 1, 2000);
    shareBps[3] = bound(seeds[3], 1, 1000);
    shareBps[4] = BPS - (shareBps[0] + shareBps[1] + shareBps[2] + shareBps[3]);

    expectedAmount = bound(expectedAmount, 1, takingAmount - 1);

    IFeeTaker.Distribution memory distribution = IFeeTaker.Distribution({
      expectedAmount: expectedAmount,
      recipients: recipients,
      shareBps: shareBps,
      unwrapWeth: false,
      tail: address(0)
    });

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

    uint256 makerBalanceAfter = _token1.balanceOf(_maker);
    uint256 takerBalanceAfter = _token0.balanceOf(_taker);

    assertTrue(makingAmountFilled <= makingAmount);

    assertEq(makerBalanceAfter, distribution.expectedAmount);
    assertEq(takerBalanceAfter, makingAmountFilled);

    assertEq(
      _token1.balanceOf(_alice), (takingAmount - distribution.expectedAmount) * shareBps[0] / BPS
    );
    assertEq(
      _token1.balanceOf(_bob), (takingAmount - distribution.expectedAmount) * shareBps[1] / BPS
    );
    assertEq(
      _token1.balanceOf(_charlie), (takingAmount - distribution.expectedAmount) * shareBps[2] / BPS
    );
    assertEq(
      _token1.balanceOf(_david), (takingAmount - distribution.expectedAmount) * shareBps[3] / BPS
    );
    assertEq(
      _token1.balanceOf(_eve), (takingAmount - distribution.expectedAmount) * shareBps[4] / BPS
    );

    {
      Vm.Log[] memory logs = vm.getRecordedLogs();
      uint256 countDistributed;
      for (uint256 j = 0; j < logs.length; j++) {
        if (logs[j].topics[0] == IFeeTaker.ProfitDistributed.selector) {
          uint256 logTakingAmount = abi.decode(logs[j].data, (uint256));
          assertEq(address(uint160(uint256(logs[j].topics[2]))), address(_token1));
          assertEq(address(uint160(uint256(logs[j].topics[3]))), recipients[countDistributed]);
          assertEq(
            logTakingAmount,
            (takingAmount - distribution.expectedAmount) * shareBps[countDistributed] / BPS
          );
          countDistributed++;
        }
      }
    }
  }

  function testFuzz_feeTaker_partialFill(
    uint256 takingAmount,
    uint256 makingAmount,
    uint256 expiration,
    uint256[5] calldata seeds,
    uint256 expectedAmount,
    uint256 actualFillAmount
  ) public {
    takingAmount = bound(takingAmount, 1_000_000, 100_000 ether);
    makingAmount = bound(makingAmount, 1_000_000, 100_000 ether);
    expiration = bound(expiration, block.timestamp, block.timestamp + 1 days);

    address[] memory recipients = new address[](5);
    recipients[0] = _alice;
    recipients[1] = _bob;
    recipients[2] = _charlie;
    recipients[3] = _david;
    recipients[4] = _eve;

    uint256[] memory shareBps = new uint256[](5);
    shareBps[0] = bound(seeds[0], 1, 5000);
    shareBps[1] = bound(seeds[1], 1, 2000);
    shareBps[2] = bound(seeds[2], 1, 2000);
    shareBps[3] = bound(seeds[3], 1, 1000);
    shareBps[4] = BPS - (shareBps[0] + shareBps[1] + shareBps[2] + shareBps[3]);

    expectedAmount = bound(expectedAmount, 1, takingAmount - 1);

    IFeeTaker.Distribution memory distribution = IFeeTaker.Distribution({
      expectedAmount: expectedAmount,
      recipients: recipients,
      shareBps: shareBps,
      unwrapWeth: false,
      tail: address(0)
    });

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

    uint256 makerBalanceAfter = _token1.balanceOf(_maker);
    uint256 takerBalanceAfter = _token0.balanceOf(_taker);

    assertTrue(makingAmountFilled <= makingAmount);

    assertEq(
      makerBalanceAfter, actualFillAmount < expectedAmount ? actualFillAmount : expectedAmount
    );
    assertEq(takerBalanceAfter, makingAmountFilled);

    uint256 profitAmount = actualFillAmount > distribution.expectedAmount
      ? actualFillAmount - distribution.expectedAmount
      : 0;

    assertEq(_token1.balanceOf(_alice), profitAmount * shareBps[0] / BPS);
    assertEq(_token1.balanceOf(_bob), profitAmount * shareBps[1] / BPS);
    assertEq(_token1.balanceOf(_charlie), profitAmount * shareBps[2] / BPS);
    assertEq(_token1.balanceOf(_david), profitAmount * shareBps[3] / BPS);
    assertEq(_token1.balanceOf(_eve), profitAmount * shareBps[4] / BPS);
  }

  function testFuzz_feeTaker_unwrapWeth(
    uint256 takingAmount,
    uint256 makingAmount,
    uint256 expiration,
    uint256[5] calldata seeds,
    uint256 expectedAmount
  ) public {
    takingAmount = bound(takingAmount, 1_000_000, 100_000 ether);
    makingAmount = bound(makingAmount, 1_000_000, 100_000 ether);
    expiration = bound(expiration, block.timestamp, block.timestamp + 1 days);

    address[] memory recipients = new address[](5);
    recipients[0] = _alice;
    recipients[1] = _bob;
    recipients[2] = _charlie;
    recipients[3] = _david;
    recipients[4] = _eve;

    uint256[] memory shareBps = new uint256[](5);
    shareBps[0] = bound(seeds[0], 1, 5000);
    shareBps[1] = bound(seeds[1], 1, 2000);
    shareBps[2] = bound(seeds[2], 1, 2000);
    shareBps[3] = bound(seeds[3], 1, 1000);
    shareBps[4] = BPS - (shareBps[0] + shareBps[1] + shareBps[2] + shareBps[3]);

    expectedAmount = bound(expectedAmount, 1, takingAmount - 1);

    IFeeTaker.Distribution memory distribution = IFeeTaker.Distribution({
      expectedAmount: expectedAmount,
      recipients: recipients,
      shareBps: shareBps,
      unwrapWeth: true,
      tail: address(0)
    });

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

    uint256 makerBalanceAfter = payable(_maker).balance;
    uint256 takerBalanceAfter = _token0.balanceOf(_taker);

    assertTrue(makingAmountFilled <= makingAmount);

    assertEq(makerBalanceAfter, distribution.expectedAmount);
    assertEq(takerBalanceAfter, makingAmountFilled);

    assertEq(
      _weth.balanceOf(_alice), (takingAmount - distribution.expectedAmount) * shareBps[0] / BPS
    );
    assertEq(
      _weth.balanceOf(_bob), (takingAmount - distribution.expectedAmount) * shareBps[1] / BPS
    );
    assertEq(
      _weth.balanceOf(_charlie), (takingAmount - distribution.expectedAmount) * shareBps[2] / BPS
    );
    assertEq(
      _weth.balanceOf(_david), (takingAmount - distribution.expectedAmount) * shareBps[3] / BPS
    );
    assertEq(
      _weth.balanceOf(_eve), (takingAmount - distribution.expectedAmount) * shareBps[4] / BPS
    );
  }

  function testFuzz_feeTaker_shareBpsTooHigh(
    uint256 takingAmount,
    uint256 makingAmount,
    uint256 expiration,
    uint256[5] calldata seeds,
    uint256 expectedAmount
  ) public {
    takingAmount = bound(takingAmount, 1_000_000, 100_000 ether);
    makingAmount = bound(makingAmount, 1_000_000, 100_000 ether);
    expiration = bound(expiration, block.timestamp, block.timestamp + 1 days);

    address[] memory recipients = new address[](3);
    recipients[0] = _alice;
    recipients[1] = _bob;
    recipients[2] = _charlie;

    uint256[] memory shareBps = new uint256[](3);
    shareBps[0] = 9000;
    shareBps[1] = 1000;
    shareBps[2] = 1000; // last one should have no profit left

    expectedAmount = bound(expectedAmount, 1, takingAmount - 1);

    IFeeTaker.Distribution memory distribution = IFeeTaker.Distribution({
      expectedAmount: expectedAmount,
      recipients: recipients,
      shareBps: shareBps,
      unwrapWeth: false,
      tail: address(0)
    });

    _flags = [_HAS_EXTENSION_FLAG, _POST_INTERACTION_CALL_FLAG];

    bytes memory extraData = abi.encode(distribution);
    bytes memory extension = _buildExtension('', '', extraData);
    IOrderMixin.Order memory order = _buildOrder(extension, takingAmount, makingAmount, expiration);
    order.receiver = Address.wrap(uint256(uint160(address(_feeTaker))));

    (, bytes32 r, bytes32 vs) = _signOrder(order);
    TakerTraits takerTraits = _buildTakerTraits(extension.length);

    vm.prank(_taker);
    (uint256 makingAmountFilled, uint256 takingAmountFilled,) =
      _limitOrder.fillOrderArgs(order, r, vs, takingAmount, takerTraits, extension);

    uint256 makerBalanceAfter = _token1.balanceOf(_maker);
    uint256 takerBalanceAfter = _token0.balanceOf(_taker);

    assertTrue(makingAmountFilled <= makingAmount);

    assertEq(makerBalanceAfter, distribution.expectedAmount);
    assertEq(takerBalanceAfter, makingAmountFilled);

    assertEq(
      _token1.balanceOf(_alice), (takingAmount - distribution.expectedAmount) * shareBps[0] / BPS
    );
    assertEq(
      _token1.balanceOf(_bob), (takingAmount - distribution.expectedAmount) * shareBps[1] / BPS
    );
    assertApproxEqAbs(_token1.balanceOf(_charlie), 0, 1); // rounding
  }

  function testFuzz_feeTaker_notWhitelisted(
    uint256 takingAmount,
    uint256 makingAmount,
    uint256 expiration,
    uint256[5] calldata seeds,
    uint256 expectedAmount
  ) public {
    takingAmount = bound(takingAmount, 1_000_000, 100_000 ether);
    makingAmount = bound(makingAmount, 1_000_000, 100_000 ether);
    expiration = bound(expiration, block.timestamp, block.timestamp + 1 days);

    address[] memory recipients = new address[](5);
    recipients[0] = _alice;
    recipients[1] = _bob;
    recipients[2] = _charlie;
    recipients[3] = _david;
    recipients[4] = _eve;

    uint256[] memory shareBps = new uint256[](5);
    shareBps[0] = bound(seeds[0], 1, 5000);
    shareBps[1] = bound(seeds[1], 1, 2000);
    shareBps[2] = bound(seeds[2], 1, 2000);
    shareBps[3] = bound(seeds[3], 1, 1000);
    shareBps[4] = BPS - (shareBps[0] + shareBps[1] + shareBps[2] + shareBps[3]);

    expectedAmount = bound(expectedAmount, 1, takingAmount - 1);

    IFeeTaker.Distribution memory distribution = IFeeTaker.Distribution({
      expectedAmount: expectedAmount,
      recipients: recipients,
      shareBps: shareBps,
      unwrapWeth: true,
      tail: address(0)
    });

    _flags = [_HAS_EXTENSION_FLAG, _POST_INTERACTION_CALL_FLAG];

    bytes memory extraData = abi.encode(distribution);
    bytes memory extension = _buildExtension('', '', extraData);
    IOrderMixin.Order memory order = _buildOrder(extension, takingAmount, makingAmount, expiration);
    order.receiver = Address.wrap(uint256(uint160(address(_feeTaker))));
    order.takerAsset = _wrapAddress(address(_weth));

    (, bytes32 r, bytes32 vs) = _signOrder(order);
    TakerTraits takerTraits = _buildTakerTraits(extension.length);

    vm.prank(_deployer);
    _feeTaker.whitelistRecipients(recipients, false);

    vm.expectRevert(IFeeTaker.NotWhitelisted.selector);
    vm.prank(_taker);
    _limitOrder.fillOrderArgs(order, r, vs, takingAmount, takerTraits, extension);
  }
}
