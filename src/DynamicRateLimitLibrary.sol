pragma solidity =0.8.19;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @notice two rate storage slots per rate limit
struct DynamicRateLimit {
    /// @notice the rate per second for this contract
    uint128 rateLimitPerSecond;
    /// @notice the cap of the buffer that can be used at once
    uint128 bufferCap;
    /// @notice the last time the buffer was used by the contract
    uint32 lastBufferUsedTime;
    /// @notice the buffer at the timestamp of lastBufferUsedTime
    uint224 bufferStored;
}

/// @title abstract contract for putting a rate limit on how fast a contrac
/// can perform an action e.g. Minting
/// @author Elliot Friedman
library DynamicRateLimitLibrary {
    using SafeCast for *;

    /// @notice event emitted when buffer gets eaten into
    event BufferUsed(uint256 amountUsed, uint256 bufferRemaining);

    /// @notice event emitted when buffer gets replenished
    event BufferReplenished(uint256 amountReplenished, uint256 bufferRemaining);

    /// @notice event emitted when buffer cap is updated
    event BufferCapUpdate(uint256 oldBufferCap, uint256 newBufferCap);

    /// @notice event emitted when rate limit per second is updated
    event RateLimitPerSecondUpdate(
        uint256 oldRateLimitPerSecond,
        uint256 newRateLimitPerSecond
    );

    /// @notice the amount of action used before hitting limit
    /// @dev replenishes at rateLimitPerSecond per second up to bufferCap
    /// @param limit pointer to the rate limit object
    function buffer(DynamicRateLimit storage limit) public view returns (uint256) {
        uint256 elapsed = block.timestamp.toUint32() - limit.lastBufferUsedTime;
        return
            Math.min(
                limit.bufferStored + (limit.rateLimitPerSecond * elapsed),
                limit.bufferCap
            );
    }

    /// @notice the method that enforces the rate limit.
    /// Decreases buffer by "amount".
    /// If buffer is <= amount, revert
    /// @param limit pointer to the rate limit object
    /// @param amount to decrease buffer by
    /// @param prevTvlAmount the previous tvl amount before the action
    function depleteBuffer(DynamicRateLimit storage limit, uint256 amount, uint256 prevTvlAmount) internal {
        uint256 newBuffer = buffer(limit);

        require(newBuffer != 0, "RateLimited: no rate limit buffer");
        require(amount <= newBuffer, "RateLimited: rate limit hit");

        uint32 blockTimestamp = block.timestamp.toUint32();
        uint224 newBufferStored = (newBuffer - amount).toUint224();

        /// gas optimization to only use a single SSTORE
        limit.lastBufferUsedTime = blockTimestamp;
        limit.bufferStored = newBufferStored;

        /// decrease both buffer cap and rate limit per second proportionally to new TVL
        uint256 newTvl = prevTvlAmount - amount;
        uint128 newRateLimitPerSecond = (limit.rateLimitPerSecond * newTvl / prevTvlAmount).toUint128();
        uint128 newBufferCap = (limit.bufferCap * newTvl / prevTvlAmount).toUint128();

        limit.rateLimitPerSecond = newRateLimitPerSecond;
        limit.bufferCap = newBufferCap;

        emit BufferUsed(amount, newBufferStored);
    }

    /// @notice function to replenish buffer
    /// @param amount to increase buffer by if under buffer cap
    /// @param limit pointer to the rate limit object
    /// @param prevTvlAmount the previous tvl amount before the action
    function replenishBuffer(DynamicRateLimit storage limit, uint256 amount, uint256 prevTvlAmount) internal {
        uint256 newBuffer = buffer(limit);

        uint256 _bufferCap = limit.bufferCap; /// gas opti, save an SLOAD

        /// cannot replenish any further if already at buffer cap
        if (newBuffer == _bufferCap) {
            /// save an SSTORE + some stack operations if buffer cannot be increased.
            /// last buffer used time doesn't need to be updated as buffer cannot
            /// increase past the buffer cap
            return;
        }

        uint32 blockTimestamp = block.timestamp.toUint32();
        /// ensure that bufferStored cannot be gt buffer cap
        uint224 newBufferStored = Math
            .min(newBuffer + amount, _bufferCap)
            .toUint224();

        /// gas optimization to only use a single SSTORE
        limit.lastBufferUsedTime = blockTimestamp;
        limit.bufferStored = newBufferStored;

        /// increase both buffer cap and rate limit per second proportionally to new TVL
        uint256 newTvl = prevTvlAmount + amount;
        uint128 newRateLimitPerSecond = (limit.rateLimitPerSecond * newTvl / prevTvlAmount).toUint128();
        uint128 newBufferCap = (_bufferCap * newTvl / prevTvlAmount).toUint128();

        limit.rateLimitPerSecond = newRateLimitPerSecond;
        limit.bufferCap = newBufferCap;

        emit BufferReplenished(amount, newBufferStored);
    }

    /// @notice syncs the buffer to the current time
    /// @dev should be called before any action that
    /// updates buffer cap or rate limit per second
    /// @param limit pointer to the rate limit object
    function sync(DynamicRateLimit storage limit) internal {
        uint224 newBuffer = buffer(limit).toUint224();
        uint32 blockTimestamp = block.timestamp.toUint32();

        limit.lastBufferUsedTime = blockTimestamp;
        limit.bufferStored = newBuffer;
    }

    /// @notice set the rate limit per second
    /// @param limit pointer to the rate limit object
    /// @param newRateLimitPerSecond the new rate limit per second
    function setRateLimitPerSecond(DynamicRateLimit storage limit, uint128 newRateLimitPerSecond) internal {
        sync(limit);
        uint256 oldRateLimitPerSecond = limit.rateLimitPerSecond;
        limit.rateLimitPerSecond = newRateLimitPerSecond;

        emit RateLimitPerSecondUpdate(
            oldRateLimitPerSecond,
            newRateLimitPerSecond
        );
    }

    /// @notice set the buffer cap, but first sync to accrue all rate limits accrued
    /// @param limit pointer to the rate limit object
    /// @param newBufferCap the new buffer cap to set
    function setBufferCap(DynamicRateLimit storage limit, uint128 newBufferCap) internal {
        sync(limit);

        uint256 oldBufferCap = limit.bufferCap;
        limit.bufferCap = newBufferCap;

        emit BufferCapUpdate(oldBufferCap, newBufferCap);
    }
}
