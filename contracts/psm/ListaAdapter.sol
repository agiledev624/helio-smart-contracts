// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../interfaces/IVBep20Delegate.sol";

contract ListaAdapter is AccessControlUpgradeable, UUPSUpgradeable {
  using SafeERC20 for IERC20;
  address public vaultManager; // vault manager address
  address public token; // token address
  uint256 public netDepositAmount; // user net deposit amount

  bytes32 public constant MANAGER = keccak256("MANAGER"); // manager role

  event Deposit(uint256 amount);
  event Withdraw(address account, uint256 amount);
  event SetVaultManager(address vaultManager);
  event SetToken(address token);

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  modifier onlyVaultManager() {
    require(msg.sender == vaultManager, "only VaultManager can call this function");
    _;
  }

  /**
   * @dev initialize contract
   * @param _admin admin address
   * @param _manager manager address
   * @param _vaultManager vault manager address
   * @param _token token address
   */
  function initialize(address _admin, address _manager, address _vaultManager, address _token) public initializer {
    require(_admin != address(0), "admin cannot be zero address");
    require(_manager != address(0), "manager cannot be zero address");
    require(_vaultManager != address(0), "vaultManager cannot be zero address");
    require(_token != address(0), "token cannot be zero address");

    __AccessControl_init();
    __UUPSUpgradeable_init();

    _setupRole(DEFAULT_ADMIN_ROLE, _admin);
    _setupRole(MANAGER, _manager);

    vaultManager = _vaultManager;
    token = _token;

    emit SetVaultManager(_vaultManager);
    emit SetToken(_token);
  }

  /**
   * @dev deposit token by vault manager
   * @param amount deposit amount
   */
  function deposit(uint256 amount) external onlyVaultManager {
    require(amount > 0, "deposit amount cannot be zero");
    IERC20(token).safeTransferFrom(vaultManager, address(this), amount);

    netDepositAmount += amount;

    emit Deposit(amount);
  }

  /**
   * @dev withdraw token by vault manager
   * @param account withdraw account
   * @param amount withdraw amount
   */
  function withdraw(address account, uint256 amount) external onlyVaultManager {
    require(amount > 0, "withdraw amount cannot be zero");
    require(amount <= netDepositAmount, "withdraw amount exceeds net deposit");

    netDepositAmount -= amount;

    // transfer token to account
    IERC20(token).safeTransfer(account, amount);

    emit Withdraw(account, amount);
  }

  /**
   * @dev withdraw all token to vault manager
   */
  function withdrawAll() external onlyVaultManager returns (uint256) {
    uint256 totalAmount = IERC20(token).balanceOf(address(this));
    if (totalAmount > 0) {
      netDepositAmount = 0;
      IERC20(token).safeTransfer(vaultManager, totalAmount);
      emit Withdraw(vaultManager, totalAmount);
    }
    return totalAmount;
  }

  function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
