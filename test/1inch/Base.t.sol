// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {IWETH} from '@1inch/solidity-utils/contracts/interfaces/IWETH.sol';
import {Address, AddressLib} from '@1inch/solidity-utils/contracts/libraries/AddressLib.sol';
import 'forge-std/Test.sol';
import {LimitOrderProtocol} from 'limit-order-protocol/contracts/LimitOrderProtocol.sol';
import {IOrderMixin} from 'limit-order-protocol/contracts/interfaces/IOrderMixin.sol';
import {MakerTraits} from 'limit-order-protocol/contracts/libraries/MakerTraitsLib.sol';
import {TakerTraits} from 'limit-order-protocol/contracts/libraries/TakerTraitsLib.sol';
import {WrappedTokenMock} from 'limit-order-protocol/contracts/mocks/WrappedTokenMock.sol';
import {ERC20Mock} from 'openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol';
import {TimeWeightedAmountGetter} from 'src/1inch/TimeWeightedAmountGetter.sol';
import {ExtensionBuilder} from 'test/utils/ExtensionBuilder.sol';

abstract contract BaseTest is Test {
  using AddressLib for Address;

  uint256 internal constant _ALLOWED_SENDER_MASK = type(uint80).max;
  uint256 internal constant _EXPIRATION_OFFSET = 80;
  uint256 internal constant _EXPIRATION_MASK = type(uint40).max;
  uint256 internal constant _NONCE_OR_EPOCH_OFFSET = 120;
  uint256 internal constant _NONCE_OR_EPOCH_MASK = type(uint40).max;
  uint256 internal constant _SERIES_OFFSET = 160;
  uint256 internal constant _SERIES_MASK = type(uint40).max;

  uint256 internal constant _NO_PARTIAL_FILLS_FLAG = 1 << 255;
  uint256 internal constant _ALLOW_MULTIPLE_FILLS_FLAG = 1 << 254;
  uint256 internal constant _PRE_INTERACTION_CALL_FLAG = 1 << 252;
  uint256 internal constant _POST_INTERACTION_CALL_FLAG = 1 << 251;
  uint256 internal constant _NEED_CHECK_EPOCH_MANAGER_FLAG = 1 << 250;
  uint256 internal constant _HAS_EXTENSION_FLAG = 1 << 249;
  uint256 internal constant _USE_PERMIT2_FLAG = 1 << 248;
  uint256 internal constant _UNWRAP_WETH_FLAG = 1 << 247;

  uint256 internal constant _MAKER_PRIVATE_KEY = 0xA11CE;
  uint256 internal constant _TAKER_PRIVATE_KEY = 0xB0B;

  LimitOrderProtocol internal _limitOrder;
  TimeWeightedAmountGetter internal _amountGetter;
  WrappedTokenMock internal _weth;
  ERC20Mock internal _token0;
  ERC20Mock internal _token1;
  uint256[] internal _flags;

  address internal _maker;
  address internal _taker;
  uint256 internal _baseTimestamp = 1_000_000;

  function setUp() public virtual {
    _maker = vm.addr(_MAKER_PRIVATE_KEY);
    _taker = vm.addr(_TAKER_PRIVATE_KEY);

    _weth = new WrappedTokenMock('Wrapped Ether', 'WETH');
    _limitOrder = new LimitOrderProtocol(IWETH(address(_weth)));
    _amountGetter = new TimeWeightedAmountGetter();
    _token0 = new ERC20Mock();
    _token1 = new ERC20Mock();
    vm.label(_maker, 'Maker');
    vm.label(_taker, 'Taker');
    vm.label(address(_weth), 'WETH');
    vm.label(address(_limitOrder), 'LimitOrderProtocol');
    vm.label(address(_amountGetter), 'KSAmountGetter');
    vm.label(address(_token0), 'Token0');
    vm.label(address(_token1), 'Token1');

    _token0.mint(_maker, 100_000 ether);
    _token1.mint(_taker, 100_000 ether);

    vm.prank(_maker);
    _token0.approve(address(_limitOrder), type(uint256).max);
    vm.prank(_taker);
    _token1.approve(address(_limitOrder), type(uint256).max);

    vm.warp(_baseTimestamp);
  }

  function _buildExtension(bytes memory makingAmountData, bytes memory takingAmountData)
    internal
    view
    returns (bytes memory)
  {
    if (makingAmountData.length > 0) {
      makingAmountData = bytes.concat(bytes20(address(_amountGetter)), makingAmountData);
    }
    if (takingAmountData.length > 0) {
      takingAmountData = bytes.concat(bytes20(address(_amountGetter)), takingAmountData);
    }
    takingAmountData = bytes.concat(bytes20(address(_amountGetter)), takingAmountData);
    return ExtensionBuilder.buildExtension({
      makerAssetSuffix: '',
      takerAssetSuffix: '',
      makingAmountData: makingAmountData,
      takingAmountData: takingAmountData,
      predicate: '',
      permit: '',
      preInteraction: '',
      postInteraction: '',
      customData: ''
    });
  }

  function _buildOrder(
    bytes memory extension,
    uint256 takingAmount,
    uint256 makingAmount,
    uint256 expiration
  ) internal view returns (IOrderMixin.Order memory order) {
    order.salt = uint256(keccak256(extension));
    order.maker = _wrapAddress(_maker);
    order.receiver = Address.wrap(0);
    order.makerAsset = _wrapAddress(address(_token0));
    order.takerAsset = _wrapAddress(address(_token1));
    order.makingAmount = makingAmount;
    order.takingAmount = takingAmount;
    order.makerTraits = _buildMakerTraits(expiration);
  }

  function _buildMakerTraits(uint256 expiration) internal view returns (MakerTraits) {
    uint256 traits = (uint256(expiration) << 80);
    for (uint256 i = 0; i < _flags.length; i++) {
      traits |= _flags[i];
    }
    return MakerTraits.wrap(traits);
  }

  function _wrapAddress(address account) internal pure returns (Address) {
    return Address.wrap(uint256(uint160(account)));
  }

  function _buildTakerTraits(uint256 extensionLength) internal pure returns (TakerTraits) {
    uint256 traits = extensionLength << 224;
    return TakerTraits.wrap(traits);
  }

  function _signOrder(IOrderMixin.Order memory order)
    internal
    view
    returns (bytes32 orderHash, bytes32 r, bytes32 vs)
  {
    orderHash = _limitOrder.hashOrder(order);
    (uint8 v, bytes32 rRaw, bytes32 sRaw) = vm.sign(_MAKER_PRIVATE_KEY, orderHash);
    r = rRaw;
    vs = _toCompact(v, sRaw);
  }

  function _toCompact(uint8 v, bytes32 s) internal pure returns (bytes32) {
    uint256 value = uint256(s);
    if (v == 28) {
      value |= 1 << 255;
    }
    return bytes32(value);
  }
}
