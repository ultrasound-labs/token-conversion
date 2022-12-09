// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// Errors
error Conversion_Expired();
error Only_Stream_Owner();

/// converts a token to another that's streamed over a fixed duration and at a fixed
/// conversion price using FuroStream
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
    uint256 public constant RATE = 750 * WEI; // the conversion rate
    uint256 public constant DURATION = 365 * 86400; // the vesting duration
    uint256 public constant EXPIRATION = 1706831999; // expiration of conversion (2024-02-01 23:59:59 GMT+0000)

    // structs
    struct Stream {
        address owner;
        uint64 startTime;
        uint128 total;
        uint128 claimed;
    }

    // storage vars
    uint256 public streamIds;
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

    constructor(address _owner) {
        transferOwnership(_owner);
    }

    /// Burns `amount` of FDT tokens and creates a new stream of BOND
    /// tokens claimable by `recipient` over one year.
    function convert(address recipient, uint256 amount)
        external
        returns (uint256 streamId)
    {
        // assert conversion is not expired
        uint256 startTime = block.timestamp;
        if (startTime > EXPIRATION) revert Conversion_Expired();

        // compute stream amount
        // @dev all amounts are in WEI precision
        uint256 amountOut = amount.mul(WEI).div(RATE);

        // create new stream
        // @dev one stream is currently taking up 2 storage slots
        streamId = streamIds++;
        streams[streamId] = Stream({
            owner: recipient,
            startTime: uint64(startTime),
            total: uint128(amountOut), // safe bc BOND totalSupply is only 10**7
            claimed: 0
        });

        // burn deposited tokens
        IERC20(FDT).safeTransferFrom(msg.sender, address(0x0), amount);
        emit Convert(streamId, msg.sender, recipient, amount, amountOut);
    }

    /// Withdraws claimable BOND tokens to `recipient`
    function claim(uint256 streamId, address recipient)
        external
        returns (uint256 claimed)
    {
        // fetch stream
        Stream storage stream = streams[streamId];

        // check owner
        if (msg.sender != stream.owner) revert Only_Stream_Owner();

        // compute claimable amount and update stream
        claimed = _claimableBalance(stream);
        stream.claimed += uint128(claimed);

        if (recipient == address(0)) {
            recipient = stream.owner;
        }

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
