// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library ExtensionBuilder {
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

  function buildExtensionWithInteractions(bytes memory preInteraction, bytes memory postInteraction)
    internal
    pure
    returns (bytes memory extension)
  {
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
