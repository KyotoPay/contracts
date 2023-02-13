// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

contract Helper {
    /**
     *
     * Constants
     *
     */
    uint256 constant FEE = 100;
    uint256 constant KYOTOPAY_DECIMALS = 10_000;
    // Uniswap's swap router
    address constant UNISWAP_SWAPROUTER_ADDRESS = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant RANDOM_USER = 0x5782F98E183f4F2BfBC7deD68141Fe6914307B3F;
    address constant RANDOM_RECIPIENT = 0x8313b3727E47efaaBB90b7C2f00A73758D52A2b5;
    address constant USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant DAI_ADDRESS = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant WBTC_ADDRESS = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address constant LOOKS_ADDRESS = 0xf4d2888d29D722226FafA5d9B24F9164c092421E;
    address ADMIN = address(this);

    // EOA that has ~$39 million in DAI
    // Reference: https://etherscan.io/address/0xb527a981e1d415af696936b3174f2d7ac8d11369
    address constant DAI_HOLDER = 0xb527a981e1d415AF696936B3174f2d7aC8D11369;

    // EOA that has ~$273 million in WBTC
    // Reference: https://etherscan.io/address/0x218b95be3ed99141b0144dba6ce88807c4ad7c09
    address constant WBTC_HOLDER = 0x218B95BE3ed99141b0144Dba6cE88807c4AD7C09;

    // Reference: https://etherscan.io/token/0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48#readProxyContract#F14
    address constant USDC_MASTER_MINTER = 0xE982615d461DD5cD06575BbeA87624fda4e3de17;

    // Reference: https://etherscan.io/token/0x6b175474e89094c44da98b954eedeac495271d0f#readContract#F5
    uint256 constant DAI_DECIMALS = 18;

    // Reference: https://etherscan.io/token/0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48#readProxyContract#F11
    uint256 constant USDC_DECIMALS = 6;

    // Reference: https://etherscan.io/token/0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2#readContract#F3
    uint256 constant WETH_DECIMALS = 18;

    // Reference: https://etherscan.io/token/0x2260fac5e5542a773aa44fbcfedf7c193bc2c599?a=mint#readContract#F4
    uint256 constant WBTC_DECIMALS = 8;

    /**
     *
     * Events
     *
     */
    event Payment(address recipient, address indexed tokenAddress, uint256 indexed amountIn, bytes32 indexed data);

    function getAdmin() external view returns (address) {
        return address(this);
    }
}