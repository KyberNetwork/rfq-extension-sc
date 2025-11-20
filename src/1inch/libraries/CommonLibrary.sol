// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAllowanceTransfer} from 'ks-common-sc/src/interfaces/IAllowanceTransfer.sol';

import {IWETH} from 'ks-common-sc/src/interfaces/IWETH.sol';
import {TokenHelper} from 'ks-common-sc/src/libraries/token/TokenHelper.sol';

library CommonLibrary {
  using TokenHelper for address;
  using CommonLibrary for *;

  function selfBalanceMinusOne(address token) internal view returns (uint256) {
    unchecked {
      uint256 balance = token.selfBalance();
      return balance > 1 ? balance - 1 : 0;
    }
  }

  function addDelta(uint256 value, int256 delta) internal pure returns (uint256 result) {
    assembly ('memory-safe') {
      result := add(value, delta)
    }
  }

  function subDelta(uint256 value, int256 delta) internal pure returns (uint256 result) {
    assembly ('memory-safe') {
      result := sub(value, delta)
    }
  }

  function sub(uint256 value0, uint256 value1) internal pure returns (int256 result) {
    assembly ('memory-safe') {
      result := sub(value0, value1)
    }
  }

  function forceApproveInf(address token, address spender) internal {
    token.forceApprove(spender, type(uint256).max);
  }

  function permit2ApproveInf(address token, address spender, IAllowanceTransfer permit2) internal {
    forceApproveInf(token, address(permit2));
    permit2.approve(token, spender, type(uint160).max, type(uint48).max);
  }

  function wrapETH(IWETH WETH) internal {
    uint256 balance = address(this).balance;
    if (balance > 0) {
      WETH.deposit{value: balance}();
    }
  }

  function unwrapWETH(IWETH WETH) internal {
    unchecked {
      uint256 balance = address(WETH).selfBalance();
      if (balance > 1) {
        WETH.withdraw(balance - 1);
      }
    }
  }
}
