// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IFlashLoanReceiver} from "./interfaces/IFlashLoanReceiver.sol";
import {ILendingPool} from "./interfaces/ILendingPool.sol";
import {IUniswapV2Router02} from "./interfaces/IUniswapV2Router02.sol";
import {ILendingPoolAddressesProvider} from "./interfaces/ILendingPoolAddressProvider.sol";
import {IWETH} from "./interfaces/IWETH.sol";

/// @title Optimized Arbitrage Executor
/// @notice Executes two‑leg DEX arbitrage using an Aave V2 flash loan, with slippage and profit safeguards.
/// @dev Uses Aave V2 `flashLoan` and UniswapV2‑style routers for swaps. Only single‑asset flash loans are supported.
/// @custom:security-contact Set the owner to a trusted EOA or multisig. Review whitelist and provider addresses before use on mainnet.
contract FlashArbMainnetReady is IFlashLoanReceiver, ReentrancyGuardTransient, Pausable, Ownable {
    using SafeERC20 for IERC20;

    /// @notice Common mainnet addresses used by default (verify prior to deployment).
    /// @dev These constants are for Ethereum mainnet Aave V2, Uniswap V2, SushiSwap, WETH, DAI, and USDC.
    address public constant AAVE_PROVIDER = 0xB53C1a33016B2DC2fF3653530bfF1848a515c8c5;
    address public constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant SUSHISWAP_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    /// @notice Aave addresses provider used to resolve the current LendingPool.
    /// @dev Owner can update this via {updateProvider} when Aave migrates infra.
    ILendingPoolAddressesProvider public provider;
    /// @notice Cached Aave LendingPool address resolved from {provider}.
    address public lendingPool;

    /// @notice Whitelist of approved UniswapV2‑compatible routers.
    /// @dev Only routers marked true can be used for swaps in {executeOperation}.
    mapping(address => bool) public routerWhitelist;

    /// @notice Whitelist of ERC‑20 tokens allowed in swap paths.
    /// @dev All tokens in both swap paths must be whitelisted.
    mapping(address => bool) public tokenWhitelist;

    /// @notice Accumulated realized profits per ERC‑20 token.
    /// @dev Increased after a successful flash loan cycle and decreased on {withdrawProfit}.
    mapping(address => uint256) public profits;

    /// @notice Accumulated realized profits in native ETH (unwrapped WETH).
    uint256 public ethProfits;

    /// @notice Maximum tolerated slippage expressed in basis points (default 200 = 2%).
    /// @dev Used as informational guidance; callers must still pass `amountOutMin` values.
    uint256 public maxSlippageBps = 200;

    /// @notice Emitted when a flash loan request is initiated.
    /// @param initiator The transaction sender (contract owner).
    /// @param asset The reserve token borrowed.
    /// @param amount The amount requested for the flash loan.
    event FlashLoanRequested(address indexed initiator, address asset, uint256 amount);

    /// @notice Emitted after completing the flash loan and swaps.
    /// @param initiator The indicated operator decoded from params.
    /// @param asset The reserve token borrowed and repaid.
    /// @param amount The borrowed principal.
    /// @param fee The Aave flash loan fee.
    /// @param profit The net profit in `asset` units realized by this operation.
    event FlashLoanExecuted(address indexed initiator, address asset, uint256 amount, uint256 fee, uint256 profit);

    /// @notice Emitted when a router is added to or removed from the whitelist.
    /// @param router The router address.
    /// @param allowed True if whitelisted, false if removed.
    event RouterWhitelisted(address router, bool allowed);

    /// @notice Emitted when a token is added to or removed from the whitelist.
    /// @param token The token address.
    /// @param allowed True if whitelisted, false if removed.
    event TokenWhitelisted(address token, bool allowed);

    /// @notice Emitted when the Aave addresses provider (and LendingPool) is updated.
    /// @param provider The new addresses provider.
    /// @param lendingPool The resolved LendingPool from the provider.
    event ProviderUpdated(address provider, address lendingPool);

    /// @notice Emitted when profits or rescued funds are withdrawn.
    /// @param token Zero address for ETH, or the ERC‑20 token withdrawn.
    /// @param to The recipient of the withdrawal.
    /// @param amount The amount transferred.
    event Withdrawn(address token, address to, uint256 amount);

    /// @dev Reverts when a zero provider address is supplied.
    error ProviderZero();
    /// @dev Reverts when owner sets slippage above the hard cap.
    error MaxSlippageExceeded(uint256 maxAllowed, uint256 actual);
    /// @dev Reverts when a required amount argument equals zero.
    error AmountZero();
    /// @dev Reverts if a non‑LendingPool caller invokes {executeOperation}.
    error OnlyLendingPool(address sender, address pool);
    /// @dev Reverts unless arrays for assets/amounts/premiums are all length 1.
    error OnlySingleAssetSupported(uint256 assetsLength, uint256 amountsLength, uint256 premiumsLength);
    /// @dev Reverts when either swap router is not whitelisted.
    error RouterNotAllowed(address router1, address router2);
    /// @dev Reverts when provided swap paths have insufficient length.
    error InvalidPathLength(uint256 path1Length, uint256 path2Length);
    /// @dev Reverts when the first path does not start with the reserve asset.
    error InvalidPath1Start(address pathStart, address expected);
    /// @dev Reverts when the second path does not end with the reserve asset.
    error InvalidPath2End(address pathEnd, address expected);
    /// @dev Reverts when a token inside any path is not whitelisted.
    error TokenNotWhitelisted(address token);
    /// @dev Reverts when the second path does not start with the intermediate token.
    error InvalidPath2Start(address pathStart, address expected);
    /// @dev Reverts if post‑swap balance is insufficient to repay principal + fee.
    error InsufficientToRepay(uint256 balance, uint256 totalDebt);
    /// @dev Reverts when realized profit is less than the specified minimum.
    error LessThanMinProfit(uint256 profit, uint256 minProfit);
    /// @dev Reverts on zero amount in withdrawal functions.
    error ZeroAmountWithdraw();
    /// @dev Reverts on zero recipient address in withdrawal functions.
    error ZeroAddressWithdraw();
    /// @dev Reverts if requested withdrawal exceeds recorded profits.
    error InsufficientProfit(uint256 available, uint256 requested);
    /// @dev Reverts if native transfer fails during ETH withdrawal.
    error WithdrawFailed(address to, uint256 amount);

    /// @notice Initializes the contract with default whitelists and resolves Aave LendingPool.
    /// @dev Sets the deployer as the initial owner. Pre‑whitelists UniswapV2 and SushiSwap routers and common tokens.
    constructor() Ownable(msg.sender) {
        provider = ILendingPoolAddressesProvider(AAVE_PROVIDER);
        lendingPool = provider.getLendingPool();

        // Prepopulate trusted routers
        routerWhitelist[UNISWAP_V2_ROUTER] = true;
        routerWhitelist[SUSHISWAP_ROUTER] = true;
        emit RouterWhitelisted(UNISWAP_V2_ROUTER, true);
        emit RouterWhitelisted(SUSHISWAP_ROUTER, true);

        // Prepopulate common tokens
        tokenWhitelist[WETH] = true;
        tokenWhitelist[DAI] = true;
        tokenWhitelist[USDC] = true;
        emit TokenWhitelisted(WETH, true);
        emit TokenWhitelisted(DAI, true);
        emit TokenWhitelisted(USDC, true);
    }

    /// @notice Add or remove a UniswapV2‑compatible router from the whitelist.
    /// @param router The router address to update.
    /// @param allowed Pass true to allow, false to revoke.
    /// @custom:access Only owner.
    function setRouterWhitelist(address router, bool allowed) external onlyOwner {
        routerWhitelist[router] = allowed;
        emit RouterWhitelisted(router, allowed);
    }

    /// @notice Add or remove a token from the swap path whitelist.
    /// @param token The ERC‑20 token address to update.
    /// @param allowed Pass true to allow, false to revoke.
    /// @custom:access Only owner.
    function setTokenWhitelist(address token, bool allowed) external onlyOwner {
        tokenWhitelist[token] = allowed;
        emit TokenWhitelisted(token, allowed);
    }

    /// @notice Update the Aave addresses provider and refresh the cached LendingPool.
    /// @param _provider The new Aave `ILendingPoolAddressesProvider` address.
    /// @custom:access Only owner.
    /// @custom:error {ProviderZero} If `_provider` is the zero address.
    function updateProvider(address _provider) external onlyOwner {
        if (_provider == address(0)) revert ProviderZero();
        provider = ILendingPoolAddressesProvider(_provider);
        lendingPool = provider.getLendingPool();
        emit ProviderUpdated(_provider, lendingPool);
    }

    /// @notice Set the maximum acceptable slippage in basis points.
    /// @param bps New slippage limit (e.g., 200 = 2%).
    /// @custom:access Only owner.
    /// @custom:error {MaxSlippageExceeded} If `bps` exceeds the hard cap (1000 bps).
    function setMaxSlippage(uint256 bps) external onlyOwner {
        if (bps > 1000) revert MaxSlippageExceeded(bps, 1000);
        maxSlippageBps = bps;
    }

    /// @notice Initiates a single‑asset flash loan from Aave V2.
    /// @param asset The ERC‑20 reserve to borrow (e.g., WETH).
    /// @param amount The principal amount to borrow.
    /// @param params ABI‑encoded parameters consumed in {executeOperation}.
    /// @custom:access Only owner.
    /// @custom:requirements The contract must hold enough balance post‑swaps to repay `amount + fee`.
    /// @custom:emits {FlashLoanRequested}
    /// @custom:error {AmountZero} If `amount` is zero.
    function startFlashLoan(address asset, uint256 amount, bytes calldata params) external onlyOwner whenNotPaused {
        if (amount == 0) revert AmountZero();
        address[] memory assets = new address[](1);
        assets[0] = asset;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        uint256[] memory modes = new uint256[](1);
        modes[0] = 0; // 0 = no debt (flash)

        emit FlashLoanRequested(msg.sender, asset, amount);
        ILendingPool(lendingPool).flashLoan(address(this), assets, amounts, modes, address(this), params, 0);
    }

    /// @inheritdoc IFlashLoanReceiver
    /// @notice Callback invoked by Aave after the flash loan is granted.
    /// @dev Performs two swaps across `router1` and `router2` with validated paths, then repays principal + fee.
    ///      Expects single‑asset arrays from Aave. Uses SafeERC20 forceApprove to manage allowances.
    /// @param assets The array with a single borrowed asset address.
    /// @param amounts The array with a single borrowed amount.
    /// @param premiums The array with a single fee amount.
    /// @param params ABI‑encoded tuple `(router1, router2, path1, path2, amountOutMin1, amountOutMin2, minProfit, unwrapProfitToEth, opInitiator)`.
    /// @return success True if the operation completed and approval for repayment was set (required by Aave LendingPool).
    /// @custom:error {OnlyLendingPool} If called by anyone except the configured LendingPool.
    /// @custom:error {OnlySingleAssetSupported} If more than one asset/amount/premium is supplied.
    /// @custom:error {RouterNotAllowed} If either router is not whitelisted.
    /// @custom:error {InvalidPathLength} If either path length is less than 2.
    /// @custom:error {InvalidPath1Start} If the first path does not start with the reserve.
    /// @custom:error {InvalidPath2End} If the second path does not end with the reserve.
    /// @custom:error {TokenNotWhitelisted} If any token in the paths is not whitelisted.
    /// @custom:error {InvalidPath2Start} If the second path does not start with the first swap's output token.
    /// @custom:error {InsufficientToRepay} If post‑swap balance is below `principal + fee`.
    /// @custom:error {LessThanMinProfit} If realized profit is below `minProfit`.
    /// @custom:emits {FlashLoanExecuted}
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address,
        bytes calldata params
    ) external override nonReentrant whenNotPaused returns (bool) {
        if (msg.sender != lendingPool) revert OnlyLendingPool(msg.sender, lendingPool);
        if (assets.length != 1 || amounts.length != 1 || premiums.length != 1) {
            revert OnlySingleAssetSupported(assets.length, amounts.length, premiums.length);
        }

        address _reserve = assets[0];
        uint256 _amount = amounts[0];
        uint256 _fee = premiums[0];

        (
            address router1,
            address router2,
            address[] memory path1,
            address[] memory path2,
            uint256 amountOutMin1,
            uint256 amountOutMin2,
            uint256 minProfit,
            bool unwrapProfitToEth,
            address opInitiator
        ) = abi.decode(params, (address, address, address[], address[], uint256, uint256, uint256, bool, address));

        if (!routerWhitelist[router1] || !routerWhitelist[router2]) revert RouterNotAllowed(router1, router2);
        if (path1.length < 2 || path2.length < 2) revert InvalidPathLength(path1.length, path2.length);
        if (path1[0] != _reserve) revert InvalidPath1Start(path1[0], _reserve);
        if (path2[path2.length - 1] != _reserve) revert InvalidPath2End(path2[path2.length - 1], _reserve);

        for (uint256 i = 0; i < path1.length; i++) {
            if (!tokenWhitelist[path1[i]]) revert TokenNotWhitelisted(path1[i]);
        }
        for (uint256 i = 0; i < path2.length; i++) {
            if (!tokenWhitelist[path2[i]]) revert TokenNotWhitelisted(path2[i]);
        }

        // Approve router1 to spend _reserve
        IERC20(_reserve).forceApprove(router1, 0);
        IERC20(_reserve).forceApprove(router1, _amount);

        uint256 deadline = block.timestamp + 300; // could be unckecked
        uint256[] memory amounts1 =
            IUniswapV2Router02(router1).swapExactTokensForTokens(_amount, amountOutMin1, path1, address(this), deadline);
        uint256 out1 = amounts1[amounts1.length - 1];

        // reset approval
        IERC20(_reserve).forceApprove(router1, 0);

        address intermediate = path1[path1.length - 1];
        // ensure path2 starts with intermediate
        if (path2[0] != intermediate) revert InvalidPath2Start(path2[0], intermediate);

        IERC20(intermediate).forceApprove(router2, 0);
        IERC20(intermediate).forceApprove(router2, out1);

        // uint256[] memory amounts2 =
        IUniswapV2Router02(router2).swapExactTokensForTokens(out1, amountOutMin2, path2, address(this), deadline);
        // uint256 out2 = amounts2[amounts2.length - 1];

        // reset approval
        IERC20(intermediate).forceApprove(router2, 0);

        uint256 totalDebt = _amount + _fee;
        uint256 balance = IERC20(_reserve).balanceOf(address(this));

        if (balance < totalDebt) revert InsufficientToRepay(balance, totalDebt);

        uint256 profit = 0;
        if (balance > totalDebt) {
            unchecked {
                profit = balance - totalDebt;
            }
        }

        if (minProfit > 0) {
            if (profit < minProfit) revert LessThanMinProfit(profit, minProfit);
        }

        if (profit > 0) {
            // If unwrap requested and profit token is WETH, unwrap to ETH and track ethProfits
            if (unwrapProfitToEth && _reserve == WETH) {
                // move profit to contract as WETH -> withdraw to ETH
                // Approve WETH withdraw: contract already holds the WETH
                // Withdraw WETH to ETH
                IWETH(WETH).withdraw(profit);
                ethProfits = ethProfits + profit;
            } else {
                profits[_reserve] = profits[_reserve] + profit;
            }
        }

        // Approve lendingPool to pull repayment
        IERC20(_reserve).forceApprove(lendingPool, 0);
        IERC20(_reserve).forceApprove(lendingPool, totalDebt);

        emit FlashLoanExecuted(opInitiator, _reserve, _amount, _fee, profit);
        return true;
    }

    /// @notice Withdraw realized profits to a recipient.
    /// @param token Zero address to withdraw native ETH profits, or the ERC‑20 token address for token profits.
    /// @param amount The amount to withdraw.
    /// @param to The recipient address.
    /// @custom:access Only owner.
    /// @custom:error {ZeroAmountWithdraw} If `amount` is zero.
    /// @custom:error {ZeroAddressWithdraw} If `to` is the zero address.
    /// @custom:error {InsufficientProfit} If `amount` exceeds recorded profits for `token`.
    /// @custom:emits {Withdrawn}
    function withdrawProfit(address token, uint256 amount, address to) external onlyOwner nonReentrant {
        if (amount == 0) revert ZeroAmountWithdraw();
        if (to == address(0)) revert ZeroAddressWithdraw();
        if (token == address(0)) {
            // ETH withdraw
            if (amount > ethProfits) revert InsufficientProfit(ethProfits, amount);
            unchecked {
                ethProfits = ethProfits - amount;
            }
            (bool sent,) = to.call{value: amount}("");
            if (!sent) revert WithdrawFailed(to, amount);
            emit Withdrawn(address(0), to, amount);
            return;
        }
        uint256 bal = profits[token];
        if (amount > bal) revert InsufficientProfit(bal, amount);
        unchecked {
            profits[token] = bal - amount;
        }
        IERC20(token).safeTransfer(to, amount);
        emit Withdrawn(token, to, amount);
    }

    /// @notice Emergency rescue of arbitrary ERC‑20 tokens from the contract.
    /// @param token The ERC‑20 token address to transfer out.
    /// @param amount The token amount to transfer.
    /// @param to The recipient address.
    /// @custom:access Only owner.
    /// @custom:error {ZeroAddressWithdraw} If `to` is the zero address.
    /// @custom:emits {Withdrawn}
    function emergencyWithdrawERC20(address token, uint256 amount, address to) external onlyOwner nonReentrant {
        if (to == address(0)) revert ZeroAddressWithdraw();
        IERC20(token).safeTransfer(to, amount);
        emit Withdrawn(token, to, amount);
    }

    /// @notice Accepts plain ETH transfers (used when unwrapping WETH profits).
    receive() external payable {}
}
