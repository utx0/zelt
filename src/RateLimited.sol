pragma solidity =0.8.19;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {RateLimitedLibrary, RateLimit} from "@src/RateLimitedLibrary.sol";

/// @title abstract contract for putting a rate limit on how fast a contrac
/// can perform an action e.g. Minting
/// @author Elliot Friedman
abstract contract RateLimited {
    using SafeCast for *;
    using RateLimitedLibrary for RateLimit;

    /// @notice maximum rate limit per second governance can set for this contract
    uint256 public immutable MAX_RATE_LIMIT_PER_SECOND;

    /// @notice rate limit for this contract
    RateLimit public rateLimit;

    /// @notice RateLimitedV2 constructor
    /// @param _maxRateLimitPerSecond maximum rate limit per second that governance can set
    /// @param _rateLimitPerSecond starting rate limit per second
    /// @param _bufferCap cap on buffer size for this rate limited instance
    constructor(
        uint256 _maxRateLimitPerSecond,
        uint128 _rateLimitPerSecond,
        uint128 _bufferCap
    ) {
        rateLimit.lastBufferUsedTime = block.timestamp.toUint32(); /// only access struct directly to prevent overflow on buffer calc in setBufferCap
        rateLimit.setBufferCap(_bufferCap);
        rateLimit.bufferStored = _bufferCap; /// manually set this as first call to setBufferCap sets it to 0

        require(
            _rateLimitPerSecond <= _maxRateLimitPerSecond,
            "RateLimited: rateLimitPerSecond too high"
        );
        rateLimit.setRateLimitPerSecond(_rateLimitPerSecond);

        MAX_RATE_LIMIT_PER_SECOND = _maxRateLimitPerSecond;
    }

    /// @notice the amount of action used before hitting limit
    /// @dev replenishes at rateLimitPerSecond per second up to bufferCap
    function buffer() public view returns (uint256) {
        return rateLimit.buffer();
    }

    /// @notice the method that enforces the rate limit.
    /// Decreases buffer by "amount".
    /// If buffer is <= amount, revert
    /// @param amount to decrease buffer by
    function _depleteBuffer(uint256 amount) internal {
        rateLimit.depleteBuffer(amount);
    }

    /// @notice function to replenish buffer
    /// @param amount to increase buffer by if under buffer cap
    function _replenishBuffer(uint256 amount) internal {
        rateLimit.replenishBuffer(amount);
    }

    function _setRateLimitPerSecond(uint128 newRateLimitPerSecond) internal {
        rateLimit.setRateLimitPerSecond(newRateLimitPerSecond);
    }

    function _setBufferCap(uint128 newBufferCap) internal {
        rateLimit.setBufferCap(newBufferCap);
    }
}
