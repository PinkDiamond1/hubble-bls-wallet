//SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0 <0.9.0;
pragma abicoder v2;

import "./lib/IBLS.sol"; // to use a deployed BLS library
import "./lib/IERC20.sol";

import "./BLSWallet.sol";
import "hardhat/console.sol";

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";


contract VerificationGateway is Initializable
{
    bytes32 BLS_DOMAIN = keccak256(abi.encodePacked(uint32(0xfeedbee5)));
    uint8 constant BLS_LEN = 4;
    // uint256[BLS_LEN] ZERO_BLS_SIG = [uint256(0), uint256(0), uint256(0), uint256(0)];

    mapping (bytes32 => BLSWallet) public walletFromHash;

    IBLS public blsLib;

    /**
    @param bls verified bls library contract address
     */
    function initialize(IBLS bls) external initializer {
        blsLib = bls;
    }

    event WalletCreated(
        address indexed wallet,
        uint256[BLS_LEN] publicKey
    );

    event WalletActioned(
        address indexed wallet,
        uint256 nonce,
        bool result
    );

    struct TxData {
        uint256 nonce;
        uint256 ethValue;
        address contractAddress;
        bytes encodedFunction;
    }

    /**
    Requires wallet contracts to exist.
    @param publicKeys bls keys to be verified
    @param signature aggregated signature
    @param txs transaction data to be processed
    */
    function verifySignatures(
        uint256[BLS_LEN][] calldata publicKeys,
        uint256[2] calldata signature,
        TxData[] calldata txs
    ) public view {
        uint256 txCount = txs.length;
        uint256[2][] memory messages = new uint256[2][](txCount);

        for (uint256 i = 0; i<txCount; i++) {
            // construct params for signature verification
            messages[i] = messagePoint(txs[i]);
        }

        bool verified = blsLib.verifyMultiple(
            signature,
            publicKeys,
            messages
        );

        require(verified, "VerificationGateway: All sigs not verified");
    }

    /** 
    Useful no-op function to call when calling a wallet for the first time.
     */
    function walletCrossCheck(bytes32 hash) public payable {
        require(msg.sender == address(walletFromHash[hash]));
    }

    /** 
    Base function for verifying and actioning BLS-signed transactions.
    Creates a new bls wallet if a transaction's first time.
    Can be called with a single transaction.
    @param publicKeys the corresponding public bls keys for transactions
    @param signature aggregated bls signature of all transactions
    @param txs data required for a BLSWallet to make a transaction
    */
    function actionCalls(
        uint256[BLS_LEN][] calldata publicKeys,
        uint256[2] calldata signature,
        TxData[] calldata txs
    ) external {
        // revert if signatures not verified
        verifySignatures(publicKeys, signature, txs);

        bytes32 publicKeyHash;
        BLSWallet wallet;
        // check nonce then perform action
        for (uint256 i = 0; i<txs.length; i++) {

            // create wallet if it doesn't exist
            createNewWallet(publicKeys[i]);

            // construct params for signature verification
            publicKeyHash = keccak256(abi.encodePacked(publicKeys[i]));
            wallet = walletFromHash[publicKeyHash];

            if (txs[i].nonce == wallet.nonce()) {
                // action transaction (increments nonce)
                bool success = wallet.action(
                    txs[i].ethValue,
                    txs[i].contractAddress,
                    txs[i].encodedFunction
                );
                emit WalletActioned(
                    address(wallet),
                    wallet.nonce(),
                    success
                );
            }
        }
    }

    /**
    Create a new wallet if one doesn't exist for the given bls public key.
     */
    function createNewWallet(uint256[BLS_LEN] calldata publicKey)
        private // consider making external and VG stateless
    {
        bytes32 publicKeyHash = keccak256(abi.encodePacked(publicKey));
        // wallet at publicKeyHash doesn't exist
        if (address(walletFromHash[publicKeyHash]) == address(0)) {
            // blsKeysFromHash[publicKeyHash] = publicKey;
            walletFromHash[publicKeyHash] = new BLSWallet(publicKey);
            emit WalletCreated(
                address(walletFromHash[publicKeyHash]),
                publicKey
            );
        }
    }

    function messagePoint(
        TxData calldata txData
    ) internal view returns (uint256[2] memory) {
        return blsLib.hashToPoint(
            BLS_DOMAIN,
            abi.encodePacked(
                block.chainid,
                txData.nonce,
                txData.ethValue,
                txData.contractAddress,
                keccak256(txData.encodedFunction)
            )
        );
    }

}