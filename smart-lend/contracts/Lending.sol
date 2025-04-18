// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// all the imports are here
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract LendingPlatform {
    // a simple Platform to take loan of mock stable coin on the deposited collateral

    /* all the constants of this contract are here */
    uint256 public constant COLLATERALIZATION_RATIO = 150;
    uint256 public constant PERCENTAGE_BASE = 100;
    uint256 public constant LIQUIDATION_THRESHOLD = 120; // 120%

    // all the variables are declared here
    IERC20 public testDAI;
    AggregatorV3Interface public priceFeed;

    /* all the mappings of contract are here */
    mapping(address => uint256) public CollateralBalance;
    mapping(address => uint256) public LoanBalance;

    /* all the events of this contract are here */
    event CollateralDeposited(address indexed user, uint256 amount);
    event LoanBorrowed(address indexed user, uint256 amount);
    event LoanRepaid(address indexed user, uint256 amount);
    event CollateralWithdrawn(address indexed user, uint256 amount);  // New event for collateral withdrawal
    event BorrowerLiquidated(address indexed user, uint256 collateralSeized, uint256 loanAmount);

    // --------------------------------------- CONSTRUCTORS START FROM HERE ------------------------------------------------------------------
    constructor(IERC20 _testDAI, AggregatorV3Interface _priceFeed) {
        testDAI = _testDAI;
        priceFeed = _priceFeed;
    }

    // ---------------------------------------- FUNCTIONS START FROM HERE -------------------------------------------------------------------
    
    /**
     * @notice Allows a user to deposit ETH as collateral.
     * @dev The amount of ETH sent with the transaction is added to the user's collateral balance.
     */
    function deposit() public payable {
        require(msg.value > 0, "deposited amount must be greater than 0");
        CollateralBalance[msg.sender] += msg.value;
        emit CollateralDeposited(msg.sender, msg.value);  // Emit CollateralDeposited event
    }

    /**
     * @notice Allows a user to borrow a loan based on the deposited collateral.
     * @dev The user can borrow up to a percentage of their collateral value.
     */
    function borrow(uint256 amount) public {
        uint256 ETHpriceUSD = getEthPrice();
        uint256 CollateralValueUSD = getCollateralValueUSD(msg.sender);
        uint maxBorrowAmountUSD = CollateralValueUSD * PERCENTAGE_BASE / COLLATERALIZATION_RATIO;
        
        require(amount <= maxBorrowAmountUSD, "BORROW AMOUNT CANNOT EXCEED THE COLLATERAL VALUE");
        
        LoanBalance[msg.sender] += amount;
        testDAI.transfer(msg.sender, amount);
        
        emit LoanBorrowed(msg.sender, amount);  // Emit LoanBorrowed event
    }

    /**
     * @notice Retrieves the current price of ETH using Chainlink price feed.
     * @dev Uses Chainlink AggregatorV3Interface to get the latest ETH price.
     */
    function getEthPrice() internal view returns (uint256) {
        (, int price, , , ) = priceFeed.latestRoundData();
        require(price > 0, "Price feed returned invalid price");
        return uint256(price);
    }

    /**
     * @notice Retrieves the collateral value in USD for a user.
     * @dev This function calculates the USD value of the collateral based on the ETH price.
     */
    function getCollateralValueUSD(address user) internal view returns (uint256) {
        uint256 ethPrice = getEthPrice();
        uint256 collateralEth = CollateralBalance[user];
        return (collateralEth * ethPrice) / 1e18;
    }

    /**
     * @notice Allows a borrower to repay their loan.
     * @dev Once the loan is repaid, the borrower can also withdraw their collateral.
     */
    function repayloan(uint256 amount) public {
        require(amount <= LoanBalance[msg.sender], "Repayment amount exceeds loan balance");
        
        testDAI.transferFrom(msg.sender, address(this), amount);
        LoanBalance[msg.sender] -= amount;
        
        if (LoanBalance[msg.sender] == 0) {
            uint256 collateralAmount = CollateralBalance[msg.sender];
            payable(msg.sender).transfer(collateralAmount);
            CollateralBalance[msg.sender] = 0;
            
            emit CollateralWithdrawn(msg.sender, collateralAmount);  // Emit CollateralWithdrawn event
        }

        emit LoanRepaid(msg.sender, amount);  // Emit LoanRepaid event
    }

    /**
     * @notice Allows a privileged user to liquidate a borrower if their collateral falls below the liquidation threshold.
     * @dev This function allows the liquidator to seize the borrower's collateral to repay the loan.
     */
    function liquidate(address borrower) public {
        uint256 loan = LoanBalance[borrower];
        require(loan > 0, "No outstanding loan to liquidate");
        
        uint256 collateralValueUSD = getCollateralValueUSD(borrower);
        uint256 requiredCollateralUSD = (loan * LIQUIDATION_THRESHOLD) / PERCENTAGE_BASE;
        
        require(collateralValueUSD < requiredCollateralUSD, "Collateral is sufficient");

        uint256 collateralEth = CollateralBalance[borrower];
        LoanBalance[borrower] = 0;
        CollateralBalance[borrower] = 0;

        payable(msg.sender).transfer(collateralEth);

        emit BorrowerLiquidated(borrower, collateralEth, loan);  // Emit BorrowerLiquidated event
    }

    
}
