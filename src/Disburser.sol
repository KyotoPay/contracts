// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

/// @title KyotoPay
/// Version 1.1 

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {DataTypes} from "./libraries/DataTypes.sol";
import {Errors} from "./libraries/Errors.sol";
import {Events} from "./libraries/Events.sol";
import {HubOwnable} from "./base/HubOwnable.sol";
import {IDisburser} from "./interfaces/IDisburser.sol";
import {IWETH9} from "./interfaces/IWETH9.sol";

// To Do: 
//   - Add a receive function
//   - Add EIP712 signatures 
//   - Update the deadline to be passed in by the frontend

contract Disburser is HubOwnable, Pausable, IDisburser {
    using SafeERC20 for IERC20;

    uint256 public constant DECIMALS = 10_000;
    // MAX_ADMIN_FEE is denominated in DECIMALs.  I.e. 500 = 5%
    uint256 public constant MAX_ADMIN_FEE = 500;

    address public immutable UNISWAP_SWAP_ROUTER_ADDRESS;
    address public immutable WETH_ADDRESS;

    // adminFee is denominated in DECIMALS.  For example, a value for fee of 200 = 2%
    uint256 public adminFee;
    constructor(uint256 _adminFee, address _kyotoHub, address _uniswapSwapRouterAddress, address _wethAddress) HubOwnable(_kyotoHub) {
        if (_adminFee > MAX_ADMIN_FEE) revert Errors.InvalidAdminFee();
        if (_uniswapSwapRouterAddress == address(0)) revert Errors.ZeroAddress();
        if (_wethAddress == address(0)) revert Errors.ZeroAddress();

        adminFee = _adminFee;
        UNISWAP_SWAP_ROUTER_ADDRESS = _uniswapSwapRouterAddress;
        WETH_ADDRESS = _wethAddress;
    }

    /**
     * @notice pays a recipient in their preferred token from a given input token
     * @param _recipient the recipient to pay
     * @param _tokenIn the token to send
     * @param _amountIn the amount of tokens to send 
     * @param _amountOut estimate of the Uniswap output of recipient's preferred token. Calculated on the frontend
     * @param _uniFee a Uniswap fee for a given pool
     * @param _data data about the transaction to be indexed
     * Requirements: 
     *  - '_recipient' != address(0)
     *  - '_tokenIn' is a valid input token
     *  - '_amountIn' != 0 
     *  - 'amountOut' != 0
     *  - '_uniFee' is a valid Uniswap pool fee
     *  - The executed swap will send the recipient more tokens than their slippageAllowed * '_amountOut'
     *  - The user's token balance > '_amountIn'
     *  - The user has approve the contract to transfer their tokens
     */ 
    function pay(
        address _recipient,
        address _tokenIn,
        uint256 _amountIn,
        uint256 _amountOut,
        uint24 _uniFee,
        bytes32 _data
    ) external whenNotPaused {
        _validateInputParams(_recipient, _tokenIn, _amountIn, _amountOut, _uniFee);

        // transfer the amount to this contract (should fail if the contract will not allow it)
        _getSenderFunds(_tokenIn, _amountIn);

        _pay(_recipient, _tokenIn, _amountIn, _amountOut, _uniFee, _data);
    }

    /**
     * @notice pays a recipient in their preferred token from the given ether
     * @param _recipient the recipient to pay
     * @param _amountOut estimate of the Uniswap output of recipient's preferred token. Calculated on the frontend
     * @param _uniFee a Uniswap fee for a given pool
     * @param _data data about the transaction to be indexed
     * Note: if the user has not set their preferences, they will receive WETH and not ETH
     * Requirements: 
     *  - '_recipient' != address(0)
     *  -  WETH is a whitelisted input
     *  -  msg.value > 0
     *  - 'amountOut' != 0
     *  - '_uniFee' is a valid Uniswap pool fee
     *  - The executed swap will send the recipient more tokens than their slippageAllowed * '_amountOut'
     */

    function payEth(address _recipient, uint256 _amountOut, uint24 _uniFee, bytes32 _data) external payable whenNotPaused {
        // Cache vars
        uint256 _msgValue = msg.value;
        address _wethAddress = WETH_ADDRESS;

        _validateInputParams(_recipient, _wethAddress, _msgValue, _amountOut, _uniFee);

        IWETH9(_wethAddress).deposit{value: _msgValue}();

        _pay(_recipient, _wethAddress, _msgValue, _amountOut, _uniFee, _data);
    }

    /*******************************
     *
     *       Internal functions
     *
     ******************************/

     /**
      * @dev validates preferences, gets recipient funds, executes the UNI swap, sends funds to recipient
      * Does not execute a UNI swap if the input token is the same as the output token or if the recipient has not set preferences
      * Instead, _pay will send the user funds directly to the recipient after a fee
      */
    function _pay(
        address _recipient,
        address _tokenIn,
        uint256 _amountIn,
        uint256 _amountOut,
        uint24 _uniFee,
        bytes32 _data
    ) internal {
        // Cache the recipient's preferences
        DataTypes.Preferences memory _preferences = KYOTO_HUB.getRecipientPreferences(_recipient);
        bool areValidPreferences = _validatePreferences(_preferences);

        // If the sender's token is the recipient's preferred token or recipient's preferences haven't been set, transfer directly and stop execution
        if ((_tokenIn == _preferences.tokenAddress) || !(areValidPreferences)) {
            _sendRecipientFunds(_tokenIn, _recipient, _amountIn);
            _emitPaymentEvent(_recipient, _tokenIn, _amountIn, _data);

            return;
        }

        uint256 swapOutput = _executeSwap(
            _tokenIn, _preferences.tokenAddress, _amountIn, _amountOut, _uniFee, _preferences.slippageAllowed
        );

        // transfer funds to recipient (will pay the owners here too)
        _sendRecipientFunds(_preferences.tokenAddress, _recipient, swapOutput);

        // emit any data for end user use
        _emitPaymentEvent(_recipient, _tokenIn, _amountIn, _data);
    }

    /**
     * @dev internal function to execute a swap using the Uniswap Swap Router
     * Uses the recipient's set slippage for amountOut
     */
    function _executeSwap(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn,
        uint256 _amountOut,
        uint24 _uniFee,
        uint96 _slippageAllowed
    ) internal returns (uint256) {
        // Cache
        address _uniswapSwapRouterAddress = UNISWAP_SWAP_ROUTER_ADDRESS;
        
        IERC20(_tokenIn).safeApprove(_uniswapSwapRouterAddress, _amountIn);

        // create the input params
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: _tokenIn,
            tokenOut: _tokenOut,
            fee: _uniFee, // e.g. fee for a pool at 0.3% tier is 3000
            recipient: address(this), // this contract will be doing the distribution of funds
            deadline: block.timestamp,
            amountIn: _amountIn,
            amountOutMinimum: ((_amountOut * uint256(_slippageAllowed)) / DECIMALS),
            sqrtPriceLimitX96: 0 // sets a limit for the price that the swap will push to the pool (setting to 0 makes it inactive) --> will require more research
        });

        // swap currency on uniswap
        return ISwapRouter(_uniswapSwapRouterAddress).exactInputSingle(params);
    }
    /**
     * @dev Internal function to validate input parameters. Reverts if given invalid input params.
     * Note: Uniswap fees for pools are 0.01%, 0.05%, 0.30%, and 1.00%
     * They are represented in hundredths of basis points.  I.e. 100 = 0.01%, 500 = 0.05%, etc.
     */

    function _validateInputParams(
        address _recipient,
        address _tokenIn,
        uint256 _amountIn,
        uint256 _amountOut,
        uint24 _uniFee
    ) internal view {
        // To Do: Make into custom error. Need to review logic operations...
        if((_uniFee != 100) && (_uniFee != 500) && (_uniFee != 3000) && (_uniFee != 10_000)) revert Errors.InvalidUniFee();
        if (!(KYOTO_HUB.isWhitelistedInputToken(_tokenIn))) revert Errors.InvalidToken();
        if (_recipient == address(0)) revert Errors.ZeroAddress();
        if (_amountIn == 0 || _amountOut == 0) revert Errors.InvalidAmount();
    }

    /**
     * @dev safe transfers funds from the user to address(this)
     */
    function _getSenderFunds(address _tokenAddress, uint256 _amountIn) internal {
        IERC20(_tokenAddress).safeTransferFrom(msg.sender, address(this), _amountIn);
    }

    /**
     * @dev safeTransfer tokens to a given recipient given a ERC20 token address and amount to send
     */ 
    function _sendRecipientFunds(address _tokenAddress, address _recipient, uint256 _amount) internal {
        // calculate the owner payment, this amount will stay in the contract and can be withdrawn at will (no reason to make superfluous transfers)
        uint256 ownerPayment = (_amount * adminFee) / DECIMALS;

        // pay the recipient the excess
        IERC20(_tokenAddress).safeTransfer(_recipient, _amount - ownerPayment);
    }

    /**
     * @dev validates recipient's preferences.  Does not revert.
     * @return true when valid preferences, false when invalid
     */
    function _validatePreferences(DataTypes.Preferences memory _preferences) internal view returns (bool) {
        return ((_preferences.slippageAllowed != 0) && (KYOTO_HUB.isWhitelistedOutputToken(_preferences.tokenAddress)));
    }

    /**
     * @dev cuts down on bytecode
     */
     // (_recipient, _tokenIn, _amountIn, _data);
    function _emitPaymentEvent(address _recipient, address _tokenIn, uint256 _amountIn, bytes32 _data) internal {
        emit Events.Payment(_recipient, _tokenIn, _amountIn, _data);
    }

    /*******************************
     *
     *       Admin functions
     *
     ******************************/

    /**
     * @dev Admin function to set the fee
     * @param _adminFee the new fee amount
     * Requirements:
     *  - 'adminFee" <= 'MAX_ADMIN_FEE'
     *  - msg.sender is the owner
     */
    function setAdminFee(uint256 _adminFee) external onlyHubOwner {
        if (_adminFee > MAX_ADMIN_FEE) revert Errors.InvalidAdminFee();
        adminFee = _adminFee;
    }

    /**
     * @dev Admin function to withdraw tokens from a given token address
     * Note: '_token' is not validated before passing it in as an argument
     * '_token' must always be verified manually before being called by the admin
     * @param _token the address of the token to withdraw
     * @param _amount the amount of token to withdraw
     * Requirements:
     *  - '_token' != address(0)
     *  - msg.sender is the owner
     *  - Token balance of address(this) > 0
     */
    function withdraw(address _token, uint256 _amount) external onlyHubOwner {
        if (IERC20(_token).balanceOf(address(this)) == 0) revert Errors.ZeroBalance();
        IERC20(_token).safeTransfer(msg.sender, _amount);
    }

    /**
     * @dev Admin function to pause payments
     */
    function pause() external onlyHubOwner {
        _pause();
    }

    /**
     * @dev Admin function to unpause payments
     */
    function unpause() external onlyHubOwner {
        _unpause();
    }
}