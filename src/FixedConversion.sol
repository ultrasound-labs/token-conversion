// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// Errors
error Conversion_Expired();
error Only_Stream_Owner();
error Invalid_Recipient();
error Invalid_Stream_StartTime();

// Interfaces
interface IERC20Burnable is IERC20 {
    function burnFrom(address account, uint256 amount) external;
}

/// Converts a token to another token where the conversion price is fixed and the output token is streamed to the
/// recipient over a fixed duration.
contract FixedConversion is Ownable {

    // Constants
    address public constant FDT = 0xEd1480d12bE41d92F36f5f7bDd88212E381A3677; // the token to deposit
    address public constant BOND = 0x0391D2021f89DC339F60Fff84546EA23E337750f; // the token to stream
    uint256 public constant RATE = 750; // the amount of FDT that converts to 1 WAD of BOND
    uint256 public constant DURATION = 365 days; // the vesting duration (1 year)
    uint256 public constant EXPIRATION = 1706831999; // expiration of conversion (2024-02-01 23:59:59 GMT+0000)

    // Structs
    struct Stream {
        uint128 total;
        uint128 claimed;
    }

    // Storage vars
    // Stream owner and startTime is encoded in streamId
    mapping(uint256 => Stream) public streams;

    // Events
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
        uint256 indexed newStreamId
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

        // don't convert to zero address
        if (recipient == address(0)) revert Invalid_Recipient();

        // compute stream amount
        // all amounts are in WAD precision
        uint256 amountOut = amount / RATE;

        // create new stream or add to existing stream created in same block
        streamId = encodeStreamId(recipient, uint64(block.timestamp));
        Stream storage stream = streams[streamId];
        // this is safe bc BOND totalSupply is only 10**7
        stream.total = uint128(amountOut + stream.total);

        // burn deposited tokens
        // reverts if insufficient allowance or balance
        IERC20Burnable(FDT).burnFrom(msg.sender, amount);
        emit Convert(streamId, msg.sender, recipient, amount, amountOut);
    }

    /// Withdraws claimable BOND tokens to the stream's `owner`
    /// @dev Reverts if not called by the stream's `owner`
    function claim(uint256 streamId)
        external
        returns (uint256 claimed)
    {
        Stream memory stream = streams[streamId];
        (address streamOwner, uint64 startTime) = decodeStreamId(streamId);

        // withdraw claimable amount
        return _claim(stream, streamId, streamOwner, streamOwner, startTime);
    }

    /// Withdraws claimable BOND tokens to a designated `recipient`
    /// @dev Reverts if not called by the stream's `owner`
    function claim(uint256 streamId, address recipient)
        external
        returns (uint256 claimed)
    {
        Stream memory stream = streams[streamId];
        (address streamOwner, uint64 startTime) = decodeStreamId(streamId);

        // withdraw claimable amount
        return _claim(stream, streamId, streamOwner, recipient, startTime);
    }

    /// Withdraws claimable BOND tokens to `recipient`
    function _claim(
        Stream memory stream,
        uint256 streamId,
        address streamOwner,
        address recipient,
        uint64 startTime
    ) private returns (uint256 claimed) {
        // check owner
        if (msg.sender != streamOwner) revert Only_Stream_Owner();

        // compute claimable amount and update stream
        claimed = _claimableBalance(stream, startTime);
        stream.claimed = uint128(stream.claimed + claimed);
        streams[streamId] = stream;

        // withdraw claimable amount
        // reverts if insufficient balance
        IERC20(BOND).transfer(recipient, claimed);
        emit Withdraw(streamId, recipient, claimed);
    }

    /// Transfers stream to a new owner
    function transferStreamOwnership(uint256 streamId, address newOwner)
        external
        returns (uint256 newStreamId)
    {
        Stream memory stream = streams[streamId];
        (address owner, uint64 startTime) = decodeStreamId(streamId);

        // only stream owner is allowed to update ownership
        if (owner != msg.sender) revert Only_Stream_Owner();

        // store stream with new streamId or add to existing stream
        newStreamId = encodeStreamId(newOwner, startTime);

        Stream memory newStream = streams[newStreamId];
        newStream.total += stream.total;
        newStream.claimed += stream.claimed;
        streams[newStreamId] = newStream;

        delete streams[streamId];
        emit UpdateStreamOwner(streamId, newStreamId);
    }

    // Owner methods

    /// Withdraws `amount` of BOND to owner
    // TODO: should we allow withdrawing BOND by owner?
    function withdraw(uint256 amount) external onlyOwner {
        // reverts if insufficient balance
        IERC20(BOND).transfer(owner(), amount);
    }

    // View methods

    /// Returns the claimable balance for a stream
    function claimableBalance(uint256 streamId)
        external
        view
        returns (uint256 claimable)
    {
        (, uint64 startTime) = decodeStreamId(streamId);
        return _claimableBalance(streams[streamId], startTime);
    }

    function _claimableBalance(Stream memory stream, uint64 startTime)
        private
        view
        returns (uint256 claimable)
    {
        uint256 endTime = startTime + DURATION;
        if (block.timestamp <= startTime) {
            revert Invalid_Stream_StartTime();
        } else if (endTime <= block.timestamp) {
            claimable = stream.total - stream.claimed;
        } else {
            uint256 diffTime = block.timestamp - startTime;
            claimable = stream.total * diffTime / DURATION - stream.claimed;
        }
    }

    /// @notice Encodes `owner` and `startTime` as `streamId`
    /// @param owner Owner of the stream
    /// @param startTime Stream startTime timestamp
    /// @return streamId Identifier of the stream [owner, startTime]
    function encodeStreamId(address owner, uint64 startTime)
        public
        pure
        returns (uint256 streamId)
    {
        unchecked {
            streamId = (uint256(uint160(owner)) << 96) + startTime;
        }
    }

    /// @notice Decodes the `owner` and `startTime` from `streamId`
    /// @param streamId bytes32 containing a stream's [owner, startTime]
    /// @return owner owner extracted from `streamId`
    /// @return startTime startTime extracted from `streamId`
    function decodeStreamId(uint256 streamId)
        public
        pure
        returns (address owner, uint64 startTime)
    {
        owner = address(uint160(uint256(streamId >> 96)));
        startTime = uint64(streamId);
    }

}
