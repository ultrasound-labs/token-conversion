// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import {TokenConversion} from "../TokenConversion.sol";

contract TokenConversionTest is Test {
    TokenConversion private conversion;
    address private owner;
    IERC20 public fdt = IERC20(0xEd1480d12bE41d92F36f5f7bDd88212E381A3677);
    IERC20 public bond = IERC20(0x0391D2021f89DC339F60Fff84546EA23E337750f);

    function setUp() public {
        // set up conversion contract
        owner = address(this);
        conversion = new TokenConversion(owner);
        deal(address(bond), address(conversion), 1000 ether);

        // set up testing account with fdt
        deal(address(fdt), address(this), 75000 ether);
        fdt.approve(address(conversion), type(uint256).max);
    }

    function test_CanChangeOwner() public {
        conversion.transferOwnership(address(0x2));
        assertEq(conversion.owner(), address(0x2));
    }

    function test_OtherUsersCannotChangeOwner() public {
        vm.prank(address(0x1));
        vm.expectRevert("Ownable: caller is not the owner");
        conversion.transferOwnership(address(0x1));
    }

    function test_EncodeStreamId() public {
        address userEncoded = address(0x1);
        uint64 startTimeEncoded = 1669852800;

        uint256 streamId = conversion.encodeStreamId(
            userEncoded,
            startTimeEncoded
        );
        (address userDecoded, uint64 startTimeDecoded) = conversion
            .decodeStreamId(streamId);

        assertEq(userDecoded, userEncoded);
        assertEq(startTimeDecoded, startTimeEncoded);
    }

    function test_Convert() public {
        // 750 FDT is converted to 1 BOND
        uint256 streamId = conversion.convert(750 ether, address(this));
        (uint128 total, uint128 claimed) = conversion.streams(streamId);

        assertEq(total, 1 ether);
        assertEq(claimed, 0);
    }

    function test_Claim() public {
        // 75000 FDT is converted to 100 BOND claimable over 1 year
        uint256 streamId = conversion.convert(75000 ether, address(this));

        // initial balance
        (uint128 total, uint128 claimed) = conversion.streams(streamId);
        assertEq(total - claimed, 100 ether);

        // move block.timestamp by 73 days (1/5-th of vesting duration)
        skip(73 days);

        // balances pre/post claim
        assertEq(conversion.claimableBalance(streamId), 20 ether);
        conversion.claim(streamId);
        assertEq(conversion.claimableBalance(streamId), 0);
        assertEq(bond.balanceOf(address(this)), 20 ether);
        (total, claimed) = conversion.streams(streamId);
        assertEq(total - claimed, 80 ether);

        // move block.timestamp by another 73 days
        skip(73 days);

        // balances pre/post claim
        assertEq(conversion.claimableBalance(streamId), 20 ether);
        conversion.claim(streamId);
        assertEq(conversion.claimableBalance(streamId), 0);
        assertEq(bond.balanceOf(address(this)), 40 ether);
        (total, claimed) = conversion.streams(streamId);
        assertEq(total - claimed, 60 ether);

        // move block.timestamp by another 73 days
        skip(73 days);

        // balances pre/post claim
        assertEq(conversion.claimableBalance(streamId), 20 ether);
        conversion.claim(streamId);
        assertEq(conversion.claimableBalance(streamId), 0);
        assertEq(bond.balanceOf(address(this)), 60 ether);
        (total, claimed) = conversion.streams(streamId);
        assertEq(total - claimed, 40 ether);

        // move block.timestamp by another 73 days
        skip(73 days);

        // balances pre/post claim
        assertEq(conversion.claimableBalance(streamId), 20 ether);
        conversion.claim(streamId);
        assertEq(conversion.claimableBalance(streamId), 0);
        assertEq(bond.balanceOf(address(this)), 80 ether);
        (total, claimed) = conversion.streams(streamId);
        assertEq(total - claimed, 20 ether);

        // move block.timestamp by another 73 days
        skip(73 days);

        // balances pre/post claim
        assertEq(conversion.claimableBalance(streamId), 20 ether);
        conversion.claim(streamId);
        assertEq(conversion.claimableBalance(streamId), 0);
        assertEq(bond.balanceOf(address(this)), 100 ether);
        (total, claimed) = conversion.streams(streamId);
        assertEq(total - claimed, 0 ether);
    }

    function test_TransferStreamOwnership() public {
        // 75000 FDT is converted to 100 BOND claimable over 1 year
        uint256 streamId = conversion.convert(75000 ether, address(this));

        // test contract is the initial stream owner
        (address streamOwner, ) = conversion.decodeStreamId(streamId);
        assertEq(streamOwner, address(this));

        // transfer stream to new owner
        address newOwner = address(0x1);
        uint256 newStreamId = conversion.transferStreamOwnership(
            streamId,
            newOwner
        );
        (address newStreamOwner, ) = conversion.decodeStreamId(newStreamId);
        assertEq(newStreamOwner, newOwner);
    }
}
