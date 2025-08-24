// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.29;

/// @title Uniswap V2 Router02 (minimal)
/// @notice Interface for performing ERC‑20 to ERC‑20 token swaps on Uniswap V2-like routers.
/// @dev This minimal subset only exposes {swapExactTokensForTokens}.
///      Caller must have approved the router to spend `amountIn` of the input token before calling.
interface IUniswapV2Router02 {
    /**
     * @notice Swap an exact amount of input tokens for as many output tokens as possible,
     *         along the specified path, ensuring at least `amountOutMin` are received.
     * @dev The caller must pre‑approve `amountIn` of the first token in `path` to the router.
     *      Swaps proceed sequentially along `path`. The final output is sent to `to`.
     * @param amountIn The exact amount of input tokens to swap.
     * @param amountOutMin The minimum acceptable amount of the final output token.
     * @param path The ordered list of token addresses: path[0] = input token, path[path.length‑1] = output token.
     * @param to The recipient of the output tokens.
     * @param deadline Unix timestamp after which the transaction will revert if not yet executed.
     * @return amounts The input and output amounts for each hop in the path; amounts[0] = amountIn, amounts[amounts.length‑1] = final output.
     */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}
