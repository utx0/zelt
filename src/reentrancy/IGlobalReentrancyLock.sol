pragma solidity 0.8.19;

/// @notice inpsired by the openzeppelin reentrancy guard smart contracts
/// data container size has been changed
interface IGlobalReentrancyLock {
    /// @notice returns the last address that locked this contract
    function lastSender() external view returns (address);

    /// @notice returns true if the contract is currently entered,
    /// returns false otherwise
    function isLocked() external view returns (bool);

    /// @notice returns true if the contract is not currently entered,
    /// returns false otherwise
    function isUnlocked() external view returns (bool);

    /// @notice returns whether or not the contract is currently entered
    /// if true, and locked in the same block, it is possible to unlock
    function lockLevel() external view returns (uint8);
}
