pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "../../contracts/psm/ListaAdapter.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract ListaAdapterTest is Test {
  ListaAdapter listaAdapter;
  address admin = address(0x10);
  address user1 = address(0x004319Fd76912890F7920aEE99Df27EBA05ef48D);
  address USDC = 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d;

  function setUp() public {
    vm.createSelectFork("bsc-main");

    vm.deal(admin, 100 ether);
    vm.deal(user1, 100 ether);

    vm.startPrank(admin);
    ListaAdapter listaAdapterImpl = new ListaAdapter();

    ERC1967Proxy listaAdapterProxy = new ERC1967Proxy(
      address(listaAdapterImpl),
      abi.encodeWithSelector(listaAdapterImpl.initialize.selector, admin, admin, user1, USDC)
    );

    listaAdapter = ListaAdapter(address(listaAdapterProxy));

    vm.stopPrank();
  }

  function test_depositAndWithdraw() public {
    deal(USDC, user1, 200 ether);

    vm.startPrank(user1);
    IERC20(USDC).approve(address(listaAdapter), 100 ether);
    listaAdapter.deposit(100 ether);
    vm.stopPrank();

    uint256 adapterUSDCBalance = IERC20(USDC).balanceOf(address(listaAdapter));
    assertEq(adapterUSDCBalance, 100 ether, "Staked USDC 0 error");

    vm.startPrank(user1);
    listaAdapter.withdraw(user1, 100 ether);
    vm.stopPrank();

    uint256 userUSDCBalance = IERC20(USDC).balanceOf(user1);
    assertEq(userUSDCBalance, 200 ether, "user1 USDC 1 error");

    adapterUSDCBalance = IERC20(USDC).balanceOf(address(listaAdapter));
    assertEq(adapterUSDCBalance, 0 ether, "Staked USDC 1 error");
  }

  function test_withdrawAll() public {
    deal(USDC, user1, 1000 ether);

    uint256 USDCBalance = IERC20(USDC).balanceOf(user1);
    assertEq(USDCBalance, 1000 ether, "user1 USDC 0 error");

    vm.startPrank(user1);
    IERC20(USDC).approve(address(listaAdapter), 100 ether);
    listaAdapter.deposit(100 ether);

    listaAdapter.withdrawAll();
    vm.stopPrank();

    USDCBalance = IERC20(USDC).balanceOf(user1);
    assertEq(USDCBalance, 1000 ether, "user1 USDC 1 error");
  }

  function test_initialize() public {
    address zero = address(0x0);

    ListaAdapter listaAdapterImpl = new ListaAdapter();

    vm.expectRevert("admin cannot be zero address");
    new ERC1967Proxy(
      address(listaAdapterImpl),
      abi.encodeWithSelector(listaAdapterImpl.initialize.selector, zero, admin, admin, USDC)
    );

    vm.expectRevert("manager cannot be zero address");
    new ERC1967Proxy(
      address(listaAdapterImpl),
      abi.encodeWithSelector(listaAdapterImpl.initialize.selector, admin, zero, admin, USDC)
    );

    vm.expectRevert("vaultManager cannot be zero address");
    new ERC1967Proxy(
      address(listaAdapterImpl),
      abi.encodeWithSelector(listaAdapterImpl.initialize.selector, admin, admin, zero, USDC)
    );

    vm.expectRevert("token cannot be zero address");
    new ERC1967Proxy(
      address(listaAdapterImpl),
      abi.encodeWithSelector(listaAdapterImpl.initialize.selector, admin, admin, admin, zero)
    );
  }
}
