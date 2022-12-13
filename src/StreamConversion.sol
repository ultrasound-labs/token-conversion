// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// Errors
error Conversion_Expired();
error Insufficient_Reserves();
error Only_Stream_Owner();
error Invalid_Recipient();

// Interfaces
interface IERC20Burnable is IERC20 {
    function burnFrom(address account, uint256 amount) external;
}

/// converts a token to another token where the conversion price is fixed and the output token is streamed to the
/// recipient over a fixed duration.
contract StreamConversion is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using SafeMath for uint128;

    // constants
    uint256 public constant WAD = 1e18;
    address public constant FDT =
        address(0xEd1480d12bE41d92F36f5f7bDd88212E381A3677); // the token to deposit
    address public constant BOND =
        address(0x0391D2021f89DC339F60Fff84546EA23E337750f); // the token to stream
    uint256 public constant RATE = 750 * WAD; // the amount of FDT that converts to 1 WAD of BOND
    uint256 public constant DURATION = 365 days; // the vesting duration (1 year)
    uint256 public constant EXPIRATION = 1706831999; // expiration of conversion (2024-02-01 23:59:59 GMT+0000)

    // structs
    struct Stream {
        uint128 total;
        uint128 claimed;
    }

    // storage vars
    // @dev stream owner and startTime is encoded in streamId
    mapping(bytes32 => Stream) public streams;

    // events
    event Convert(
        bytes32 indexed streamId,
        address indexed sender,
        address indexed recipient,
        uint256 amountIn,
        uint256 amountOut
    );
    event Withdraw(
        bytes32 indexed streamId,
        address indexed recipient,
        uint256 amount
    );
    event UpdateStreamOwner(
        bytes32 indexed streamId,
        bytes32 indexed newStreamId
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
        returns (bytes32 streamId)
    {
        // assert conversion is not expired
        if (block.timestamp > EXPIRATION) revert Conversion_Expired();

        // compute stream amount
        // @dev all amounts are in WAD precision
        uint256 amountOut = amount.mul(WAD).div(RATE);

        // create new stream
        streamId = _encodeStreamId(recipient, uint64(block.timestamp));
        streams[streamId] = Stream({
            total: uint128(amountOut), // safe bc BOND totalSupply is only 10**7
            claimed: 0
        });

        // burn deposited tokens
        // @dev reverts if insufficient allowance or balance
        IERC20Burnable(FDT).burnFrom(msg.sender, amount);
        emit Convert(streamId, msg.sender, recipient, amount, amountOut);
    }

    /// Withdraws claimable BOND tokens to `recipient`
    function claim(bytes32 streamId) external returns (uint256 claimed) {
        Stream memory stream = streams[streamId];
        (address recipient, uint64 startTime) = _decodeStreamId(streamId);
        return _claim(stream, streamId, recipient, startTime);
    }

    /// Withdraws claimable BOND tokens to `recipient`
    function claimTo(bytes32 streamId, address recipient)
        external
        returns (uint256 claimed)
    {
        Stream memory stream = streams[streamId];
        (address streamOwner, uint64 startTime) = _decodeStreamId(streamId);

        // check owner
        if (msg.sender != streamOwner) revert Only_Stream_Owner();

        // don't claim to zero address
        if (recipient == address(0)) revert Invalid_Recipient();

        // withdraw claimable amount
        return _claim(stream, streamId, recipient, startTime);
    }

    /// Withdraws claimable BOND tokens to `recipient`
    function _claim(
        Stream memory stream,
        bytes32 streamId,
        address recipient,
        uint64 startTime
    ) private returns (uint256 claimed) {
        // compute claimable amount and update stream
        claimed = _claimableBalance(stream, startTime);
        stream.claimed += uint128(claimed);
        streams[streamId] = stream;

        // withdraw claimable amount
        // @dev reverts if insufficient balance
        IERC20(BOND).safeTransfer(recipient, claimed);
        emit Withdraw(streamId, recipient, claimed);
    }

    /// Transfers stream to a new owner
    function transferStreamOwnership(bytes32 streamId, address newOwner)
        external
        returns (bytes32 newStreamId)
    {
        Stream memory stream = streams[streamId];
        (address owner, uint64 startTime) = _decodeStreamId(streamId);

        // only stream owner is allowed to update ownership
        if (owner != msg.sender) revert Only_Stream_Owner();

        // store stream with new streamId
        newStreamId = _encodeStreamId(newOwner, startTime);
        delete streams[streamId];
        streams[newStreamId] = stream;
        emit UpdateStreamOwner(streamId, newStreamId);
    }

    // Owner methods

    /// Withdraws `amount` of BOND to owner
    function withdraw(uint256 amount) external onlyOwner {
        // @dev reverts if insufficient balance
        IERC20(BOND).safeTransfer(owner(), amount);
    }

    // View methods

    /// Returns the claimable balance for a stream
    function claimableBalance(bytes32 streamId)
        external
        view
        returns (uint256 claimable)
    {
        (, uint64 startTime) = _decodeStreamId(streamId);
        return _claimableBalance(streams[streamId], startTime);
    }

    function _claimableBalance(Stream memory stream, uint64 startTime)
        private
        view
        returns (uint256 claimable)
    {
        uint256 endTime = uint256(startTime).add(DURATION);
        if (block.timestamp <= startTime) {
            claimable = 0;
        } else if (endTime <= block.timestamp) {
            claimable = stream.total.sub(stream.claimed);
        } else {
            uint256 diffTime = block.timestamp.sub(startTime);
            claimable = ((stream.total).mul(diffTime).div(DURATION)).sub(
                stream.claimed
            );
        }
    }

    /// returns the total (remaining) balance (incl. claimable) for a stream
    function totalBalance(bytes32 streamId)
        external
        view
        returns (uint256 total)
    {
        Stream storage stream = streams[streamId];
        return (stream.total).sub(stream.claimed);
    }

    /// @notice Encodes `owner` and `startTime` as `streamId`
    /// @param owner Owner of the stream
    /// @param startTime Stream startTime timestamp
    /// @return streamId Identifier of the stream [owner, startTime]
    function encodeStreamId(address owner, uint64 startTime)
        external
        pure
        returns (bytes32 streamId)
    {
        return _encodeStreamId(owner, startTime);
    }

    function _encodeStreamId(address owner, uint64 startTime)
        private
        pure
        returns (bytes32 streamId)
    {
        unchecked {
            streamId = bytes32(
                (uint256(uint160(owner)) << 96) + uint256(startTime)
            );
        }
    }

    /// @notice Decodes the `owner` and `startTime` from `streamId`
    /// @param streamId bytes32 containing [owner, startTime]
    /// @return owner Chainlink round id
    /// @return startTime Timestamp of the Chainlink round
    function decodeStreamId(bytes32 streamId)
        external
        pure
        returns (address owner, uint64 startTime)
    {
        return _decodeStreamId(streamId);
    }

    function _decodeStreamId(bytes32 streamId)
        private
        pure
        returns (address owner, uint64 startTime)
    {
        owner = address(uint160(uint256(streamId >> 96)));
        startTime = uint64(uint256(streamId));
    }
}
