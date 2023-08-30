// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.17;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IAxelarGasService} from "@axelar-network/axelar-cgp-solidity/contracts/interfaces/IAxelarGasService.sol";
import {IAxelarGateway} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol";
import {AxelarExecutable} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/executable/AxelarExecutable.sol";


// import {Upgradable} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/upgradable/Upgradable.sol";
// import {StringToAddress, AddressToString} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/utils/AddressString.sol";
// import {StringToBytes32, Bytes32ToString} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/utils/Bytes32String.sol";


import {TypeCasts} from "./libraries/TypeCasts.sol";
import {Errors} from "./libraries/Errors.sol";

import {IMessageExecutor} from "./interfaces/EIP5164/IMessageDispatcher.sol";

import "./libraries/MessageStruct.sol";

/**
 * @title HyperlaneReceiverAdapter implementation.
 * @notice `IBridgeReceiverAdapter` implementation that uses Hyperlane as the bridge.
 */
contract AxelarReceiverAdapter is
    IMessageExecutor,
    IMessageExecutable,
    AxelarExecutable,
    Ownable
{
    /// @notice `Mailbox` contract reference.
    IMailbox public immutable mailbox;

    /// @notice `ISM` contract reference.
    IInterchainSecurityModule public ism;

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
     * @notice Emitted when the ISM is set.
     * @param module The new ISM for this adapter/recipient.
     */
    event IsmSet(address indexed module);

    /**
     * @notice Emitted when a sender adapter for a source chain is updated.
     * @param srcChainId Source chain identifier.
     * @param senderAdapter Address of the sender adapter.
     */
    event SenderAdapterUpdated(uint256 srcChainId, address senderAdapter);

    /* Constructor */
    /**
     * @notice HyperlaneReceiverAdapter constructor.
     * @param _mailbox Address of the Hyperlane `Mailbox` contract.
     */
    constructor(address _mailbox) {
        if (_mailbox == address(0)) {
            revert Errors.InvalidMailboxZeroAddress();
        }
        mailbox = IMailbox(_mailbox);
    }

    /// @notice Restrict access to trusted `Mailbox` contract.
    modifier onlyMailbox() {
        if (msg.sender != address(mailbox)) {
            revert Errors.UnauthorizedMailbox(msg.sender);
        }
        _;
    }

    /// @inheritdoc ISpecifiesInterchainSecurityModule
    function interchainSecurityModule()
        external
        view
        returns (IInterchainSecurityModule)
    {
        return ism;
    }

    /**
     * @notice Sets the ISM for this adapter/recipient.
     * @param _ism The ISM contract address.
     */
    function setIsm(address _ism) external onlyOwner {
        ism = IInterchainSecurityModule(_ism);
        emit IsmSet(_ism);
    }

    function executeMessage(
        address _to,
        bytes calldata message,
        bytes32 messageId,
        uint256 fromChainId,
        address from
    ) internal {
        (bool success, bytes memory returnData) = _to.call(
            abi.encodePacked(message, messageId, fromChainId, from)
        );

        if (!success) {
            revert MessageFailure(messageId, returnData);
        }

        emit MessageIdExecuted(fromChainId, messageId);
    }

    /**
     * @notice Called by Hyperlane `Mailbox` contract on destination chain to receive cross-chain messages.
     * @dev _origin Source chain domain identifier (not currently used).
     * @param _sender Address of the sender on the source chain.
     * @param _body Body of the message.
     */
    function handle(
        uint32,
        /* _origin*/ bytes32 _sender,
        bytes memory _body
    ) external virtual override onlyMailbox {
        address adapter = TypeCasts.bytes32ToAddress(_sender);
        (
            uint256 srcChainId,
            bytes32 msgId,
            address srcSender,
            address destReceiver,
            bytes memory data
        ) = abi.decode(_body, (uint256, bytes32, address, address, bytes));

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
