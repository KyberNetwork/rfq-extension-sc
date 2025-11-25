// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import 'ks-common-sc/script/Base.s.sol';
import 'src/1inch/DecayCurveAmountGetter.sol';

contract DeployDecayCurveScript is BaseScript {
  string salt = '251030';

  /**
   * @dev Deploys DecayCurveAmountGetter contract to specified chains
   *
   * Usage:
   * Deploy to multiple chains using chain ids
   * forge script DeployDecayCurveScript \
   *   --sig "run(string[])" \
   *   "[1,137,8453]" \
   *   --broadcast
   */
  function run(string[] memory chainIds) public multiChain(chainIds) {
    if (bytes(salt).length == 0) {
      revert('salt is required');
    }

    address admin = _readAddressByChainId('admin', vm.getChainId());
    string memory contractSalt = string.concat('DecayCurveAmountGetter_', salt);
    bytes memory creationCode =
      abi.encodePacked(type(DecayCurveAmountGetter).creationCode, abi.encode(admin));

    address decayCurveAmountGetter =
      _create3Deploy(keccak256(abi.encodePacked(contractSalt)), creationCode);

    _writeAddress('decay-curve', decayCurveAmountGetter);
  }
}
