//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.17;

import "../../libraries/MessageStruct.sol";

interface IMessageExecutor {
    /**
     * @notice Emitted when a message has successfully been executed.
     * @param fromChainId ID of the chain that dispatched the message
     * @param messageId ID uniquely identifying the message that was executed
     */
    event MessageIdExecuted(
        uint256 indexed fromChainId,
        bytes32 indexed messageId
    );

    /**  @dev Custom error: Message ID already executed
     *  @param messageId  ID uniquely identifying the message
     * @param errorData  error data in bytes
     *
     */
    error MessageIdAlreadyExecuted(bytes32 messageId, bytes errorData);

    /**
     * @dev MessageExecutor MUST revert if an individual message fails and SHOULD emit a MessageFailure custom error.
     */
    error MessageFailure(bytes32 messageId, bytes errorData);

    /**
     * @notice Execute message from the origin chain.
     * @dev Should authenticate that the call has been performed by the bridge transport layer.
     * @dev Must revert if the message fails.
     * @dev Must emit the `MessageIdExecuted` event once the message has been executed.
     * @param to Address that will receive `data`
     * @param data Data forwarded to address `to`
     * @param messageId ID uniquely identifying the message
     * @param fromChainId ID of the chain that dispatched the message
     * @param from Address of the sender on the origin chain
     */
    function executeMessage(
        address to,
        bytes calldata data,
        bytes32 messageId,
        uint256 fromChainId,
        address from
    ) external;
}
