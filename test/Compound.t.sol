// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../script/DeployComp.s.sol";
import "../src/TestErc20.sol";

contract CompoundTest is Test, DeployComp {
    Unitroller unitroller;
    Comptroller comptroller;
    Comptroller comptrollerProxy;

    SimplePriceOracle priceOracle;
    WhitePaperInterestRateModel whitePaperInterestRateModel;
    CErc20Delegate cErc20Delegate;

    CErc20Delegator cSai;
    CErc20Delegator cTokenA;
    CErc20Delegator cTokenB;

    TestErc20 sai;
    TestErc20 tokenA;
    TestErc20 tokenB;

    uint256 collateralAmount = 1 * 1e18;
    uint256 tokenBPrice = 100 * 1e18;

    address public admin = vm.envAddress("wallet");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");

    function setUp() public {
        (
            unitroller,
            comptroller,
            priceOracle,
            whitePaperInterestRateModel,
            cErc20Delegate,
            cSai
        ) = run();
        sai = TestErc20(cSai.underlying());
        comptrollerProxy = Comptroller(address(unitroller));

        vm.startPrank(admin);
        tokenA = new TestErc20("Token A", "tokenA");
        tokenB = new TestErc20("Token B", "tokenB");
        CErc20Delegate cErc20DelegateA = new CErc20Delegate();
        CErc20Delegate cErc20DelegateB = new CErc20Delegate();
        cTokenA = new CErc20Delegator(
            address(tokenA),
            ComptrollerInterface(address(unitroller)),
            InterestRateModel(address(whitePaperInterestRateModel)),
            1 * 1e18,
            "Compound TokenA",
            "cTokenA",
            18,
            payable(admin),
            address(cErc20DelegateA),
            ""
        );
        cTokenB = new CErc20Delegator(
            address(tokenB),
            ComptrollerInterface(address(unitroller)),
            InterestRateModel(address(whitePaperInterestRateModel)),
            1 * 1e18,
            "Compound TokenB",
            "cTokenB",
            18,
            payable(admin),
            address(cErc20DelegateB),
            ""
        );

        // Add cSai to unitroller's markets map
        comptrollerProxy._supportMarket(CToken(address(cTokenA)));
        comptrollerProxy._supportMarket(CToken(address(cTokenB)));

        // The borrower can only borrow 70% of the collateral value

        priceOracle.setUnderlyingPrice(CToken(address(cTokenA)), 1e18);
        priceOracle.setUnderlyingPrice(CToken(address(cTokenB)), tokenBPrice);

        assertEq(
            comptrollerProxy._setCollateralFactor(
                CToken(address(cTokenB)),
                0.5 * 1e18
            ),
            0
        );

        assertEq(
            priceOracle.getUnderlyingPrice(CToken(address(cTokenA))),
            1e18
        );
        assertEq(
            priceOracle.getUnderlyingPrice(CToken(address(cTokenB))),
            tokenBPrice
        );

        uint256 tokenASupplyAmount = 10000 * 1 * 1e18;

        // admin supply tokenA
        tokenA.mint(admin, tokenASupplyAmount);
        tokenA.approve(address(cTokenA), tokenASupplyAmount);
        cTokenA.mint(tokenASupplyAmount);

        // Give user1 some tokenB
        tokenB.mint(user1, collateralAmount);
        // Give user1 some tokenB, (100/1) * 0.5 * 1e18
        tokenA.mint(user2, 50 * 1e18);
        vm.stopPrank();
    }

    function testMintAndRedeem() public {
        uint256 mintAmount = 100 * 10 ** sai.decimals();
        vm.startPrank(admin);
        sai.mint(user1, mintAmount);

        changePrank(user1);

        sai.approve(address(cSai), mintAmount);
        cSai.mint(mintAmount);
        // After mint, user1 should have 100 cSai, 0 Sai, and totalSupply of cSai should be 100
        assertEq(cSai.balanceOf(user1), mintAmount);
        assertEq(sai.balanceOf(user1), 0);
        assertEq(cSai.totalSupply(), mintAmount);

        cSai.approve(address(cSai), mintAmount);
        cSai.redeem(mintAmount);
        // After redeem, user1 should have 0 cSai, 100 Sai, and totalSupply of cSai should be 0
        assertEq(cSai.balanceOf(user1), 0);
        assertEq(sai.balanceOf(user1), mintAmount);
        assertEq(cSai.totalSupply(), 0);
    }

    function testBorrowAndRepay() public {
        vm.startPrank(user1);
        // user1 mint cTokenB
        tokenB.approve(address(cTokenB), collateralAmount);
        cTokenB.mint(collateralAmount);

        // check the cTokenB, tokenB balance of user1
        assertEq(tokenB.balanceOf(user1), 0);
        assertEq(cTokenB.balanceOf(user1), collateralAmount);

        address[] memory tokenAddr = new address[](1);
        tokenAddr[0] = address(cTokenB);
        comptrollerProxy.enterMarkets(tokenAddr);
        // User 1 borrow token A
        // cTokenB.approve(address(cTokenA), collateralAmount);
        (, uint liquidityBeforeBorrow, ) = comptrollerProxy.getAccountLiquidity(
            user1
        );

        uint256 borrowTokenAAmomut = 50 * 1e18;
        assertEq(liquidityBeforeBorrow, borrowTokenAAmomut);

        assertEq(cTokenA.borrow(borrowTokenAAmomut), 0);
        (, uint liquidityAfterBorrow, ) = comptrollerProxy.getAccountLiquidity(
            user1
        );
        assertEq(liquidityAfterBorrow, 0);

        assertEq(tokenA.balanceOf(user1), borrowTokenAAmomut);

        // User 1 repay token A
        tokenA.approve(address(cTokenA), borrowTokenAAmomut);
        assertEq(cTokenA.repayBorrow(borrowTokenAAmomut), 0);
        assertEq(tokenA.balanceOf(user1), 0);
        (, uint liquidityAfterRepay, ) = comptrollerProxy.getAccountLiquidity(
            user1
        );
        assertEq(liquidityAfterRepay, borrowTokenAAmomut);
    }

    function testModifyCollateralFactorAndGetLiquidated() public {
        vm.startPrank(user1);
        // user1 mint cTokenB
        tokenB.approve(address(cTokenB), collateralAmount);
        cTokenB.mint(collateralAmount);

        // check the cTokenB, tokenB balance of user1
        assertEq(tokenB.balanceOf(user1), 0);
        assertEq(cTokenB.balanceOf(user1), collateralAmount);

        address[] memory tokenAddr = new address[](1);
        tokenAddr[0] = address(cTokenB);
        comptrollerProxy.enterMarkets(tokenAddr);

        // User 1 borrow token A
        (, uint liquidityBeforeBorrow, ) = comptrollerProxy.getAccountLiquidity(
            user1
        );

        uint256 borrowTokenAAmomut = 50 * 1e18;
        assertEq(liquidityBeforeBorrow, borrowTokenAAmomut);

        assertEq(cTokenA.borrow(borrowTokenAAmomut), 0);
        assertEq(tokenA.balanceOf(user1), borrowTokenAAmomut);
        (, uint liquidityAfterBorrow, ) = comptrollerProxy.getAccountLiquidity(
            user1
        );
        changePrank(admin);
        assertEq(
            comptrollerProxy._setCollateralFactor(
                CToken(address(cTokenB)),
                0.3 * 1e18
            ),
            0
        );
        (
            ,
            uint liquidityAfterModifyCF,
            uint shortFallAfterModifyCF
        ) = comptrollerProxy.getAccountLiquidity(user1);

        assertEq(liquidityAfterModifyCF, 0);
        assertEq(
            shortFallAfterModifyCF,
            (tokenBPrice * 2) / 10 // At first, the collateral factor was 0.5, and it becomes 0.3 now
        );
        changePrank(user2);
        assertEq(tokenA.balanceOf(user2), 50 * 1e18);
        // Debt： 50 tokenA, close factor 60%
        tokenA.approve(address(cTokenA), 0.6 * 50 * 1e18);
        assertEq(cTokenA.liquidateBorrow(user1, 0.6 * 50 * 1e18, cTokenB), 0);

        // Debt： 50 tokenA -> 20 tokenA
        // liquidationIncentive = 30 * 1.08 = 32.4 tokenA value -> 0.324 cTokenB
        // protocolSeizeShareMantissa -> 2.8%
        // liquidators get: 0.324 * (1-0.028) = .314928 cTokenB
        // protocaol get reserve: 0.324 * 0.028 = 0.009072 cTokenB
        assertEq(tokenA.balanceOf(user2), 20 * 1e18);
        assertEq(cTokenB.balanceOf(user2), 0.314928 * 1e18);
        assertEq(cTokenB.totalReserves(), 0.009072 * 1e18);

        (, uint liquidityAfterLiq, uint shortFallAfterLiq) = comptrollerProxy
            .getAccountLiquidity(user1);

        // left collateral: (1 - 0.324) = 0.676 cTokenB, equal to 0.676 * 100 = 67.6 tokenA
        // can borrow 67.6 * 0.3 (collateral factor) = 20.28 tokenA
        // left debt: 20 tokenA
        // liquidityAfterLiq, 20.28 - 20 = 0.28 tokenA
        assertEq(shortFallAfterLiq, 0);
        assertEq(liquidityAfterLiq, 0.28 * 1e18);
    }

    function testModifyCollateralPriceAndGetLiquidated() public {
        vm.startPrank(user1);
        // user1 mint cTokenB
        tokenB.approve(address(cTokenB), collateralAmount);
        cTokenB.mint(collateralAmount);

        // check the cTokenB, tokenB balance of user1
        assertEq(tokenB.balanceOf(user1), 0);
        assertEq(cTokenB.balanceOf(user1), collateralAmount);

        address[] memory tokenAddr = new address[](1);
        tokenAddr[0] = address(cTokenB);
        comptrollerProxy.enterMarkets(tokenAddr);
        // User 1 borrow token A

        (, uint liquidityBeforeBorrow, ) = comptrollerProxy.getAccountLiquidity(
            user1
        );

        uint256 borrowTokenAAmomut = 50 * 1e18;
        assertEq(liquidityBeforeBorrow, borrowTokenAAmomut);

        assertEq(cTokenA.borrow(borrowTokenAAmomut), 0);

        changePrank(admin);
        uint256 tokenBNewPrice = 50 * 1e18;
        priceOracle.setUnderlyingPrice(
            CToken(address(cTokenB)),
            tokenBNewPrice
        );

        assertEq(
            priceOracle.getUnderlyingPrice(CToken(address(cTokenB))),
            tokenBNewPrice
        );
        (
            ,
            uint liquidityAfterPriceDrop,
            uint shortFallAfterPriceDrop
        ) = comptrollerProxy.getAccountLiquidity(user1);

        assertEq(liquidityAfterPriceDrop, 0);
        assertEq(
            shortFallAfterPriceDrop,
            ((tokenBPrice - tokenBNewPrice) * 5) / 10 // token price drop from 100 -> 50, collateral factor is 0.5
        );
        changePrank(user2);
        assertEq(tokenA.balanceOf(user2), 50 * 1e18);
        // Debt： 50 tokenA, close factor 60%
        tokenA.approve(address(cTokenA), 0.6 * 50 * 1e18);
        assertEq(cTokenA.liquidateBorrow(user1, 0.6 * 50 * 1e18, cTokenB), 0);

        // Debt： 50 tokenA -> 20 tokenA
        // liquidationIncentive = 30 * 1.08 = 32.4 tokenA value -> 32.4 / 50 = 0.648 cTokenB
        // protocolSeizeShareMantissa -> 2.8%
        // liquidators get: 0.648 * (1-0.028) = 0.629856
        // protocaol get reserve: 0.648 * 0.028 = 0.018144
        assertEq(tokenA.balanceOf(user2), 20 * 1e18);
        assertEq(cTokenB.balanceOf(user2), 0.629856 * 1e18);
        assertEq(cTokenB.totalReserves(), 0.018144 * 1e18);

        (, uint liquidityAfterLiq, uint shortFallAfterLiq) = comptrollerProxy
            .getAccountLiquidity(user1);

        // left collateral: (1 - 0.648) = 0.352 cTokenB, equal to 17.6 tokenA
        // can borrow 17.6 * 0.5 (collateral factor) = 8.8 tokenA
        // left debt: 20 tokenA
        // shortFallAfterLiq: 20 - 8.8 = 11.2 tokenA

        assertEq(shortFallAfterLiq, 11.2 * 1e18);
        assertEq(liquidityAfterLiq, 0);
    }
}
