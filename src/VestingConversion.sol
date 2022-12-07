// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// https://github.com/sushiswap/sushiswap/blob/master/protocols/furo/contracts/FuroStreamRouter.sol
interface IFuroStreamRouter {
    function createStream(
        address recipient,
        address token,
        uint64 startTime,
        uint64 endTime,
        uint256 amount, /// @dev in token amount and not in shares
        bool fromBentoBox,
        uint256 minShare
    ) external payable returns (uint256 streamId, uint256 depositedShares);
}

/// Expired conversion error
error Conversion_Expired();

/// converts a token to another that's streamed over a fixed duration and at a fixed
/// conversion price using FuroStream
contract VestingConversion {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using SafeCast for uint256;

    IERC20 public immutable tokenIn; // the token to deposit
    uint256 public immutable tokenInDecimals; // decimal precision of deposited token
    IERC20 public immutable tokenOut; // the token to stream
    uint256 public immutable tokenOutDecimals; // decimal precision of streamed token
    uint256 public immutable rate; // the conversion rate
    uint256 public immutable rateDecimals; // decimal precision of conversion rate
    uint256 public immutable duration; // the vesting duration
    uint256 public immutable expiration; // expiration of the conversion offer
    address public immutable beneficiary; // the beneficiary of deposited tokens
    IFuroStreamRouter public immutable router; // the Sushi FuroStreamRouter

    event Convert(
        uint256 indexed streamId,
        address indexed sender,
        address indexed recipient,
        uint256 amountIn,
        uint256 amountOut,
        uint256 vestingEnd
    );

    constructor(
        address _tokenIn,
        address _tokenOut,
        uint256 _conversionRate,
        uint256 _rateDecimals,
        uint256 _vestingDuration,
        uint256 _conversionExpiration,
        address _tokenInBeneficiary,
        address _furoStreamRouter
    ) {
        tokenIn = IERC20(_tokenIn);
        tokenInDecimals = IERC20Metadata(_tokenIn).decimals();
        tokenOut = IERC20(_tokenOut);
        tokenOutDecimals = IERC20Metadata(_tokenOut).decimals();
        rate = _conversionRate;
        rateDecimals = _rateDecimals;
        duration = _vestingDuration;
        expiration = _conversionExpiration;
        beneficiary = _tokenInBeneficiary;
        router = IFuroStreamRouter(_furoStreamRouter);
    }

    function convert(address recipient, uint256 amount)
        external
        returns (uint256 streamId, uint256 depositedShares)
    {
        // assert conversion is not expired
        if (block.timestamp > expiration) revert Conversion_Expired();

        // compute conversion parameters
        uint256 amountOut = amount
            .mul(rate)
            .div(tokenInDecimals)
            .mul(tokenOutDecimals)
            .div(rateDecimals);
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime.add(duration);

        // send deposited tokens to beneficiary
        tokenIn.safeTransferFrom(msg.sender, beneficiary, amount);

        // approve FuroStreamRouter to transfer tokenOut
        // @dev we only approve incrementally with each conversion
        tokenOut.safeIncreaseAllowance(address(router), amountOut);

        // create Furo stream
        // @dev Stream owner will be the conversion contract, if updates to streams are
        // needed then this has to be implemented in the conversion contract
        (streamId, depositedShares) = router.createStream(
            recipient,
            address(tokenOut),
            startTime.toUint64(),
            endTime.toUint64(),
            amount,
            false,
            0
        ); // TODO: fix minShare param

        emit Convert(
            streamId,
            msg.sender,
            recipient,
            amount,
            amountOut,
            endTime
        );
    }
}
