// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.10;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {IVault} from "../interfaces/IVault.sol";
import {IDao} from "../interfaces/IDao.sol";
import {IHelioProviderV2} from "../interfaces/IHelioProviderV2.sol";
import {ILpToken} from "../interfaces/ILpToken.sol";
import {IHelioTokenProvider} from "../interfaces/IHelioTokenProvider.sol";


abstract contract BaseLpTokenProvider is IHelioTokenProvider,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    uint128 public constant RATE_DENOMINATOR = 1e18;
    // manager role
    bytes32 public constant MANAGER = keccak256("MANAGER");
    // pause role
    bytes32 public constant PAUSER = keccak256("PAUSER");
    // proxy role
    bytes32 public constant PROXY = keccak256("PROXY");

    /**
     * Variables
     */
    // Tokens
    address public token; // original token, e.g FDUSD
    ILpToken public lpToken; // (clisXXX, e.g clisFDUSD)
    // interaction address
    IDao public dao;
    // account > delegation { delegateTo, amount }
    mapping(address => Delegation) public delegation;
    // delegateTo account > sum delegated amount on this address
    // fixme: remove this field
    mapping(address => uint256) public delegatedCollateral;
    // user account > sum collateral of user
    mapping(address => uint256) public userCollateral;

    /**
     * DEPOSIT
     */
    function _provide(uint256 _amount) internal returns (uint256) {
        require(_amount > 0, "zero deposit amount");

        IERC20(token).safeTransferFrom(msg.sender, address(this), _amount);
        // do sync before balance modified
        _syncCollateral(msg.sender);
        // deposit token as collateral
        uint256 collateralAmount = _provideCollateral(msg.sender, msg.sender, _amount);

        emit Deposit(msg.sender, _amount, collateralAmount);
        return collateralAmount;
    }

    function _provide(uint256 _amount, address _delegateTo) internal returns (uint256) {
        require(_amount > 0, "zero deposit amount");
        require(_delegateTo != address(0), "delegateTo cannot be zero address");
        require(
            delegation[msg.sender].delegateTo == _delegateTo ||
            delegation[msg.sender].amount == 0, // first time, clear old delegatee
            "delegateTo is differ from the current one"
        );

        IERC20(token).safeTransferFrom(msg.sender, address(this), _amount);
        // do sync before balance modified
        _syncCollateral(msg.sender);
        uint256 userCollateral = _provideCollateral(msg.sender, _delegateTo, _amount);

        Delegation storage delegation = delegation[msg.sender];
        delegation.delegateTo = _delegateTo;
        delegation.amount += userCollateral;
        delegatedCollateral[_delegateTo] += userCollateral;

        emit Deposit(msg.sender, _amount, userCollateral);
        return userCollateral;
    }

    /**
     * @dev deposit token to dao, mint collateral tokens to delegateTo
     * by default token to collateral token rate is 1:1
     *
     * @param _account account who deposit token
     * @param _holder collateral token holder
     * @param _amount token amount to deposit
     */
    function _provideCollateral(address _account, address _holder, uint256 _amount)
        virtual
        internal
        returns (uint256)
    {
        // all deposit data will be recorded on behalf of `account`
        dao.deposit(_account, token, _amount);
        // lpTokenHolder can be account or delegateTo
        lpToken.mint(_holder, _amount);
        userCollateral[_account] += _amount;

        return _amount;
    }

    function _delegateAllTo(address _newDelegateTo) internal {
        require(_newDelegateTo != address(0), "delegateTo cannot be zero address");
        _syncCollateral(msg.sender);
        // get user total deposit
        uint256 userCollateral = userCollateral[msg.sender];
        require(userCollateral > 0, "zero collateral to delegate");

        Delegation storage currentDelegation = delegation[msg.sender];
        address currentDelegateTo = currentDelegation.delegateTo;

        // Step 1. burn all tokens
        if (currentDelegation.amount > 0) {
            // burn delegatee's token
            lpToken.burn(currentDelegateTo, currentDelegation.amount);
            delegatedCollateral[currentDelegateTo] -= currentDelegation.amount;
            // burn self's token
            if (userCollateral > currentDelegation.amount) {
                _safeBurnCollateral(msg.sender, userCollateral - currentDelegation.amount);
            }
        } else {
            _safeBurnCollateral(msg.sender, userCollateral);
        }

        // Step 2. save new delegatee and mint all tokens to delegatee
        if (_newDelegateTo == msg.sender) {
            // mint all to self
            lpToken.mint(msg.sender, userCollateral);
            // remove delegatee
            delete delegation[msg.sender];
        } else {
            // mint all to new delegatee
            lpToken.mint(_newDelegateTo, userCollateral);
            // save delegatee's info
            currentDelegation.delegateTo = _newDelegateTo;
            currentDelegation.amount = userCollateral;
            delegatedCollateral[_newDelegateTo] += userCollateral;
        }

        emit ChangeDelegateTo(msg.sender, currentDelegateTo, _newDelegateTo);
    }

    /**
     * RELEASE
     */
    function _release(address _recipient, uint256 _amount) internal returns (uint256) {
        require(_recipient != address(0));
        require(_amount > 0, "zero withdrawal amount");

        _withdrawCollateral(msg.sender, _amount);
        IERC20(token).safeTransfer(_recipient, _amount);
        emit Withdrawal(msg.sender, _recipient, _amount);
        return _amount;
    }

    function _withdrawCollateral(address _account, uint256 _amount) virtual internal {
        _syncCollateral(msg.sender);
        dao.withdraw(_account, address(token), _amount);
        _burnCollateral(_account, _amount);
    }

    /**
     * Burn collateral Token from both delegator and delegateTo
     * @dev burns delegatee's lpToken first, then delegator's
     * by default token to collateral token rate is 1:1
     *
     * @param _account collateral token owner
     * @param _amount token amount to burn
     */
    function _burnCollateral(address _account, uint256 _amount) virtual internal {
        Delegation storage delegation = delegation[_account];
        if (delegation.amount > 0) {
            uint256 delegatedAmount = delegation.amount;
            uint256 delegateeBurn = _amount > delegatedAmount ? delegatedAmount : _amount;
            // burn delegatee's token, update delegated amount
            lpToken.burn(delegation.delegateTo, delegateeBurn);
            delegation.amount -= delegateeBurn;
            delegatedCollateral[delegation.delegateTo] -= delegateeBurn;
            // burn delegator's token
            if (_amount > delegateeBurn) {
                _safeBurnCollateral(_account, _amount - delegateeBurn);
            }
            userCollateral[_account] -= _amount;
        } else {
            // no delegation, only burn from account
            _safeBurnCollateral(_account, _amount);
            userCollateral[_account] -= _amount;
        }
    }

    /**
     * DAO FUNCTIONALITY
     */
    function _liquidation(address _recipient, uint256 _amount) internal {
        require(_recipient != address(0));
        IERC20(token).safeTransfer(_recipient, _amount);
        emit Liquidation(_recipient, _amount);
    }

    function _daoBurn(address _account, uint256 _amount) internal {
        require(_account != address(0));
        _syncCollateral(_account);
        _burnCollateral(_account, _amount);
    }

    /**
     * @dev to make sure existing users who do not have enough lpToken can still burn
     * only the available amount excluding delegated part will be burned
     *
     * @param _account collateral token holder
     * @param _amount amount to burn
     */
    function _safeBurnCollateral(address _account, uint256 _amount) virtual internal {
        // fixme: use local balanceOf instead of erc20.balanceOf
        //        uint256 availableBalance = lpToken.balanceOf(_account) - delegatedCollateral[_account];
        uint256 availableBalance = userCollateral[_account] - delegation[_account].amount;
        if (_amount <= availableBalance) {
            lpToken.burn(_account, _amount);
        } else if (availableBalance > 0) {
            // existing users do not have enough lpToken
            lpToken.burn(_account, availableBalance);
        }
    }


    function _syncCollateral(address _account) internal virtual returns (bool) {
        uint256 userExpectLp = dao.locked(token, _account);
        uint256 userCurrentLp = userCollateral[_account];
        if (userExpectLp == userCurrentLp) {
            return false;
        }

        Delegation storage currentDelegation = delegation[_account];
        uint256 currentDelegateLp = currentDelegation.amount;
        address currentDelegateTo = currentDelegation.delegateTo;
        // Step 1. burn all tokens
        if (currentDelegateLp > 0) {
            // burn delegatee's token
            lpToken.burn(currentDelegateTo, currentDelegateLp);
            delegatedCollateral[currentDelegateTo] -= currentDelegateLp;
            currentDelegation.amount = 0;
            // burn self's token
            if (userCurrentLp > currentDelegateLp) {
                _safeBurnCollateral(_account, userCurrentLp - currentDelegateLp);
            }
        } else {
            _safeBurnCollateral(_account, userCurrentLp);
        }

        uint256 expectDelegateLp = userCurrentLp > 0 ? userExpectLp * currentDelegateLp / userCurrentLp : 0;
        uint256 expectUserSelfLp = userExpectLp - expectDelegateLp;
        if (expectDelegateLp > 0) {
            lpToken.mint(currentDelegateTo, expectDelegateLp);
            delegatedCollateral[currentDelegateTo] += expectDelegateLp;
            currentDelegation.amount = expectDelegateLp;
        }
        if (expectUserSelfLp > 0) {
            lpToken.mint(_account, expectUserSelfLp);
        }
        userCollateral[_account] = userExpectLp;

        emit SyncUserLp(_account, userExpectLp);
        return true;
    }

    function changeToken(address _token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20(token).approve(address(dao), 0);
        token = _token;
        IERC20(token).approve(address(dao), type(uint256).max);
        emit ChangeToken(_token);
    }
    function changeLpToken(address _lpToken) external onlyRole(DEFAULT_ADMIN_ROLE) {
        lpToken = ILpToken(_lpToken);
        emit ChangeLpToken(_lpToken);
    }
    function changeDao(address _dao) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20(token).approve(address(dao), 0);
        dao = IDao(_dao);
        IERC20(token).approve(address(dao), type(uint256).max);
        emit ChangeDao(_dao);
    }

    /**
     * PAUSABLE FUNCTIONALITY
     */
    function pause() external onlyRole(PAUSER) {
        _pause();
    }
    function togglePause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        paused() ? _unpause() : _pause();
    }

    /**
     * UUPSUpgradeable FUNCTIONALITY
     */
    function _authorizeUpgrade(address _newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {
    }

    // storage gap, declared fields: 6/50
    uint256[44] __gap;
}