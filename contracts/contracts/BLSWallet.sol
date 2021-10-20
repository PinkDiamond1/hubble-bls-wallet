//SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0 <0.9.0;
pragma abicoder v2;


//To avoid constructor params having forbidden evm bytecodes on Optimism
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import "./lib/IERC20.sol";
import "hardhat/console.sol";

interface IVerificationGateway {
    function walletCrossCheck(bytes32 publicKeyHash) external;
}

contract BLSWallet
{
    address public gateway;
    uint256[4] public publicKey;
    uint256 public nonce;

    constructor(uint256[4] memory blsKey) {
        gateway = msg.sender;
        publicKey = blsKey;
        nonce = 0;
    }

    receive() external payable {}
    fallback() external payable {}

    function getPublicKey() external returns (uint256[4] memory) {
        return publicKey;
    }

    function action(
        uint256 ethValue,
        address contractAddress,
        bytes calldata encodedFunction
    ) public payable onlyGateway returns (bool success) {
        if (ethValue > 0) {
            (success, ) = payable(contractAddress).call{value: ethValue}(encodedFunction);
        }
        else {
            (success, ) = address(contractAddress).call(encodedFunction);
        }
        nonce++;
    }

    modifier onlyGateway() {
        require(msg.sender == gateway);
        _;
    }
}