pragma solidity 0.8.19;
import "forge-std/Test.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";
import "compound-protocol/contracts/CErc20Delegator.sol";
import {IFlashLoanSimpleReceiver, IPoolAddressesProvider, IPool} from "aave-v3-core/contracts/flashloan/interfaces/IFlashLoanSimpleReceiver.sol";

interface IUniswapV3SwapCallback {
    /// @notice Called to `msg.sender` after executing a swap via IUniswapV3Pool#swap.
    /// @dev In the implementation you must pay the pool tokens owed for the swap.
    /// The caller of this method must be checked to be a UniswapV3Pool deployed by the canonical UniswapV3Factory.
    /// amount0Delta and amount1Delta can both be 0 if no tokens were swapped.
    /// @param amount0Delta The amount of token0 that was sent (negative) or must be received (positive) by the pool by
    /// the end of the swap. If positive, the callback must send that amount of token0 to the pool.
    /// @param amount1Delta The amount of token1 that was sent (negative) or must be received (positive) by the pool by
    /// the end of the swap. If positive, the callback must send that amount of token1 to the pool.
    /// @param data Any data passed through by the caller via the IUniswapV3PoolActions#swap call
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external;
}

interface ISwapRouter is IUniswapV3SwapCallback {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Swaps `amountIn` of one token for as much as possible of another token
    /// @param params The parameters necessary for the swap, encoded as `ExactInputSingleParams` in calldata
    /// @return amountOut The amount of the received token
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);

    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    /// @notice Swaps `amountIn` of one token for as much as possible of another along the specified path
    /// @param params The parameters necessary for the multi-hop swap, encoded as `ExactInputParams` in calldata
    /// @return amountOut The amount of the received token
    function exactInput(ExactInputParams calldata params) external payable returns (uint256 amountOut);

    struct ExactOutputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountOut;
        uint256 amountInMaximum;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Swaps as little as possible of one token for `amountOut` of another token
    /// @param params The parameters necessary for the swap, encoded as `ExactOutputSingleParams` in calldata
    /// @return amountIn The amount of the input token
    function exactOutputSingle(ExactOutputSingleParams calldata params) external payable returns (uint256 amountIn);

    struct ExactOutputParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountOut;
        uint256 amountInMaximum;
    }

    /// @notice Swaps as little as possible of one token for `amountOut` of another along the specified path (reversed)
    /// @param params The parameters necessary for the multi-hop swap, encoded as `ExactOutputParams` in calldata
    /// @return amountIn The amount of the input token
    function exactOutput(ExactOutputParams calldata params) external payable returns (uint256 amountIn);
}



// TODO: Inherit IFlashLoanSimpleReceiver
contract AaveFlashLoan is IFlashLoanSimpleReceiver {
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant Uni = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
    address constant router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
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
        
        IERC20(Uni).approve(router, IERC20(Uni).balanceOf(address(this)));
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
        uint256 amountOut = ISwapRouter(router).exactInputSingle(swapParams);

        IERC20(USDC).approve(msg.sender, amounts + premiums);
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
