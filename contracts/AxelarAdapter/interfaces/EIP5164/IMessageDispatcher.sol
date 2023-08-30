//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.17;

interface IMessageDispatcher {
    /**
     * @notice Emitted when a message has successfully been dispatched to the executor chain.
     * @param messageId ID uniquely identifying the message
     * @param from Address that dispatched the message
     * @param toChainId ID of the chain receiving the message
     * @param to Address that will receive the message
     * @param data Data that was dispatched
     */
    event MessageDispatched(
        bytes32 indexed messageId,
        address indexed from,
        uint256 indexed toChainId,
        address to,
        bytes data
    );

    /**
     * @notice Dispatch a message to the receiving chain.
     * @dev Must compute and return an ID uniquely identifying the message.
     * @dev Must emit the `MessageDispatched` event when successfully dispatched.
     * @param toChainId ID of the receiving chain
     * @param to Address on the receiving chain that will receive `data`
     * @param data Data dispatched to the receiving chain
     * @return bytes32 ID uniquely identifying the message
     */
    function dispatchMessage(
        uint256 toChainId,
        address to,
        bytes calldata data
    ) external payable returns (bytes32);
}
