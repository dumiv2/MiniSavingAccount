pragma solidity 0.8.24; 

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract AToken is ERC20{
    address public owner; 

    uint256 constant public AAVE_PRICE_USD = 88.53 * (10 ** 18); 
    uint256 constant public MTC_PRICE_USD = 1.72 * (10 ** 18); 

    uint256 public mtcToUSD;
    uint256 public aaveToUSD; 

    constructor() ERC20("aToken Ethereum", "AToken"){
        owner = msg.sender;
        mtcToUSD = MTC_PRICE_USD; 
        aaveToUSD = AAVE_PRICE_USD;


    } 

    function mintTokensWithMTC(address recipient, uint256 amount) external {
        require(msg.sender == owner, "Only owner can mint tokens"); 
        uint256 aaveAmount1 = (amount * mtcToUSD) * (10 ** 18) / aaveToUSD;
        _mint(recipient, aaveAmount1); 
        uint256 balanceAfterMint = balanceOf(recipient); 
        emit BalanceAfterMint(recipient, balanceAfterMint); 
        emit TokensMinted(recipient, amount, aaveAmount1); 
    }

    function mintTokensWithUSD(address recipient, uint256 usdAmount) external {
        require(msg.sender == owner, "Only owner can mint tokens");
        uint256 aaveAmount2 = usdAmount * (10**15) / aaveToUSD;
        _mint(recipient, aaveAmount2);  

    }

    event BalanceAfterMint(address indexed recipient, uint256 balance);

    function burnTokenswithMTC(address recipient, uint256 amount) public payable {
        require(msg.sender == owner, "Only owner can burn tokens"); 
        uint256 ethAmount = (amount * mtcToUSD) * (10**15) / aaveToUSD; 
        require(balanceOf(recipient) >= ethAmount, "Insufficient Balance"); 
        _burn(recipient, ethAmount);
        emit TokensBurned(recipient, amount, ethAmount); 

    }

    function burnTokenswithUSD(address sender, uint256 usdAmount) external {
        require(msg.sender == owner, "Only owner can burn tokens"); 
        uint256 usdAmountToBurn = usdAmount * (10**15) / aaveToUSD; 
        _burn(sender, ethAmount); 
        emit TokensBurned(sender, usdAmount, usdAmountToBurn); 
    }

    event TokensMinted(address indexed recipient, uint256 amount, uint256 aaveAmount); 
    event TokensBurned(address indexed burner, uint256 amount, uint256 ethAmount);

}