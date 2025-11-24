// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IWETH} from 'ks-common-sc/src/interfaces/IWETH.sol';

contract ImmutableState {
  address internal immutable original;

  IWETH internal immutable WETH;

  constructor(address _WETH) {
    original = address(this);
    WETH = IWETH(_WETH);
  }
}
