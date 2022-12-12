// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// Errors
error Conversion_Expired();
error Insufficient_Reserves();
error Only_Stream_Owner();
error Invalid_Recipient();

/// converts a token to another token where the conversion price is fixed and the output token is streamed to the
/// recipient over a fixed duration.
contract StreamConversion is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using SafeMath for uint128;

    // constants
    uint256 public constant WEI = 1e18;
    address public constant FDT =
        address(0xEd1480d12bE41d92F36f5f7bDd88212E381A3677); // the token to deposit
    address public constant BOND =
        address(0x0391D2021f89DC339F60Fff84546EA23E337750f); // the token to stream
    uint256 public constant RATE = 750 * WEI; // the amount of FDT that converts to 1 WEI of BOND
    uint256 public constant DURATION = 365 * 86400; // the vesting duration (1 year)
    uint256 public constant EXPIRATION = 1706831999; // expiration of conversion (2024-02-01 23:59:59 GMT+0000)

    // structs
    // @dev uses 2 storage slots
    struct Stream {
        address owner;
        uint64 startTime;
        uint128 total;
        uint128 claimed;
    }

    // storage vars
    uint256 public streamIds; // counter keeping track of streams
    mapping(uint256 => Stream) public streams;

    // events
    event Convert(
        uint256 indexed streamId,
        address indexed sender,
        address indexed recipient,
        uint256 amountIn,
        uint256 amountOut
    );
    event Withdraw(
        uint256 indexed streamId,
        address indexed recipient,
        uint256 amount
    );
    event UpdateStreamOwner(
        uint256 indexed streamId,
        address indexed oldOwner,
        address indexed newOwner
    );

    /// Instantiates a new converter contract with an owner
    /// @dev owner is able to withdraw BOND from the conversion contract
    constructor(address _owner) {
        transferOwnership(_owner);
    }

    /// Burns `amount` of FDT tokens and creates a new stream of BOND
    /// tokens claimable by `recipient` over one year.
    function convert(uint256 amount, address recipient)
        external
        returns (uint256 streamId)
    {
        // assert conversion is not expired
        if (block.timestamp > EXPIRATION) revert Conversion_Expired();

        // compute stream amount
        // @dev all amounts are in WEI precision
        uint256 amountOut = amount.mul(WEI).div(RATE);

        // create new stream and increase stream counter
        streamId = streamIds++;
        streams[streamId] = Stream({
            owner: recipient,
            startTime: uint64(block.timestamp),
            total: uint128(amountOut), // safe bc BOND totalSupply is only 10**7
            claimed: 0
        });

        // burn deposited tokens
        // @dev fails if sender doesn't hold enough FDT
        IERC20(FDT).safeTransferFrom(msg.sender, address(0x0), amount);
        emit Convert(streamId, msg.sender, recipient, amount, amountOut);
    }

    /// Withdraws claimable BOND tokens to `recipient`
    function claim(uint256 streamId) external returns (uint256 claimed) {
        Stream memory stream = streams[streamId];
        return _claim(stream, streamId, stream.owner);
    }

    /// Withdraws claimable BOND tokens to `recipient`
    function claimTo(uint256 streamId, address recipient)
        external
        returns (uint256 claimed)
    {
        Stream memory stream = streams[streamId];

        // check owner
        if (msg.sender != stream.owner) revert Only_Stream_Owner();

        // don't claim to zero address
        if (recipient == address(0)) revert Invalid_Recipient();

        // withdraw claimable amount
        return _claim(stream, streamId, recipient);
    }

    /// Withdraws claimable BOND tokens to `recipient`
    function _claim(
        Stream memory stream,
        uint256 streamId,
        address recipient
    ) private returns (uint256 claimed) {
        // compute claimable amount and update stream
        claimed = _claimableBalance(stream);
        stream.claimed += uint128(claimed);
        streams[streamId] = stream;

        // assert converter holds enough BOND tokens
        if (IERC20(BOND).balanceOf(address(this)) < claimed)
            revert Insufficient_Reserves();

        // withdraw claimable amount
        IERC20(BOND).safeTransfer(recipient, claimed);
        emit Withdraw(streamId, recipient, claimed);
    }

    /// Transfers stream to a new owner
    function transferStreamOwnership(uint256 streamId, address _owner)
        external
    {
        Stream storage stream = streams[streamId];

        // only stream owner is allowed to update ownership
        if (stream.owner != msg.sender) revert Only_Stream_Owner();

        // update ownership of the stream
        stream.owner = _owner;
        emit UpdateStreamOwner(streamId, msg.sender, _owner);
    }

    // Owner methods

    /// Withdraws `amount` of BOND to owner
    function withdraw(uint256 amount) external onlyOwner {
        IERC20(BOND).safeTransfer(owner(), amount);
    }

    // View methods

    /// Returns the details of a stream
    function getStream(uint256 streamId) external view returns (Stream memory) {
        return streams[streamId];
    }

    /// Returns the claimable balance for a stream
    function claimableBalance(uint256 streamId)
        external
        view
        returns (uint256 claimable)
    {
        return _claimableBalance(streams[streamId]);
    }

    function _claimableBalance(Stream memory stream)
        private
        view
        returns (uint256 claimable)
    {
        uint256 endTime = uint256(stream.startTime).add(DURATION);
        if (block.timestamp <= stream.startTime) {
            claimable = 0;
        } else if (endTime <= block.timestamp) {
            claimable = stream.total.sub(stream.claimed);
        } else {
            uint256 diffTime = block.timestamp.sub(stream.startTime);
            claimable = ((stream.total).mul(diffTime).div(DURATION)).sub(
                stream.claimed
            );
        }
    }

    /// returns the total (remaining) balance (incl. claimable) for a stream
    function totalBalance(uint256 streamId)
        external
        view
        returns (uint256 total)
    {
        Stream storage stream = streams[streamId];
        return (stream.total).sub(stream.claimed);
    }
}
