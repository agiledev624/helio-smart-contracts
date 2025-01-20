// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "../../../contracts/Interaction.sol";
import "../../../contracts/LisUSD.sol";
import "../../../contracts/amo/DynamicDutyCalculator.sol";
import "../../../contracts/oracle/ResilientOracle.sol";

import "../../../contracts/strategy/SnBnbYieldConverterStrategy.sol";
import "./ITestStakeManager.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";


contract SnBnbYieldConverterStrategyTest is Test {
    uint256 mainnet;

    address user = address(0x00AA);
    address user1 = address(0x00AB);

    address bot = address(0x9c975db5E112235b6c4a177C2A5c67ab4d758499);

    address masterVault = address(0x986b40C2618fF295a49AC442c5ec40febB26CC54);

    address validatorLegend = address(0x773760b0708a5Cc369c346993a0c225D8e4043B1);

    ISnBnbStakeManager stakeManager;

    SnBnbYieldConverterStrategy strategy;

    function setUp() public {
        mainnet = vm.createSelectFork("https://bsc-dataseed.binance.org");

        ProxyAdmin proxyAdmin = ProxyAdmin(address(0x1Fa3E4718168077975fF4039304CC2e19Ae58c4C));
        SnBnbYieldConverterStrategy impl = new SnBnbYieldConverterStrategy();
        ITransparentUpgradeableProxy proxy = ITransparentUpgradeableProxy(payable(address(0x6F28FeC449dbd2056b76ac666350Af8773E03873)));

        vm.startPrank(address(0x07D274a68393E8b8a2CCf19A2ce4Ba3518735253));
        proxyAdmin.upgrade(proxy, address(impl));
        vm.stopPrank();

        stakeManager = ISnBnbStakeManager(address(0x1adB950d8bB3dA4bE104211D5AB038628e477fE6));
        strategy = SnBnbYieldConverterStrategy(payable(address(0x6F28FeC449dbd2056b76ac666350Af8773E03873)));
    }

    function test_deposit() public {
        deal(masterVault, 3 ether);

        vm.startPrank(masterVault);
        strategy.deposit{value: 1 ether}();
        vm.stopPrank();

        vm.startPrank(masterVault);
        vm.expectRevert("invalid sender");
        payable(strategy).call{value: 2 ether, gas: 5000}("");
        vm.stopPrank();
    }

    function test_claimNextBatch_receive() public {
        deal(masterVault, 10_000 ether);

        vm.prank(masterVault);
        strategy.deposit{value: 10_000 ether}();

        vm.prank(bot);
        ITestStakeManager(address(stakeManager)).delegateTo(validatorLegend, 10_000 ether);

        deal(user, 0);
        vm.prank(masterVault);
        strategy.withdraw(user, 89 ether);
        strategy.batchWithdraw();

        uint256 undelegateAmount0 = ITestStakeManager(address(stakeManager)).getAmountToUndelegate();
        vm.prank(bot);
        ITestStakeManager(address(stakeManager)).undelegateFrom(validatorLegend, undelegateAmount0 + 1 ether);

        skip(1 days);
        vm.prank(masterVault);
        strategy.withdraw(user1, 9_000 ether);
        strategy.batchWithdraw();

        uint256 undelegateAmount1 = ITestStakeManager(address(stakeManager)).getAmountToUndelegate();
        vm.prank(bot);
        ITestStakeManager(address(stakeManager)).undelegateFrom(validatorLegend, undelegateAmount1 + 1 ether);

        skip(8 days);
        vm.prank(bot);
        ITestStakeManager(address(stakeManager)).claimUndelegated(validatorLegend);

        assertEq(0, address(user).balance, "user balance");
        for (uint256 i = 0; i < 10; i++) {
            strategy.claimNextBatchAndDistribute(50);
        }
        assertEq(89 ether, address(user).balance, "user balance");
    }

    function test_claimNextBatch_receive_for() public {
        deal(masterVault, 10_000 ether);

        vm.prank(masterVault);
        strategy.deposit{value: 10_000 ether}();

        vm.prank(bot);
        ITestStakeManager(address(stakeManager)).delegateTo(validatorLegend, 10_000 ether);

        deal(user, 0);
        vm.prank(masterVault);
        strategy.withdraw(user, 89 ether);
        strategy.batchWithdraw();

        uint256 undelegateAmount0 = ITestStakeManager(address(stakeManager)).getAmountToUndelegate();
        vm.prank(bot);
        ITestStakeManager(address(stakeManager)).undelegateFrom(validatorLegend, undelegateAmount0 + 1 ether);

        skip(1 days);
        vm.prank(masterVault);
        strategy.withdraw(user1, 9_000 ether);
        strategy.batchWithdraw();

        uint256 undelegateAmount1 = ITestStakeManager(address(stakeManager)).getAmountToUndelegate();
        vm.prank(bot);
        ITestStakeManager(address(stakeManager)).undelegateFrom(validatorLegend, undelegateAmount1 + 1 ether);

        skip(8 days);
        vm.prank(bot);
        ITestStakeManager(address(stakeManager)).claimUndelegated(validatorLegend);

        ITestStakeManager.WithdrawalRequest[] memory requests = ITestStakeManager(address(stakeManager))
            .getUserWithdrawalRequests(address(strategy));
        uint256 idx = 0;
        for (uint256 times = 0; times < requests.length; times++) {
            (bool isClaimable, uint256 amount) = ITestStakeManager(address(stakeManager))
                .getUserRequestStatus(address(strategy), idx);
            if (!isClaimable) {
                idx++;
                continue;
            }

            ITestStakeManager(address(stakeManager)).claimWithdrawFor(address(strategy), idx);
        }

        assertEq(0, address(user).balance, "user balance");
        strategy.claimNextBatchAndDistribute(50);
        assertEq(89 ether, address(user).balance, "user balance");
    }
}
