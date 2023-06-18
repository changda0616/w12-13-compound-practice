pragma solidity 0.8.19;
import "forge-std/Test.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";
import "compound-protocol/contracts/CErc20Delegator.sol";
import {IFlashLoanSimpleReceiver, IPoolAddressesProvider, IPool} from "aave-v3-core/contracts/flashloan/interfaces/IFlashLoanSimpleReceiver.sol";
import {ISwapRouter} from "v3-periphery/interfaces/ISwapRouter.sol";

// TODO: Inherit IFlashLoanSimpleReceiver
contract AaveFlashLoan is IFlashLoanSimpleReceiver {
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant Uni = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;

    address constant POOL_ADDRESSES_PROVIDER =
        0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;
    address payable cUSDC;
    address payable cUni;
    address liquidatee;

    function executeOperation(
        address assets,
        uint256 amounts,
        uint256 premiums,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {

        IERC20(USDC).approve(address(cUSDC), amounts);
        uint result = CErc20Delegator(cUSDC).liquidateBorrow(
            liquidatee,
            amounts,
            CErc20Delegator(cUni)
        );

        require(result == 0);
        uint balance = IERC20(cUni).balanceOf(address(this));
        IERC20(cUni).approve(address(cUni), balance);
        CErc20Delegator(cUni).redeem(balance);

        ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: Uni,
                tokenOut: USDC,
                fee: 3000, // 0.3%
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: IERC20(Uni).balanceOf(address(this)),
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
        uint256 amountOut = swapRouter.exactInputSingle(swapParams);
        IERC20(USDC).approve(msg.sender, amount + premiums);
        return true;
    }

    function execute(
        address _liquidatee,
        uint256 flashAmount,
        address payable _cUSDCAddress,
        address payable _cUni
    ) external {
        // TODO
        cUSDC = _cUSDCAddress;
        cUni = _cUni;
        liquidatee = _liquidatee;
        IPool pool = POOL();
        IERC20(USDC).approve(
            address(pool),
            2500 * 10 ** ERC20(USDC).decimals()
        );
        pool.flashLoanSimple(
            address(this),
            address(USDC),
            flashAmount,
            bytes(""),
            0
        );
    }

    function ADDRESSES_PROVIDER() public view returns (IPoolAddressesProvider) {
        return IPoolAddressesProvider(POOL_ADDRESSES_PROVIDER);
    }

    function POOL() public view returns (IPool) {
        return IPool(ADDRESSES_PROVIDER().getPool());
    }
}
