// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IFeeTaker {
  event TakingAmountTransferred(
    bytes32 indexed orderHash, address indexed token, address indexed recipient, uint256 amount
  );

  error OnlyLimitOrderProtocol();

  struct Distribution {
    uint256 expectedAmount;
    bool unwrapWeth;
  }
}
