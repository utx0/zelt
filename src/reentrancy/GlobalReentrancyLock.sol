// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {IGlobalReentrancyLock} from "@src/reentrancy/IGlobalReentrancyLock.sol";

/// @notice inpsired by the openzeppelin reentrancy guard smart contracts
/// data container size has been changed.

/// @dev need ACL to be able to lock and unlock the system and create public
/// lock and unlock functions that are scoped to only locker contracts
/// once locked, only the original caller that locked can unlock the contract

/// @notice explanation on data types used in contract

/// @dev block number can be safely downcasted without a check on exceeding
/// uint88 max because the sun will explode before this statement is true:
/// block.number > 2^88 - 1
/// address can be stored in a uint160 because an address is only 20 bytes

/// @dev in the EVM. 160bits / 8 bits per byte = 20 bytes
/// https://docs.soliditylang.org/en/develop/types.html#address

/// Storage slot visualization:

/// | last sender |  last block entered  |  lock level  |
/// |   0 - 160   |      160 - 248       |   248 - 256  |

contract GlobalReentrancyLock is IGlobalReentrancyLock {
    /// -------------------------------------------------
    /// -------------------------------------------------
    /// ------------------- Constants -------------------
    /// -------------------------------------------------
    /// -------------------------------------------------

    uint8 private constant _NOT_ENTERED = 0;
    uint8 private constant _ENTERED_LEVEL_ONE = 1;
    uint8 private constant _ENTERED_LEVEL_TWO = 2;

    /// ------------- System States ---------------

    /// system unlocked
    /// request level 2 locked
    /// call reverts because system must be locked at level 1 before locking to level 2
    ///
    /// system unlocked
    /// request level 1 locked
    /// level 1 locked, msg.sender stored
    /// level 1 unlocked, msg.sender checked to ensure same as locking
    ///
    /// lock level 1, msg.sender is stored
    /// request level 2 locked
    /// level 2 locked, msg.sender not stored
    /// request level 2 unlocked,
    /// level 2 unlocked, msg.sender not checked
    /// level 1 unlocked, msg.sender checked
    ///
    /// level 1 locked
    /// request level 2 locked
    /// level 2 locked
    /// request level 0 unlocked, invalid state, must unlock to level 1, call reverts
    ///
    /// request level 3 or greater locked from any system state, call reverts

    /// -------------------------------------------------
    /// -------------------------------------------------
    /// --------- Single Storage Slot Per Lock ----------
    /// -------------------------------------------------
    /// -------------------------------------------------

    /// @notice cache the address that locked the system
    /// only this address can unlock it
    address public lastSender;

    /// @notice store the last block entered
    /// if last block entered was in the past and status
    /// is entered, the system is in an invalid state
    /// which means that actions should not be allowed
    uint88 public lastBlockEntered;

    /// @notice system lock level
    uint8 public lockLevel;

    /// ---------- View Only APIs ----------

    /// @notice returns true if the contract is not currently entered
    /// at level 1 and 2, returns false otherwise
    function isUnlocked() external view override returns (bool) {
        return lockLevel == _NOT_ENTERED;
    }

    /// @notice returns whether or not the contract is currently locked
    function isLocked() external view override returns (bool) {
        return lockLevel != _NOT_ENTERED;
    }

    /// ---------- Internal State Changing APIs ----------

    /// @notice set the status to entered
    /// @dev only valid state transitions:
    /// - lock to level 1 from level 0
    /// - lock to level 2 from level 1
    function _lock(uint8 toLock) internal {
        uint8 currentLevel = lockLevel; /// cache to save 1 warm SLOAD

        require(toLock == currentLevel + 1, "GlobalReentrancyLock: invalid lock level");
        require(toLock <= _ENTERED_LEVEL_TWO, "GlobalReentrancyLock: exceeds lock state");

        /// only store the sender and lastBlockEntered if first caller (locking to level 1)
        if (currentLevel == _NOT_ENTERED) {
            /// - lock to level 1 from level 0

            uint88 blockEntered = uint88(block.number);

            lastSender = msg.sender;
            lastBlockEntered = blockEntered;
        } else {
            /// - lock to level 2 from level 1

            /// ------ increasing lock level flow ------

            /// do not update sender, to ensure original sender gets checked on final unlock
            /// do not update lastBlockEntered because it should be the same, if it isn't, revert
            /// if already entered, ensure entry happened this block
            require(block.number == lastBlockEntered, "GlobalReentrancyLock: system not entered this block");

            /// prevent footguns, do not allow original locker to lock again
            require(msg.sender != lastSender, "GlobalReentrancyLock: reentrant");
        }

        lockLevel = toLock;
    }

    /// @notice set the status to not entered
    /// only available if entered in same block
    /// otherwise, system is in an indeterminate state and no execution should be allowed
    /// can only be called by the last address to lock the system
    /// to prevent incorrect system behavior
    /// @dev toUnlock can only be _ENTERED_LEVEL_ONE or _NOT_ENTERED
    /// currentLevel cannot be _NOT_ENTERED when this function is called
    /// @dev only valid state transitions:
    /// - unlock to level 0 from level 1 as original locker in same block as lock
    /// - lock from level 2 down to level 1 in same block as lock
    function _unlock(uint8 toUnlock) internal {
        uint8 currentLevel = lockLevel;

        require(uint88(block.number) == lastBlockEntered, "GlobalReentrancyLock: not entered this block");
        require(currentLevel != _NOT_ENTERED, "GlobalReentrancyLock: system not entered");

        /// if started at level 1, locked up to level 2,
        /// and trying to lock down to level 0,
        /// fail as that puts us in an invalid state

        require(toUnlock == currentLevel - 1, "GlobalReentrancyLock: unlock level must be 1 lower");

        if (toUnlock == _NOT_ENTERED) {
            /// - unlock to level 0 from level 1, verify sender is original locker
            require(msg.sender == lastSender, "GlobalReentrancyLock: caller is not locker");
        } else {
            /// prevent footguns, do not allow original locker to unlock from level 2 to level 1
            require(msg.sender != lastSender, "GlobalReentrancyLock: reentrant");
        }

        lockLevel = toUnlock;
    }
}
