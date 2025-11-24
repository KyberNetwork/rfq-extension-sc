// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IFeeTaker {
  event WhitelistUpdated(address indexed recipient, bool status);
  event ProfitDistributed(
    bytes32 indexed orderHash, address indexed token, address indexed recipient, uint256 amount
  );

  error OnlyLimitOrderProtocol();
  error NotWhitelisted();

  struct Distribution {
    uint256 expectedAmount;
    address[] recipients;
    uint256[] shareBps; // basis points (e.g., 10000 = 100%)
    bool unwrapWeth;
    address tail;
  }
}
