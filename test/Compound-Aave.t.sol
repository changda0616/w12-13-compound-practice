// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../script/DeployComp.s.sol";
import "../src/TestErc20.sol";
import "openzeppelin/token/ERC20/ERC20.sol";

import "../src/AaveFlashLoan.sol";

import {IFlashLoanSimpleReceiver, IPoolAddressesProvider, IPool} from "aave-v3-core/contracts/flashloan/interfaces/IFlashLoanSimpleReceiver.sol";

contract CompoundTest is Test, DeployComp {
    Unitroller unitroller;
    Comptroller comptroller;
    Comptroller comptrollerProxy;

    SimplePriceOracle priceOracle;
    WhitePaperInterestRateModel whitePaperInterestRateModel;
    CErc20Delegate cErc20Delegate;

    CErc20Delegator cSai;
    CErc20Delegator cUSDC;
    CErc20Delegator cUni;

    AaveFlashLoan public liquidator;

    address constant POOL_ADDRESSES_PROVIDER =
        0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;

    ERC20 USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 Uni = ERC20(0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984);

    uint256 collateralAmount = 1 * 1e18;
    uint256 tokenBPrice = 100 * 1e18;

    address public admin = vm.envAddress("wallet");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");

    function setUp() public {
        string memory rpc = vm.envString("MAINNET_RPC_URL");
        vm.createSelectFork(rpc, 17465000);
        assertEq(block.number, 17465000);

        (
            unitroller,
            comptroller,
            priceOracle,
            whitePaperInterestRateModel,
            cErc20Delegate,

        ) = run();

        comptrollerProxy = Comptroller(address(unitroller));

        vm.startPrank(admin);
        uint8 cTokenDecimals = 18;
        uint8 usdcDecimals = USDC.decimals();
        uint8 uniDecimals = Uni.decimals();
        uint8 cUsdcExchangeRateDecimals = 18 - cTokenDecimals + usdcDecimals;
        uint8 cUniExchangeRateDecimals = 18 - cTokenDecimals + uniDecimals;
        CErc20Delegate cErc20DelegateUSDC = new CErc20Delegate();
        CErc20Delegate cErc20DelegateUni = new CErc20Delegate();

        cUSDC = new CErc20Delegator(
            address(USDC),
            ComptrollerInterface(address(unitroller)),
            InterestRateModel(address(whitePaperInterestRateModel)),
            1 * 10 ** cUsdcExchangeRateDecimals,
            "Compound USDC",
            "cUSDC",
            usdcDecimals,
            payable(admin),
            address(cErc20DelegateUSDC),
            ""
        );
        cUni = new CErc20Delegator(
            address(Uni),
            ComptrollerInterface(address(unitroller)),
            InterestRateModel(address(whitePaperInterestRateModel)),
            1 * 10 ** cUniExchangeRateDecimals,
            "Compound Uni",
            "cUni",
            uniDecimals,
            payable(admin),
            address(cErc20DelegateUni),
            ""
        );

        // Add cSai to unitroller's markets map
        comptrollerProxy._supportMarket(CToken(address(cUSDC)));
        comptrollerProxy._supportMarket(CToken(address(cUni)));

        uint8 cUSDCPriceDecimals = 18 - usdcDecimals + 18; // 30
        uint8 cUniPriceDecimals = 18 - uniDecimals + 18; // 18
        // The borrower can only borrow 70% of the collateral value
        priceOracle.setUnderlyingPrice(
            CToken(address(cUSDC)),
            1 * 10 ** cUSDCPriceDecimals
        );
        priceOracle.setUnderlyingPrice(
            CToken(address(cUni)),
            5 * 10 ** cUniPriceDecimals
        );

        assertEq(
            comptrollerProxy._setCollateralFactor(
                CToken(address(cUni)),
                0.5 * 1e18
            ),
            0
        );

        assertEq(
            priceOracle.getUnderlyingPrice(CToken(address(cUSDC))),
            1 * 10 ** cUSDCPriceDecimals
        );
        assertEq(
            priceOracle.getUnderlyingPrice(CToken(address(cUni))),
            5 * 10 ** cUniPriceDecimals
        );

        deal(address(Uni), user1, 1000 * 10 ** uniDecimals);

        deal(address(USDC), address(cUSDC), 2500 * 10 ** usdcDecimals);

        vm.stopPrank();
    }

    function ADDRESSES_PROVIDER() public view returns (IPoolAddressesProvider) {
        return IPoolAddressesProvider(POOL_ADDRESSES_PROVIDER);
    }

    function POOL() public view returns (IPool) {
        return IPool(ADDRESSES_PROVIDER().getPool());
    }

    function testAaveLiquidate() public {
        //  mint 1000 uni
        vm.startPrank(user1);
        uint8 cTokenDecimals = 18;
        uint8 usdcDecimals = USDC.decimals();
        uint8 uniDecimals = Uni.decimals();
        uint256 uniMintAmount = 1000 * 10 ** uniDecimals;
        Uni.approve(address(cUni), uniMintAmount);
        // check mint success
        assertEq(cUni.mint(uniMintAmount), 0);
        assertEq(Uni.balanceOf(user1), 0);
        assertEq(cUni.balanceOf(user1), uniMintAmount);

        // borrow 2500 USDC
        address[] memory tokenAddr = new address[](1);
        tokenAddr[0] = address(cUni);
        comptrollerProxy.enterMarkets(tokenAddr);

        (, uint liquidity, ) = comptrollerProxy.getAccountLiquidity(user1);

        assertEq(cUSDC.borrow(2500 * 10 ** usdcDecimals), 0);
        assertEq(USDC.balanceOf(user1), 2500 * 10 ** usdcDecimals);
        (, uint liquidityAfterBorrow, ) = comptrollerProxy.getAccountLiquidity(
            user1
        );
        // Should be no liquidity left
        assertEq(liquidityAfterBorrow, 0);

        // Change the price
        changePrank(admin);
        priceOracle.setUnderlyingPrice(
            CToken(address(cUni)),
            4 * 10 ** uniDecimals
        );

        (, , uint shortFall) = comptrollerProxy.getAccountLiquidity(user1);

        assertEq(
            shortFall,
            (1000 * 10 ** uniDecimals * (5 - 4) * 5) / 10 // token price drop from 100 -> 50, collateral factor is 0.5
        );

        changePrank(user2);
        IPool pool = POOL();
        uint256 flashAmount = 0.5 * 2500 * 10 ** usdcDecimals;
        liquidator = new AaveFlashLoan();

        liquidator.execute(
            user1,
            flashAmount,
            payable(address(cUSDC)),
            payable(address(cUni))
        );

        assertGt(USDC.balanceOf(address(liquidator)), 63 * 10 ** usdcDecimals);
    }
}
