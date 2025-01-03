// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./interfaces/OracleInterface.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @title BoundValidator
 * @author Lista
 * @notice The BoundValidator contract is used to validate prices fetched from two different sources.
 * Each asset has an upper and lower bound ratio set in the config. In order for a price to be valid
 * it must fall within this range of the validator price.
 */
contract BoundValidator is OwnableUpgradeable, BoundValidatorInterface {
  struct ValidateConfig {
    /// @notice asset address
    address asset;
    /// @notice Upper bound of deviation between reported price and anchor price,
    /// beyond which the reported price will be invalidated
    uint256 upperBoundRatio;
    /// @notice Lower bound of deviation between reported price and anchor price,
    /// below which the reported price will be invalidated
    uint256 lowerBoundRatio;
  }

  /// @notice validation configs by asset
  mapping(address => ValidateConfig) public validateConfigs;

  /// @notice Emit this event when new validation configs are added
  event ValidateConfigAdded(address indexed asset, uint256 indexed upperBound, uint256 indexed lowerBound);

  /// @notice to prevent the implementation contract to initialize itself
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /// @notice Initializes the contract
  function initialize() public initializer {
    __Ownable_init();
  }

  /**
   * @notice Add multiple validation configs at the same time
     * @param configs Array of validation configs
     * @custom:access Only Governance
     * @custom:error Zero length error is thrown if length of the config array is 0
     * @custom:event Emits ValidateConfigAdded for each validation config that is successfully set
     */
  function setValidateConfigs(ValidateConfig[] memory configs) external onlyOwner {
    uint256 length = configs.length;
    if (length == 0) revert("invalid validate config length");
    for (uint256 i; i < length; ) {
      setValidateConfig(configs[i]);
      unchecked {
        ++i;
      }
    }
  }

  /**
   * @notice Add a single validation config
     * @param config Validation config struct
     * @custom:access Only Governance
     * @custom:error Null address error is thrown if asset address is null
     * @custom:error Range error thrown if bound ratio is not positive
     * @custom:error Range error thrown if lower bound is greater than or equal to upper bound
     * @custom:event Emits ValidateConfigAdded when a validation config is successfully set
     */
  function setValidateConfig(ValidateConfig memory config) public onlyOwner {
    if (config.asset == address(0)) revert("asset can't be zero address");
    if (config.upperBoundRatio == 0 || config.lowerBoundRatio == 0) revert("bound must be positive");
    if (config.upperBoundRatio <= config.lowerBoundRatio) revert("upper bound must be higher than lowner bound");
    validateConfigs[config.asset] = config;
    emit ValidateConfigAdded(config.asset, config.upperBoundRatio, config.lowerBoundRatio);
  }

  /**
   * @notice Test reported asset price against anchor price
     * @param asset asset address
     * @param reportedPrice The price to be tested
     * @custom:error Missing error thrown if asset config is not set
     * @custom:error Price error thrown if anchor price is not valid
     */
  function validatePriceWithAnchorPrice(
    address asset,
    uint256 reportedPrice,
    uint256 anchorPrice
  ) public view virtual override returns (bool) {
    if (validateConfigs[asset].upperBoundRatio == 0) revert("validation config not exist");
    if (anchorPrice == 0) revert("anchor price is not valid");
    return _isWithinAnchor(asset, reportedPrice, anchorPrice);
  }

  /**
   * @notice Test whether the reported price is within the valid bounds
     * @param asset Asset address
     * @param reportedPrice The price to be tested
     * @param anchorPrice The reported price must be within the valid bounds of this price
     */
  function _isWithinAnchor(address asset, uint256 reportedPrice, uint256 anchorPrice) private view returns (bool) {
    if (reportedPrice != 0) {
      // we need to multiply anchorPrice by 1e18 to make the ratio 18 decimals
      uint256 anchorRatio = (anchorPrice * 1e18) / reportedPrice;
      uint256 upperBoundAnchorRatio = validateConfigs[asset].upperBoundRatio;
      uint256 lowerBoundAnchorRatio = validateConfigs[asset].lowerBoundRatio;
      return anchorRatio <= upperBoundAnchorRatio && anchorRatio >= lowerBoundAnchorRatio;
    }
    return false;
  }

  // BoundValidator is to get inherited, so it's a good practice to add some storage gaps like
  // OpenZepplin proposed in their contracts: https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
  // solhint-disable-next-line
  uint256[49] private __gap;
}
