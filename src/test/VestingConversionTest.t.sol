// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "./utils/Caller.sol";
import "./utils/tokens/TokenERC20.sol";

import {VestingConversion} from "../VestingConversion.sol";

contract VestingConversionTest is Test {
    TokenERC20 private tokenIn;
    TokenERC20 private tokenOut;
    VestingConversion private conversion;
    uint256 private RATE_DECIMALS;
    uint256 private RATE;
    uint256 private DURATION;
    uint256 private EXPIRATION;
    address private owner;
    address private furo;

    function setUp() public {
        RATE_DECIMALS = 18;
        RATE = (10**RATE_DECIMALS)/750;
        DURATION = 365*86400; // 1 year
        EXPIRATION = block.timestamp + 365*86400; // 1 year from now
        tokenIn = new TokenERC20("TokenIn", "TOKI");
        tokenOut = new TokenERC20("TokenOut", "TOKO");
        owner = address(this);
        furo = address(0x1);

        conversion = new VestingConversion(
            address(tokenIn),
            address(tokenOut),
            RATE,
            RATE_DECIMALS,
            DURATION,
            EXPIRATION,
            owner,
            furo,
            owner
        );
    }

    function testCanChangeOwner() public {
        conversion.transferOwnership(address(0x2));
        assertEq(conversion.owner(), address(0x2));
    }

    function testOtherUsersCannotChangeOwner() public {
        Caller user = new Caller();

        (bool ok, ) = user.externalCall(
            address(conversion),
            abi.encodeWithSelector(
                conversion.transferOwnership.selector,
                (address(0x2))
            )
        );

        assertTrue(!ok, "Only the owner can change owner");
    }
}
