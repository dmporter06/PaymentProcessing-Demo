// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// Basic Payment Processing Demo
// Desired Features:

// Payment Processing with Aave lending integration Smart Contract

// Make this a github repository

// Imports the functionality for lending ETH on Aave
import "Contracts/AaveLendingProcessor.sol";

contract PaymentProcessor {
    
    address public owner;
    
    IAaveLendingProcessor public immutable aaveLendingProcessor;
    
    uint256 public lastLendTimestamp;
    uint256 public lastRetrieveTimestamp;
    
    // Update lending and retriving thresholds
    uint256 public lendingThreshold = 1 ether;
    uint256 public retrieveThreshold = 1 ether;

    // Threshold setter functions for testing purposes, REMOVE FOR LIVE DEMO
    function setLendingThreshold(uint256 _newLendingThreshold) external onlyOwner {
        lendingThreshold = _newLendingThreshold;
    }

    function setRetrieveThreshold(uint256 _newRetrieveThreshold) external onlyOwner {
        retrieveThreshold = _newRetrieveThreshold;
    }

    struct Merchant {
        uint256 merchantId;
        string merchantName;
        address custodialWallet;
        uint256 balance;
        bool isRegistered;
    }

    mapping(address => Merchant) merchants;
    mapping(uint256 => address) merchantIds;
    uint256 nextMerchantId;

    event MerchantRegistered(address indexed merchant, uint256 merchantId, address custodialWallet);
    event PaymentProcessed(address indexed merchant, address indexed customer, uint256 amount);
    event FundsWithdrawn(address indexed merchant, uint256 amount, address indexed recipient);
    event FundsLentToAave(uint256 amount);
    event FundsRetrievedFromAave(uint256 amount);
    event FundsReceived(uint256 amount, address sender);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    modifier onlyMerchant() {
        require(merchants[msg.sender].isRegistered, "Only registered merchants can call this");
        _;
    }

    constructor(address _aaveLendingProcessor) {
        owner = msg.sender;
        nextMerchantId = 1;
        aaveLendingProcessor = IAaveLendingProcessor(_aaveLendingProcessor);
    }

    function registerMerchant(string memory _merchantName, address _custodialWallet) external onlyOwner {
        require(!merchants[_custodialWallet].isRegistered, "Merchant already registered");
        merchants[_custodialWallet] = Merchant(nextMerchantId, _merchantName, _custodialWallet, 0, true);
        merchantIds[nextMerchantId] = _custodialWallet;
        emit MerchantRegistered(_custodialWallet, nextMerchantId, _custodialWallet);
        unchecked {
            nextMerchantId++;
        }
    }

    function processPayment(address _merchant) external payable {
        require(merchants[_merchant].isRegistered, "Merchant not registered");
        require(msg.value > 0, "Payment amount must be greater than zero");

        merchants[_merchant].balance += msg.value;
        emit PaymentProcessed(_merchant, msg.sender, msg.value);
    }

    function issueRefund(address payable _customer, uint256 _amount) external onlyMerchant {
        require(merchants[msg.sender].balance >= _amount, "Insufficient funds in merchant's balance");
        require(_customer != address(0), "Invalid customer address");

        // Deduct the amount from merchant's balance
        merchants[msg.sender].balance -= _amount;

        // Transfer the refund to the customer
        (bool success, ) = _customer.call{value: _amount}("");
        require(success, "Refund failed");

        // Emit an event for the refund transaction
        emit PaymentProcessed(msg.sender, _customer, _amount);  // You can reuse PaymentProcessed event for refund
        emit FundsWithdrawn(msg.sender, _amount, _customer); // Emit the withdrawal event for tracking
    }

    // This function costs a shit ton of gas to deploy for some reason
    function withdrawFunds(address payable _recipient, uint256 amount) external onlyMerchant {
        require(merchants[msg.sender].balance >= amount, "Insufficient balance");
        require(address(this).balance >= amount, "Not enough liquidity available, retrieve funds first");

        merchants[msg.sender].balance -= amount;

        // Using transfer to minimize gas cost
        _recipient.transfer(amount);

        emit FundsWithdrawn(msg.sender, amount, _recipient);
    }

    function emergencyWithdraw() external onlyOwner {
        uint256 contractBalance = address(this).balance;
        require(contractBalance > 0, "No funds available");

        (bool success, ) = owner.call{value: contractBalance}("");
        require(success, "Emergency withdrawal failed");
    }

    function requestRetrieveFunds(uint256 amount) external onlyMerchant {
        require(amount >= retrieveThreshold, "Amount too small to retrieve");
    
        aaveLendingProcessor.retrieveLentFunds(amount, address(this));

        emit FundsRetrievedFromAave(amount);
    }

    function getMerchantById(uint256 _merchantId) external view onlyOwner returns (Merchant memory) {
        address merchantAddress = merchantIds[_merchantId];
        require(merchants[merchantAddress].isRegistered, "Merchant ID not found");
        return merchants[merchantAddress];
    }

    function collectAaveInterest() external view onlyOwner {
        uint256 interest = aaveLendingProcessor.collectInterest();
        require(interest > 0, "No interest available");
        
        // Owner can decide what to do with the interest: reinvest or distribute
    }

    // Batch lending function
    function lendFundsBatch() external onlyOwner {
        require(block.timestamp >= lastLendTimestamp + 1 hours, "Lending too soon");
        require(address(this).balance >= lendingThreshold, "Not enough funds to lend");

        uint256 amountToLend = address(this).balance;

        // Directly call lending function in AaveLendingProcessor
        aaveLendingProcessor.lendFunds{value: amountToLend}();
    
        lastLendTimestamp = block.timestamp;

        emit FundsLentToAave(amountToLend);
    }

    // Batch retrieval function
    function retrieveLentFundsBatch(uint256 amount) external onlyOwner {
        require(block.timestamp >= lastRetrieveTimestamp + 1 hours, "Retrieving too soon");
        require(amount >= retrieveThreshold, "Amount too small to retrieve");

        uint256 balanceBefore = address(this).balance;

        aaveLendingProcessor.retrieveLentFunds(amount, address(this));

        uint256 balanceAfter = address(this).balance;
        require(balanceAfter > balanceBefore, "Funds retrieval failed"); // Ensure funds were actually withdrawn

        lastRetrieveTimestamp = block.timestamp;

        emit FundsRetrievedFromAave(amount);
    }

    // Allow contract to receive ETH
    receive() external payable {
        emit FundsReceived(msg.value, msg.sender);
    }

    // Fallback in case Aave sends ETH to this contract without a function call
    fallback() external payable {} 
}