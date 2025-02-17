// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// Payment Processing with Aave lending integration Smart Contract

// Where to get contract information
// AavePool: Aave Documentation
// WETH Gateway: Aave Documentation
// WETH address: Google it, and verify on sepolia.etherscan.io
// aWETH address: Google it, and verify on sepolia.etherscan.io

interface IAaveLendingProcessor {
    function lendFunds() external payable;
    function retrieveLentFunds(uint256 amount, address paymentProcessor) external;
    function collectInterest() external view returns (uint256);
}

// Aave v3 Lending Pool Interface
interface IPool {
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
    function getReserveNormalizedIncome(address asset) external view returns (uint256);
}

// Aave v3 ETH Gateway (for handling native ETH deposits)
interface IWETH {
    function deposit() external payable;
    function approve(address spender, uint256 amount) external returns (bool);
}

contract AaveLendingProcessor {
    address public owner;
    IPool public immutable aavePool;
    address public immutable WETH;

    uint256 public totalDeposited;

    event FundsLent(uint256 amount);
    event FundsRetrieved(uint256 withdrawnAmount);
    event InterestCollected(uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this");
        _;
    }

    constructor(address _aavePool, address _weth) {
        owner = msg.sender;
        aavePool = IPool(_aavePool);
        WETH = _weth;

        // Approve max WETH amount to Aave to save gas
        IWETH(WETH).approve(address(aavePool), type(uint256).max);
    }

    // Deposit ETH into Aave
    function lendFunds() external payable {
        require(msg.value > 0, "No ETH sent to lend");

        // Convert ETH to WETH
        IWETH(WETH).deposit{value: msg.value}();

        // Supply WETH to Aave
        aavePool.supply(WETH, msg.value, address(this), 0);

        // Track the total deposited amount
        totalDeposited += msg.value;

        emit FundsLent(msg.value);
    }

    // Withdraw ETH from Aave
    function retrieveLentFunds(uint256 amount, address paymentProcessor) external onlyOwner {
        require(paymentProcessor != address(0), "Invalid recipient address");

        // Withdraw WETH from Aave back to the PaymentProcessor contract
        uint256 withdrawnAmount = aavePool.withdraw(WETH, amount, paymentProcessor);

        emit FundsRetrieved(withdrawnAmount);
    }

    // Collect earned interest (calculated based on reserve income)
    function collectInterest() external view returns (uint256) {
        uint256 normalizedIncome = aavePool.getReserveNormalizedIncome(WETH);

        // Ensure we correctly calculate interest as growth over totalDeposited
        require(totalDeposited > 0, "No funds deposited yet");

        uint256 availableInterest = normalizedIncome - totalDeposited;
        return availableInterest; 
    }

    // Allow contract to receive ETH
    receive() external payable {}

    // Fallback in case Aave sends ETH to this contract without a function call
    fallback() external payable {}
} 