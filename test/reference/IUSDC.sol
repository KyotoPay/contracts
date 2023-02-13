// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.9.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IUSDC is IERC20 {
    function isBlacklisted(address) external view returns (bool);
    function mint(address, uint256) external;
    function configureMinter(address, uint256) external returns (bool);
}
