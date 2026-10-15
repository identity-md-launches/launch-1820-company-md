// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Company.md (COMD)
/// @notice Fixed supply ERC-20; the deploying address receives all tokens once.
/// @dev No administrative roles, transfer fees, burn entry points, or further minting.
contract CompanyToken is ERC20 {
    /// @notice One billion tokens, expressed in the token's 18-decimal base units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20("Company.md", "COMD") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
