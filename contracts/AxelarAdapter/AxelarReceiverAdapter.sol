// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.17;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IAxelarGasService} from "./interfaces/IAxelarGasService.sol";
import {IAxelarGateway} from "./interfaces/IAxelarGateway.sol";
import {AxelarExecutable} from "./AxelarExecutable.sol";

import {StringToAddress, AddressToString} from "./libraries/AddressString.sol";
import {StringToBytes32, Bytes32ToString} from "./libraries/Bytes32String.sol";

import {Errors} from "./libraries/Errors.sol";

import {IMessageExecutor} from "./interfaces/EIP5164/IMessageExecutor.sol";

import "./libraries/MessageStruct.sol";

/**
 * @title AxelarReceiverAdapter implementation.
 * @notice `IBridgeReceiverAdapter` implementation that uses Axelar as the bridge.
 */
contract AxelarReceiverAdapter is AxelarExecutable, IMessageExecutor, Ownable {
    IAxelarGasService public immutable gasService;

    using StringToAddress for string;
    using AddressToString for address;

    /**
     * @notice Sender adapter address for each source chain.
     * @dev srcChainId => senderAdapter address.
     */
    mapping(uint256 => address) public senderAdapters;

    /**
     * @notice Ensure that messages cannot be replayed once they have been executed.
     * @dev msgId => isExecuted.
     */
    mapping(bytes32 => bool) public executedMessages;

    /**
     * @notice Emitted when a sender adapter for a source chain is updated.
     * @param srcChainId Source chain identifier.
     * @param senderAdapter Address of the sender adapter.
     */
    event SenderAdapterUpdated(uint256 srcChainId, address senderAdapter);

    /* Constructor */
    /**
     * @notice AxelarReceiverAdapter constructor.
     * @param _gateway Address of the Axelar `Gatway` contract.
     */
    constructor(
        address _gateway,
        address _gasService
    ) AxelarExecutable(_gateway) {
        if (_gateway == address(0)) {
            revert Errors.InvalidGatewayZeroAddress();
        }
    }

    /// @notice Restrict access to trusted `Gateway` contract.
    modifier onlyGateway() {
        if (msg.sender != address(gateway)) {
            revert Errors.UnauthorizedGateway(msg.sender);
        }
        _;
    }

    // /// @notice A modifier used for restricting the caller of some functions to be configured receiver adapters.
    // modifier onlyReceiverAdapter() {
    //     require(
    //         isTrustedExecutor(msg.sender),
    //         "only trusted receiver adapters allowed"
    //     );
    //     _;
    // }

    function executeMessage(
        address _to,
        bytes calldata data,
        bytes32 messageId,
        uint256 fromChainId,
        address from
    ) internal {
        // if(executedMessages[messageId]) {
        //     revert MessageIdAlreadyExecuted(messageId);
        // }

        (bool _success, bytes memory _returnData) = _to.call(
            abi.encodePacked(data, messageId, fromChainId, from)
        );

        if (!_success) {
            revert MessageFailure(messageId, _returnData);
        }

        //executedMessages[messageId] = true;

        emit MessageIdExecuted(fromChainId, messageId);
    }

    /**
     * @notice Called by Axelar `Gateway` contract on destination chain to receive cross-chain messages.
     * @dev sourceChain Source chain domain identifier (not currently used).
     * @param sourceAddress Address of the sender on the source chain.
     * @param _payload Body of the message.
     */
    function _execute(
        string calldata /*sourceChain*/,
        string calldata sourceAddress,
        bytes calldata _payload
    ) internal virtual override {
        //address adapter = TypeCasts.bytes32ToAddress(_sender);
        address adapter = sourceAddress.toAddress(sourceAddress);
        (
            address destReceiver,
            bytes data,
            bytes32 msgId,
            uint256 srcChainId,
            address memory srcSender
        ) = abi.decode(_payload, (address, bytes, bytes32, uint256, address));

        if (adapter != senderAdapters[srcChainId]) {
            revert Errors.UnauthorizedAdapter(srcChainId, adapter);
        }
        if (executedMessages[msgId]) {
            revert MessageIdAlreadyExecuted(msgId);
        } else {
            executedMessages[msgId] = true;
        }

        executeMessage(destReceiver, data, msgId, srcChainId, srcSender);
    }

    function updateSenderAdapter(
        uint256[] calldata _srcChainIds,
        address[] calldata _senderAdapters
    ) external override onlyOwner {
        if (_srcChainIds.length != _senderAdapters.length) {
            revert Errors.MismatchChainsAdaptersLength(
                _srcChainIds.length,
                _senderAdapters.length
            );
        }
        for (uint256 i; i < _srcChainIds.length; ++i) {
            senderAdapters[_srcChainIds[i]] = _senderAdapters[i];
            emit SenderAdapterUpdated(_srcChainIds[i], _senderAdapters[i]);
        }
    }
}
