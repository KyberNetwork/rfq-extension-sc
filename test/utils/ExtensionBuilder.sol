// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title ExtensionBuilder
 * @notice Library for building extension calldata for limit orders
 * @author Limit Order Protocol
 * @dev The extension calldata format is:
 *      - First 32 bytes: offsets header (8 uint32 values packed)
 *      - Following bytes: concatenated field data
 */
library ExtensionBuilder {
  /**
   * @notice Calculates cumulative offsets for extension fields
   * @param fields Array of 8 field data bytes
   * @return packedOffsets Packed uint256 containing 8 uint32 offsets
   */
  function _calculateOffsets(bytes[8] memory fields) private pure returns (uint256 packedOffsets) {
    uint256 cumulativeLength = 0;
    for (uint256 i = 0; i < 8; ++i) {
      uint256 fieldLength = fields[i].length;
      if (fieldLength > 0) {
        cumulativeLength += fieldLength;
      }
      packedOffsets |= uint256(uint32(cumulativeLength)) << (32 * i);
    }
  }

  /**
   * @notice Builds extension calldata from individual field data
   * @param makerAssetSuffix Additional data for maker asset (e.g., ERC721 tokenId)
   * @param takerAssetSuffix Additional data for taker asset (e.g., ERC721 tokenId)
   * @param makingAmountData Data for making amount calculation
   * @param takingAmountData Data for taking amount calculation
   * @param predicate Predicate calldata for order validation
   * @param permit Maker permit calldata
   * @param preInteraction Pre-interaction calldata (address + data)
   * @param postInteraction Post-interaction calldata (address + data)
   * @param customData Custom data appended after all fields
   * @return extension The complete extension calldata
   */
  function buildExtension(
    bytes memory makerAssetSuffix,
    bytes memory takerAssetSuffix,
    bytes memory makingAmountData,
    bytes memory takingAmountData,
    bytes memory predicate,
    bytes memory permit,
    bytes memory preInteraction,
    bytes memory postInteraction,
    bytes memory customData
  ) internal pure returns (bytes memory extension) {
    // Prepare fields array
    bytes[8] memory fields;
    fields[0] = makerAssetSuffix;
    fields[1] = takerAssetSuffix;
    fields[2] = makingAmountData;
    fields[3] = takingAmountData;
    fields[4] = predicate;
    fields[5] = permit;
    fields[6] = preInteraction;
    fields[7] = postInteraction;

    // Calculate and pack offsets
    uint256 packedOffsets = _calculateOffsets(fields);

    // Concatenate all field data
    bytes memory concatenatedData = bytes.concat(
      makerAssetSuffix,
      takerAssetSuffix,
      makingAmountData,
      takingAmountData,
      predicate,
      permit,
      preInteraction,
      postInteraction,
      customData
    );

    // Build final extension: offsets header (32 bytes) + concatenated data
    extension = bytes.concat(bytes32(packedOffsets), concatenatedData);
  }

  /**
   * @notice Builds extension calldata with only specific fields
   * @param predicate Predicate calldata
   * @param permit Maker permit calldata
   * @param makingAmountData Making amount calculation data
   * @param takingAmountData Taking amount calculation data
   * @return extension The complete extension calldata
   */
  function buildExtension(
    bytes memory predicate,
    bytes memory permit,
    bytes memory makingAmountData,
    bytes memory takingAmountData
  ) internal pure returns (bytes memory extension) {
    return buildExtension(
      '', // makerAssetSuffix
      '', // takerAssetSuffix
      makingAmountData,
      takingAmountData,
      predicate,
      permit,
      '', // preInteraction
      '', // postInteraction
      '' // customData
    );
  }

  /**
   * @notice Builds extension with interaction data
   * @param preInteraction Pre-interaction calldata (must start with 20-byte address)
   * @param postInteraction Post-interaction calldata (must start with 20-byte address)
   * @return extension The complete extension calldata
   */
  function buildExtensionWithInteractions(
    bytes memory preInteraction,
    bytes memory postInteraction
  ) internal pure returns (bytes memory extension) {
    return buildExtension(
      '', // makerAssetSuffix
      '', // takerAssetSuffix
      '', // makingAmountData
      '', // takingAmountData
      '', // predicate
      '', // permit
      preInteraction,
      postInteraction,
      '' // customData
    );
  }
}
