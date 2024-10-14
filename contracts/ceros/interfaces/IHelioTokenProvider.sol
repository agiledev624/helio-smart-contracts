// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.10;


interface IHelioTokenProvider {

    /**
     * Structs
     */
    struct Delegation {
        address delegateTo; // who helps delegator to hold clisBNB, aka the delegatee
        uint256 amount;
    }

    /**
     * Events
     */
    event Deposit(address indexed account, uint256 amount, uint256 collateralAmount);
    event Claim(address indexed recipient, uint256 amount);
    event Withdrawal(address indexed owner, address indexed recipient, uint256 amount);
    event Liquidation(address indexed recipient, uint256 amount);

    event ChangeCertToken(address ceToken);
    event ChangeCollateralToken(address collateralToken);
    event ChangeDao(address dao);
    event ChangeProxy(address auctionProxy);
    event ChangeMasterVault(address masterVault);
    event ChangeBNBStakingPool(address pool, bool useStakeManagerPool);
    event ChangeLiquidationStrategy(address strategy);
    event ChangeDelegateTo(address account, address oldDelegatee, address newDelegatee);
    event ChangeGuardian(address oldGuardian, address newGuardian);

    /**
     * Deposit
     */
    function provide(uint256 amount) external returns (uint256);
    function provide(uint256 amount, address delegateTo) external returns (uint256);
    function delegateAllTo(address newDelegateTo) external;

    /**
     * Withdrawal
     */
    function release(address recipient, uint256 amount) external returns (uint256);

    /**
     * DAO FUNCTIONALITY
     */
    function liquidation(address recipient, uint256 amount) external;
    function daoBurn(address account, uint256 amount) external;
    function daoMint(address account, uint256 amount) external;
}
