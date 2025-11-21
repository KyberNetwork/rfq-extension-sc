// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IOrderMixin} from 'limit-order-protocol/contracts/interfaces/IOrderMixin.sol';
import {IPostInteraction} from 'limit-order-protocol/contracts/interfaces/IPostInteraction.sol';

import {ManagementBase} from 'ks-common-sc/src/base/ManagementBase.sol';
import {ManagementPausable} from 'ks-common-sc/src/base/ManagementPausable.sol';
import {ManagementRescuable} from 'ks-common-sc/src/base/ManagementRescuable.sol';

import {Address, AddressLib} from '@1inch/solidity-utils/contracts/libraries/AddressLib.sol';
import {IWETH} from 'ks-common-sc/src/interfaces/IWETH.sol';
import {CustomRevert} from 'ks-common-sc/src/libraries/CustomRevert.sol';
import {KSRoles} from 'ks-common-sc/src/libraries/KSRoles.sol';
import {TokenHelper} from 'ks-common-sc/src/libraries/token/TokenHelper.sol';

import {CommonLibrary} from './libraries/CommonLibrary.sol';

import {IFeeTaker} from './interfaces/IFeeTaker.sol';

import {ImmutableState} from './base/ImmutableState.sol';

contract FeeTaker is
  IPostInteraction,
  IFeeTaker,
  ManagementRescuable,
  ManagementPausable,
  ImmutableState
{
  using TokenHelper for address;
  using AddressLib for Address;

  uint256 constant BPS = 10_000;
  address private immutable LIMIT_ORDER_PROTOCOL;

  mapping(address => bool) public whitelistedRecipients;

  modifier onlyLimitOrderProtocol() {
    if (msg.sender != LIMIT_ORDER_PROTOCOL) revert OnlyLimitOrderProtocol();
    _;
  }

  constructor(
    address initialAdmin,
    address[] memory initialRescuers,
    address _WETH,
    address _LIMIT_ORDER_PROTOCOL
  ) ManagementBase(0, initialAdmin) ImmutableState(_WETH) {
    _batchGrantRole(KSRoles.RESCUER_ROLE, initialRescuers);
    WETH = IWETH(_WETH);
    LIMIT_ORDER_PROTOCOL = _LIMIT_ORDER_PROTOCOL;
  }

  function whitelistRecipients(address[] calldata _recipients, bool _grantOrRevoke)
    external
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    for (uint256 i = 0; i < _recipients.length; i++) {
      whitelistedRecipients[_recipients[i]] = _grantOrRevoke;
      emit WhitelistUpdated(_recipients[i], _grantOrRevoke);
    }
  }

  function postInteraction(
    IOrderMixin.Order calldata order,
    bytes calldata,
    bytes32 orderHash,
    address,
    uint256,
    uint256 takingAmount,
    uint256,
    bytes calldata data
  ) external override onlyLimitOrderProtocol {
    Distribution memory distribution = abi.decode(data, (Distribution));

    address maker = order.maker.get();
    address takingToken = order.takerAsset.get();

    uint256 profitAmount =
      takingAmount > distribution.expectedAmount ? takingAmount - distribution.expectedAmount : 0;

    if (distribution.unwrapWeth) {
      WETH.withdraw(takingAmount - profitAmount);
      TokenHelper.safeTransferNative(maker, takingAmount - profitAmount);
    } else {
      takingToken.safeTransfer(maker, takingAmount - profitAmount);
    }

    if (profitAmount != 0) {
      uint256 remainingProfit = profitAmount;
      for (uint256 i = 0; i < distribution.recipients.length; i++) {
        if (!whitelistedRecipients[distribution.recipients[i]]) {
          revert NotWhitelisted();
        }

        uint256 recipientAmount = (profitAmount * distribution.shareBps[i]) / BPS;
        recipientAmount = remainingProfit < recipientAmount ? remainingProfit : recipientAmount;

        takingToken.safeTransfer(distribution.recipients[i], recipientAmount);
        remainingProfit -= recipientAmount;

        emit ProfitDistributed(orderHash, takingToken, distribution.recipients[i], recipientAmount);
      }
    }
  }

  receive() external payable {}
}
