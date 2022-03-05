// Modified example from: https://solidity-by-example.org/app/bi-directional-payment-channel/
// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v3.3/contracts/math/SafeMath.sol";
import "github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v3.3/contracts/cryptography/ECDSA.sol";

contract BiDirectionalPaymentChannel {
    using SafeMath for uint;
    using ECDSA for bytes32;

    event ChallengeExit(address indexed sender, uint round);
    event Withdraw(address indexed to, uint amount);
    event WithdrawExit(address indexed sender, uint round, uint amount);

    address payable public closingparty;
    address payable[2] public users;

    mapping(address => bool) public isUser;

    mapping(address => uint) public balances;

    uint public round;
    uint public withdrawWait;
    uint public disputeGasUnits;
    uint public deposit;
    uint public deadline;

    bool public punished;

    // NOTE: deposit from multi-sig wallet
    constructor(
        address payable[2] memory _users,
        uint[2] memory _balances,
        uint _withdrawWait,
        uint _disputeGasUnits
    ) payable 
    {
        require(_withdrawWait > 0, "waiting period must be > 0");

        for (uint i = 0; i < _users.length; i++) {
            address payable user = _users[i];

            require(!isUser[user], "user must be unique");
            users[i] = user;
            isUser[user] = true;

            balances[user] = _balances[i];
        }

        withdrawWait = _withdrawWait;
        disputeGasUnits = _disputeGasUnits;
    }

    function verify(
        bytes[2] memory _signatures,
        address[2] memory _signers,
        uint[2] memory _balances,
        uint _round
    ) public pure returns (bool) {
        for (uint i = 0; i < _signatures.length; i++) {
            /*
            NOTE: sign with address of this contract to protect
                  agains replay attack on other contracts
            */
            bool valid = _signers[i] ==
                keccak256(abi.encodePacked(_balances, _round))
                .toEthSignedMessageHash()
                .recover(_signatures[i]);

            if (!valid) {
                return false;
            }
        }

        return true;
    }

    modifier checkSignatures(
        bytes[2] memory _signatures,
        uint[2] memory _balances,
        uint _round
    ) {
        // Note: copy storage array to memory
        address[2] memory signers;
        for (uint i = 0; i < users.length; i++) {
            signers[i] = users[i];
        }

        require(
            verify(_signatures, signers, _balances, _round),
            "Invalid signature"
        );

        _;
    }

    modifier onlyUser() {
        require(isUser[msg.sender], "Not user");
        _;
    }

    function update(
        uint[2] memory _balances,
        bytes[2] memory _signatures,
        uint _round
    ) 
        public checkSignatures(_signatures, _balances, _round)
    {
        for (uint i = 0; i < _balances.length; i++) {
            if ((balances[users[i]] > _balances[i]) &&
                (closingparty != address(0)) &&
                (closingparty != msg.sender) && 
                (punished == false)) {
                    // successful dispute, give deposit to sender
                    balances[msg.sender] += deposit;
                    punished = true;
                } 
            balances[users[i]] = _balances[i];
        }
    }

    function checkDeposit(uint _deposit)
        public view returns (bool) 
    {
        // uint baseFee = block.baseFee; commented due to compiler issue
        uint baseFee = 1000;
        if(_deposit >= baseFee * disputeGasUnits) {
            return true;
        }
        return false;
    } 

    function withdrawExit(
        uint[2] memory _balances,
        bytes[2] memory _signatures,
        uint _round
    )
        public payable onlyUser checkSignatures(_signatures, _balances, _round)
    {
        bool validDeposit = checkDeposit(msg.value);
        if(validDeposit) {
            update(_balances, _signatures, _round);
            deposit = msg.value;
            deadline = block.number + withdrawWait;
            closingparty = msg.sender;
            emit WithdrawExit(msg.sender, _round, msg.value);
        }
    }

    function withdraw() 
        public onlyUser 
    {
        require(block.timestamp >= deadline, "withdrawal period has not expired yet");

        uint amount = balances[msg.sender];
        balances[msg.sender] = 0;

        // if the withdrawal is by person closing channel and was honest, return deposit 
        if(msg.sender == closingparty && !punished) {
            amount += deposit;
        }

        (bool sent, ) = msg.sender.call{value: amount}("");
        require(sent, "Failed to send Ether");

        emit Withdraw(msg.sender, amount);
    }
}
