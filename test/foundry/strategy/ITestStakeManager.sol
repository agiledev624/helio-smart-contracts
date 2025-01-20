//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.10;

interface ITestStakeManager {

    struct WithdrawalRequest {
        uint256 uuid;
        uint256 amountInSnBnb;
        uint256 startTime;
    }

    function delegateTo(address validator, uint256 amount) external;

    function undelegateFrom(address _operator, uint256 _amount)
        external
        returns (uint256 _actualBnbAmount);

    function claimUndelegated(address _validator) external returns (uint256, uint256);

    function getAmountToUndelegate() external view returns (uint256);

    function requestUUID() external view returns (uint256);

    function nextConfirmedRequestUUID() external view returns (uint256);

    function getUserWithdrawalRequests(address _address)
        external
        view
        returns (WithdrawalRequest[] memory);

    function getUserRequestStatus(address _user, uint256 _idx)
        external
        view
        returns (bool _isClaimable, uint256 _amount);

    function claimWithdraw(uint256 _idx) external;

    function claimWithdrawFor(address _user, uint256 _idx) external;
}
