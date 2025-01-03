//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../masterVault/interfaces/IMasterVault.sol";
import "../../ceros/interfaces/IBinancePool.sol";
import "../../ceros/interfaces/ICertToken.sol";
import "../../ceros/interfaces/ICerosRouter.sol";
import "../../ceros/interfaces/IVault.sol";
import "../../strategy/BaseStrategy.sol";

contract CerosYieldConverterStrategy is BaseStrategy {

    ICerosRouter private _ceRouter;
    ICertToken private _certToken;
    IBinancePool private _binancePool;
    IVault private _ceVault;

    using SafeERC20 for IERC20;

    event BinancePoolChanged(address binancePool);
    event CeRouterChanged(address ceRouter);

    /// @dev initialize function - Constructor for Upgradable contract, can be only called once during deployment
    /// @param destination Address of the ceros router contract
    /// @param rewards Address of the fee recipient
    /// @param certToken Address of aBNBc token
    /// @param masterVault Address of the masterVault contract
    /// @param binancePool Address of binancePool contract
    /// @param ceVault Address of CeVault
    function initialize(
        address destination,
        address rewards,
        address certToken,
        address masterVault,
        address binancePool,
        address ceVault
    ) public initializer {
        __BaseStrategy_init(destination, rewards, masterVault);
        _ceRouter = ICerosRouter(destination);
        _certToken = ICertToken(certToken);
        _binancePool = IBinancePool(binancePool);
        _ceVault = IVault(ceVault);
    }

    /// @dev deposits the given amount of underlying tokens into ceros
    function deposit() external payable onlyVault returns(uint256 value) {
        return _deposit(msg.value);
    }

    /// @dev deposits all the available underlying tokens into ceros
    function depositAll() external onlyStrategist {
        _deposit(address(this).balance);
    }

    /// @dev internal function to deposit the given amount of underlying tokens into ceros
    /// @param amount amount of underlying tokens
    function _deposit(uint256 amount) whenDepositNotPaused internal returns (uint256 value) {
        require(amount > 0, "invalid amount");
        if (canDeposit(amount)) {
            return _ceRouter.deposit{value: amount}();
        }
    }

    /// @dev withdraws the given amount of underlying tokens from ceros and transfers to masterVault
    /// @param amount amount of underlying tokens
    function withdraw(address recipient, uint256 amount) nonReentrant onlyVault external returns(uint256 value) {
        return _withdraw(recipient, amount);
    }

    /// @dev withdraws everything from ceros and transfers to masterVault
    function panic() external nonReentrant onlyStrategist returns (uint256 value) {
        (,, uint256 debt) = vault.strategyParams(address(this));
        return _withdraw(address(vault), debt);
    }

    /// @dev internal function to withdraw the given amount of underlying tokens from ceros
    ///      and transfers to masterVault
    /// @param amount amount of underlying tokens
    /// @return value - returns the amount of underlying tokens withdrawn from ceros
    function _withdraw(address recipient, uint256 amount) internal returns (uint256 value) {
        require(amount > 0, "invalid amount");
        uint256 ethBalance = address(this).balance;
        if(amount < ethBalance) {
            (bool sent, ) = payable(recipient).call{value: amount}("");
            require(sent, "transfer failed");
            return amount;
        } else {
            _ceRouter.withdraw(recipient, amount);
            return amount;
        }
    }

    // withdrawal aBNBc
    /// @param recipient address to receive withdrawan aBNBc
    /// @param amount in BNB
    function withdrawInToken(address recipient, uint256 amount)
    external
    override
    nonReentrant
    onlyVault
    returns (uint256 realAmount)
    {
        return _ceRouter.withdrawABNBc(recipient, amount);
    }

    //estimate how much token(aBNBc) can get when do withdrawInToken
    function estimateInToken(uint256 amount) external view returns(uint256){
        uint256 ratio = _certToken.ratio();
        return (amount * ratio) / 1e18;
    }

    // calculate the total(aBNBc) in the strategy contract
    function balanceOfToken() external view returns(uint256){
        return _ceVault.getDepositOf(address(this)) - _ceVault.getClaimedOf(address(this)) - _ceVault.getYieldFor(address(this));
    }

    function canDeposit(uint256 amount) public view returns(bool) {
        uint256 minimumStake = IBinancePool(_binancePool).getMinimumStake();
        uint256 relayerFee = _binancePool.getRelayerFee();
        return (amount >= minimumStake + relayerFee);
    }

    function assessDepositFee(uint256 amount) public view returns(uint256) {
        return amount - _binancePool.getRelayerFee();
    }

    /// @dev claims yield from ceros in aBNBc and transfers to feeRecipient
    function harvest() external onlyStrategist {
        _harvestTo(rewards);
    }

    /// @dev internal function to claim yield from ceros in aBNBc and transfer them to desired address
    function _harvestTo(address to) private returns(uint256 yield) {
        yield = _ceRouter.getYieldFor(address(this));
        if(yield > 0) {
            yield = _ceRouter.claim(to);
        }
        uint256 profit = _ceRouter.getProfitFor(address(this));
        if(profit > 0) {
            yield += profit;
            _ceRouter.claimProfit(to);
        }
        emit Harvested(to, yield);
    }

    /// @dev only owner can change binance pool address
    /// @param binancePool new binance pool address
    function changeBinancePool(address binancePool) external onlyOwner {
        require(binancePool != address(0));
        _binancePool = IBinancePool(binancePool);
        emit BinancePoolChanged(binancePool);
    }

    /// @dev only owner can change ceRouter
    /// @param ceRouter new ceros router address
    function changeCeRouter(address ceRouter) external onlyOwner {
        require(ceRouter != address(0));
        destination = ceRouter;
        _ceRouter = ICerosRouter(ceRouter);
        emit CeRouterChanged(ceRouter);
    }
}
