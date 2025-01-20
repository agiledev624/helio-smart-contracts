//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../masterVault/interfaces/IMasterVault.sol";
import "../snbnb/interfaces/ISnBnbStakeManager.sol";
import "./BaseStrategy.sol";

contract SnBnbYieldConverterStrategy is BaseStrategy {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    IERC20Upgradeable private _snBnbToken;
    ISnBnbStakeManager private _stakeManager;

    struct UserWithdrawRequest {
        address recipient;
        uint256 amount; //BNB
        uint256 snBnbAmount;
        uint256 triggerTime;
    }
    mapping(uint256 => UserWithdrawRequest) private _withdrawRequests;
    uint256 private _firstDistributeIdx;
    uint256 private _nextWithdrawIdx;

    /**
     * @dev for storing the withdraw requests that can't be fulfilled via the automated mechanism because of gas limits
     * and have to be manually distributed. It stores the sum of all such requests for a recipient.
     */
    mapping(address => uint256) public manualWithdrawAmount;

    uint256 public bnbDepositBalance; // amount of bnb deposited by this strategy
    uint256 public snBnbToUnstake; // amount of snBnb to withdraw from synclub in next batchWithdraw
    uint256 public bnbToDistribute; // amount of bnb to distribute to users who unstaked

    uint256 public lastUnstakeTriggerTime; // last time when batchWithdraw was invoked

    event SnBnbStakeManagerChanged(address stakeManager);
    event AddManualWithdrawAmount(address recipient, uint256 amount);
    event ManualWithdraw(address recipient, uint256 amount);

    /// @dev initialize function - Constructor for Upgradable contract, can be only called once during deployment
    /// @param destination Address of the stakeManager contract
    /// @param rewardsAddr Address which receives yield
    /// @param snBnbToken Address of snBNB token
    /// @param masterVault Address of the masterVault contract
    function initialize(
        address destination,
        address rewardsAddr,
        address snBnbToken,
        address masterVault
    ) public initializer {
        __BaseStrategy_init(destination, rewardsAddr, masterVault);

        _snBnbToken = IERC20Upgradeable(snBnbToken);
        _stakeManager = ISnBnbStakeManager(destination);
        lastUnstakeTriggerTime = block.timestamp;

        _snBnbToken.safeApprove(destination, type(uint256).max);
    }

    /// @dev deposits the given amount of BNB into Synclub stakeManager
    function deposit()
        external
        payable
        nonReentrant
        onlyVault
        returns (uint256)
    {
        uint256 amount = msg.value;
        return _deposit(amount);
    }

    /// @dev internal function to deposit the given amount of BNB into Synclub stakeManager
    /// @param amount amount of BNB to deposit
    function _deposit(uint256 amount)
        internal
        whenDepositNotPaused
        returns (uint256)
    {
        require(canDeposit(amount), "invalid amount");
        bnbDepositBalance += amount;
        _stakeManager.deposit{value: amount}();
        return amount;
    }


    /// @dev creates an entry to withdraw the given amount of BNB from Synclub's stakeManager
    /// @param amount amount of BNB to withdraw
    function withdraw(address recipient, uint256 amount)
        external
        nonReentrant
        onlyVault
        returns (uint256)
    {
        return _withdraw(recipient, amount);
    }

    // @dev get SnBNB from strategy
    /// @param amount amount of BNB to withdraw
    /// returns the amount of SnBNB that will be transfer to recipient
    function withdrawInToken(address recipient, uint256 amount)
        external
        nonReentrant
        onlyVault
        returns (uint256){
        uint256 snBnbAmount = _stakeManager.convertBnbToSnBnb(amount);
        _snBnbToken.safeTransfer(recipient, snBnbAmount);
        bnbDepositBalance -= amount;
        return snBnbAmount;
    }

    //estimate how much token(snBNB) can get when do withdrawInToken
    function estimateInToken(uint256 amount) external view returns(uint256){
        return _stakeManager.convertBnbToSnBnb(amount);
    }

    // calculate the total(snBNB) in the strategy contract
    function balanceOfToken() public view returns(uint256){
        return _snBnbToken.balanceOf(address(this));
    }

    /// @dev creates an entry to withdraw everything(bnbDeposited) from Synclub's stakeManager
    function panic() external nonReentrant onlyStrategist returns (uint256) {
        (, , uint256 debt) = vault.strategyParams(address(this));
        return _withdraw(address(vault), debt);
    }

    /// @dev internal function to create an withdraw the given amount of BNB from Synclub's stakeManager
    /// @param amount amount of BNB
    /// @return value - returns the amount of BNB that will be withdrawn from Synclub in future
    function _withdraw(address recipient, uint256 amount)
        internal
        returns (uint256 value)
    {
        uint256 snBnbAmount = _stakeManager.convertBnbToSnBnb(amount);
        bnbDepositBalance -= amount;
        snBnbToUnstake += snBnbAmount;
        _withdrawRequests[_nextWithdrawIdx++] = UserWithdrawRequest({
            recipient: recipient,
            amount: amount,
            snBnbAmount: snBnbAmount,
            triggerTime: block.timestamp
        });

        return amount;
    }

    // Anybody can call.
    // actual withdraw request to Snyclub, should be called max once a hour
    function batchWithdraw() external nonReentrant {
        require(
            block.timestamp - lastUnstakeTriggerTime >= 1 hours,
            "Allowed once per hour"
        );
        require(snBnbToUnstake > 0, "No SnBNB to unstake");

        uint256 snBnbToUnstake_ = snBnbToUnstake; // To prevent reentrancy
        snBnbToUnstake = 0;
        lastUnstakeTriggerTime = block.timestamp;
        _stakeManager.requestWithdraw(snBnbToUnstake_);
    }

    /// @param maxNumRequests : parameter to control max number of requests to refund
    /// @return foundClaimableReq : true if claimed any batch, false if no batch is available to claim
    /// @return reqCount : actual number requests refunded
    function claimNextBatchAndDistribute(uint256 maxNumRequests)
        external
        nonReentrant
        returns (bool foundClaimableReq, uint256 reqCount)
    {
        foundClaimableReq = _claimNextBatch();
        reqCount = _distributeFund(maxNumRequests);
    }

    /// @dev claims the next available withdraw batch from Synclub
    /// @dev transfer funds(BNB) from stakeManager to strategy
    /// @return foundClaimableReq : true if claimed any batch, false if no batch is available to claim
    function claimNextBatch()
        public
        nonReentrant
        returns (bool foundClaimableReq)
    {
        return _claimNextBatch();
    }

    function _claimNextBatch() private returns (bool foundClaimableReq) {
        ISnBnbStakeManager.WithdrawalRequest[] memory requests = _stakeManager
            .getUserWithdrawalRequests(address(this));

        uint256 idx = 0;
        for (uint256 times = 0; times < requests.length; times++) {
            (bool isClaimable, uint256 amount) = _stakeManager
                .getUserRequestStatus(address(this), idx);

            if (!isClaimable) {
                idx++;
                continue;
            }

            // update bnbToDistribute in receive()
            _stakeManager.claimWithdraw(idx);
            return true;
        }

        return false;
    }

    /// @dev distribute claimed funds to users in FIFO order of withdraw requests
    /// @param maxNumRequests : parameter to control max number of requests to refund
    /// @return reqCount : actual number requests refunded
    function distributeFund(uint256 maxNumRequests)
        public
        nonReentrant
        returns (uint256 reqCount)
    {
        return _distributeFund(maxNumRequests);
    }

    function _distributeFund(uint256 maxNumRequests)
        private
        returns (uint256 reqCount)
    {
        for (
            reqCount = 0;
            reqCount < maxNumRequests &&
                _firstDistributeIdx < _nextWithdrawIdx &&
                _withdrawRequests[_firstDistributeIdx].amount <=
                bnbToDistribute;
            reqCount++
        ) {
            address recipient = _withdrawRequests[_firstDistributeIdx]
                .recipient;
            uint256 amount = _withdrawRequests[_firstDistributeIdx].amount;

            delete _withdrawRequests[_firstDistributeIdx];
            _firstDistributeIdx++;
            bnbToDistribute -= amount;

            (
                bool sent, /*memory data*/

            ) = payable(recipient).call{value: amount, gas: 5000}("");

            if (!sent) {
                // the recipient didn't accept direct funds within the specified gas, so save the whole request to be
                // withdrawn by the recipient manually later
                manualWithdrawAmount[recipient] += amount;
                emit AddManualWithdrawAmount(recipient, amount);
            }
        }
    }

    /// @dev Anybody can call this to manually send the withdrawn funds to a recipient, if the recipient had funds that
    /// need to be manually withdrawn.
    function distributeManual(address recipient) external nonReentrant {
        uint256 amount = manualWithdrawAmount[recipient];
        require(amount > 0, "!distributeManual");

        delete manualWithdrawAmount[recipient];

        (
            bool sent, /*memory data*/
        ) = payable(recipient).call{value: amount}("");
        require(sent, "!sent");

        emit ManualWithdraw(recipient, amount);
    }

    /// @dev claims yield from Synclub in SnBNB and transfers to rewardsAddr
    function harvest() external nonReentrant onlyStrategist {
        _harvestTo(rewards);
    }

    /// @dev internal function to claim yield from Synclub in SnBNB and transfer them to desired address
    function _harvestTo(address to) private returns (uint256 yield) {
        yield = calculateYield();

        require(yield > 0, "no yield to harvest");

        _snBnbToken.safeTransfer(to, yield);
        emit Harvested(to, yield);
    }

    function calculateYield() public view returns (uint256 yield) {
        uint256 snBnbEqAmount = _stakeManager.convertBnbToSnBnb(
            bnbDepositBalance
        );

        // yield = snBnbHoldingBalance - snBnbEqAmount
        // snHoldingBalance = _snBnbToken.balanceOf(address(this)) - snBnbToUnstake
        yield = balanceOfToken() - snBnbToUnstake - snBnbEqAmount;
    }

    // returns the total amount of tokens in the destination contract
    function balanceOfPool() public view override returns (uint256) {
        return bnbDepositBalance;
    }

    function canDeposit(uint256 amount) public pure returns (bool) {
        return (amount > 0);
    }

    function assessDepositFee(uint256 amount) public pure returns (uint256) {
        return amount;
    }

    /// @dev get the withdraw requests of the user
    /// @param account - address of the user
    /// @return requests - the withdraw requests of the user
    function getWithdrawRequests(address account) external view returns (UserWithdrawRequest[] memory requests) {
        uint256 count = 0;
        for (uint256 i = _firstDistributeIdx; i < _nextWithdrawIdx; i++) {
            if (_withdrawRequests[i].recipient == account) {
                count++;
            }
        }
        if (count == 0) {
            return requests;
        }
        requests = new UserWithdrawRequest[](count);
        uint256 idx;
        for (uint256 i = _firstDistributeIdx; i < _nextWithdrawIdx; i++) {
            if (_withdrawRequests[i].recipient == account) {
                requests[idx++] = _withdrawRequests[i];
            }
        }

        return requests;
    }

    receive() external payable override {
        require(
            msg.sender == destination ||
            msg.sender == strategist,
            "invalid sender"
        );

        if (msg.sender == destination) {
            // The amount transferred from Synclub may be a little more than the users' withdrawal requests
            // due to possible increases in the snBNB:BNB exchange rate.
            bnbToDistribute += msg.value;
        }
    }
}
