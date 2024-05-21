// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Ownable} from "openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

error PeriodTooShort();
error AssetNotSupported();
error LiquidationUnavailable();

contract MiniSavingAccount is Ownable {
    using SafeERC20 for IERC20;

    uint256 constant MINIMUM_BORROWING_PERIOD = 7 days;

    struct BorrowInfo {
        address borrowAsset;
        address collateralAsset;
        uint256 borrowAmount;
        uint256 collateralAmount;
        uint256 returnAmount;
        uint256 returnDateTimestamp;
        uint256 borrowTimestamp;
    }

    mapping(address => uint256) public balances;
    mapping(address => uint256) public lendingRatesDaily;
    mapping(address => mapping(address => uint256)) public collateralRates;

    mapping(address => BorrowInfo[]) public userBorrowings;
    mapping(address => uint256[]) public borrowTimestamps;
    mapping(address => uint256[]) public repayTimestamps;
    mapping(address => uint256) public borrowCount;
    mapping(address => uint256) public repayCount;

    BorrowInfo[] public borrowings;

    function deposit(address asset, uint256 amount) external {
        balances[asset] += amount;
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(address asset, uint256 amount) external onlyOwner {
        balances[asset] -= amount;
        IERC20(asset).safeTransfer(msg.sender, amount);
    }

    function borrow(
        address borrowAsset,
        uint256 borrowAmount,
        address collateralAsset,
        uint256 period
    ) external returns (uint256) {
        if (period < MINIMUM_BORROWING_PERIOD) {
            revert PeriodTooShort();
        }

        uint256 collateralRate = collateralRates[borrowAsset][collateralAsset];

        if (collateralRate == 0) {
            revert AssetNotSupported();
        }

        uint256 returnAmount = borrowAmount +
            (lendingRatesDaily[borrowAsset] * period) /
            1 ether;

        uint256 collateralAmount = (returnAmount * collateralRate) / 1 ether;

        BorrowInfo memory borrowInfo = BorrowInfo({
            borrowAsset: borrowAsset,
            collateralAsset: collateralAsset,
            borrowAmount: borrowAmount,
            collateralAmount: collateralAmount,
            returnAmount: returnAmount,
            returnDateTimestamp: block.timestamp + period,
            borrowTimestamp: block.timestamp
        });

        borrowings.push(borrowInfo);
        userBorrowings[msg.sender].push(borrowInfo);
        borrowTimestamps[msg.sender].push(block.timestamp);
        borrowCount[msg.sender] += 1;

        balances[borrowAsset] -= borrowAmount;

        IERC20(borrowAsset).safeTransfer(msg.sender, borrowAmount);
        IERC20(collateralAsset).safeTransferFrom(
            msg.sender,
            address(this),
            collateralAmount
        );

        return borrowings.length - 1;
    }

    function repay(uint256 index) external {
        BorrowInfo storage borrowInfo = borrowings[index];

        balances[borrowInfo.borrowAsset] += borrowInfo.returnAmount;

        IERC20(borrowInfo.borrowAsset).safeTransferFrom(
            msg.sender,
            address(this),
            borrowInfo.returnAmount
        );
        IERC20(borrowInfo.collateralAsset).safeTransfer(
            msg.sender,
            borrowInfo.collateralAmount
        );

        borrowInfo.collateralAmount = 0;
        borrowInfo.returnAmount = 0;

        repayTimestamps[msg.sender].push(block.timestamp);
        repayCount[msg.sender] += 1;
    }

    function liquidate(uint256 index) external {
        BorrowInfo storage borrowInfo = borrowings[index];

        if (borrowInfo.returnDateTimestamp >= block.timestamp) {
            revert LiquidationUnavailable();
        }

        balances[borrowInfo.collateralAsset] += borrowInfo.collateralAmount;

        borrowInfo.collateralAmount = 0;
        borrowInfo.returnAmount = 0;
    }

    function setCollateralRate(
        address lendingAsset,
        address borrowingAsset,
        uint256 borrowRate
    ) external onlyOwner {
        collateralRates[lendingAsset][borrowingAsset] = borrowRate;
    }

    function setCollateralRateBatched(
        address[] calldata lendingAssets,
        address[] calldata borrowingAssets,
        uint256[] calldata borrowRates
    ) external onlyOwner {
        for (uint256 i = 0; i < lendingAssets.length; i++) {
            collateralRates[lendingAssets[i]][borrowingAssets[i]] = borrowRates[i];
        }
    }

    function setDailyLendingRate(
        address asset,
        uint256 lendingRate
    ) external onlyOwner {
        lendingRatesDaily[asset] = lendingRate;
    }

    function setDailyLendingRateBatched(
        address[] calldata assets,
        uint256[] calldata lendingRates
    ) external onlyOwner {
        for (uint256 i = 0; i < assets.length; i++) {
            lendingRatesDaily[assets[i]] = lendingRates[i];
        }
    }

    function getBorrowingInfo(
        uint256 index
    ) external view returns (BorrowInfo memory) {
        return borrowings[index];
    }

    function calculateAverageBorrowToRepayTime(address user) public view returns (uint256) {
        uint256[] storage borrowTimes = borrowTimestamps[user];
        uint256[] storage repayTimes = repayTimestamps[user];

        if (borrowTimes.length == 0 || repayTimes.length == 0) {
            return 0;
        }

        uint256 totalBorrowToRepayTime = 0;
        uint256 count = 0;

        for (uint256 i = 0; i < borrowTimes.length && i < repayTimes.length; i++) {
            if (repayTimes[i] > borrowTimes[i]) {
                totalBorrowToRepayTime += (repayTimes[i] - borrowTimes[i]);
                count++;
            }
        }

        if (count == 0) {
            return 0;
        }

        return totalBorrowToRepayTime / count;
    }

    function calculateHealthFactor(address user) public view returns (uint256) {
        uint256 totalCollateral = 0;
        uint256 totalBorrow = 0;

        BorrowInfo[] storage userBorrows = userBorrowings[user];
        for (uint256 i = 0; i < userBorrows.length; i++) {
            totalCollateral += userBorrows[i].collateralAmount;
            totalBorrow += userBorrows[i].borrowAmount;
        }

        if (totalBorrow == 0) {
            return type(uint256).max;
        }

        return (totalCollateral * 1 ether) / totalBorrow;
    }

    function calculateLTVChangeRate(address user) public view returns (uint256) {
        if (borrowTimestamps[user].length < 2) {
            return 0;
        }

        uint256 initialLTV = calculateLTV(user, 0);
        uint256 latestLTV = calculateLTV(user, borrowTimestamps[user].length - 1);

        if (initialLTV == 0) {
            return 0;
        }

        return ((latestLTV - initialLTV) * 1 ether) / initialLTV;
    }

    function calculateLTV(address user, uint256 index) internal view returns (uint256) {
        uint256 totalCollateral = 0;
        uint256 totalBorrow = 0;

        BorrowInfo storage borrowInfo = userBorrowings[user][index];
        totalCollateral += borrowInfo.collateralAmount;
        totalBorrow += borrowInfo.borrowAmount;

        if (totalCollateral == 0) {
            return 0;
        }

        return (totalBorrow * 1 ether) / totalCollateral;
    }

    function assessUserRisk(address user) external view returns (
        uint256 borrowFrequencyScore,
        uint256 repayFrequencyScore,
        uint256 averageBorrowToRepayTimeScore,
        uint256 healthFactorScore,
        uint256 ltvChangeRateScore,
        uint256 overallReliabilityScore
)
 {
    // Frequency of Borrowing
    uint256 borrowFrequency = borrowCount[user];
    borrowFrequencyScore = calculateBorrowFrequencyScore(borrowFrequency);

    // Frequency of Repayment
    uint256 repayFrequency = repayCount[user];
    repayFrequencyScore = calculateRepayFrequencyScore(repayFrequency);

    // Average time between borrowing and repayment
    uint256 averageBorrowToRepayTime = calculateAverageBorrowToRepayTime(user);
    averageBorrowToRepayTimeScore = calculateAverageBorrowToRepayTimeScore(averageBorrowToRepayTime);

    // Health Factor
    uint256 healthFactor = calculateHealthFactor(user);
    healthFactorScore = calculateHealthFactorScore(healthFactor);

    // LTV Change Rate
    uint256 ltvChangeRate = calculateLTVChangeRate(user);
    ltvChangeRateScore = calculateLTVChangeRateScore(ltvChangeRate);

    // Combine these factors into a comprehensive risk score (weights are placeholders)
    overallReliabilityScore = (healthFactorScore * 50 + 
                        ltvChangeRateScore * 25 + 
                        borrowFrequencyScore * 10 + 
                        repayFrequencyScore * 10 +
                        averageBorrowToRepayTimeScore * 20) / 115;

    return (
        borrowFrequencyScore,
        repayFrequencyScore,
        averageBorrowToRepayTimeScore,
        healthFactorScore,
        ltvChangeRateScore,
        overallReliabilityScore
    );
}

function calculateBorrowFrequencyScore(uint256 borrowFrequency) internal pure returns (uint256) {
    if (borrowFrequency >= 10) {
        return 100; // Highest risk score
    } else if (borrowFrequency >= 5) {
        return 75; // Medium risk score
    } else if (borrowFrequency >= 1) {
        return 50; // Low risk score
    } else {
        return 25; // Minimal risk score
    }
}



function calculateRepayFrequencyScore(uint256 repayFrequency) internal pure returns (uint256) {
    if (repayFrequency >= 10) {
        return 100; // Highest risk score
    } else if (repayFrequency >= 5) {
        return 75; // Medium risk score
    } else if (repayFrequency >= 1) {
        return 50; // Low risk score
    } else {
        return 25; // Minimal risk score
    }
}


function calculateAverageBorrowToRepayTimeScore(uint256 averageBorrowToRepayTime) internal pure returns (uint256) {
    // Define thresholds based on your platform's requirements
    if (averageBorrowToRepayTime >= 30 days) {
        return 25; // Minimal risk score
    } else if (averageBorrowToRepayTime >= 15 days) {
        return 50; // Low risk score
    } else if (averageBorrowToRepayTime >= 7 days) {
        return 75; // Medium risk score
    } else {
        return 100; // Highest risk score
    }
}


function calculateHealthFactorScore(uint256 healthFactor) internal pure returns (uint256) {
    // Define thresholds based on your platform's requirements
    if (healthFactor >= 2 ether) {
        return 25; // Minimal risk score
    } else if (healthFactor >= 1.5 ether) {
        return 50; // Low risk score
    } else if (healthFactor >= 1 ether) {
        return 75; // Medium risk score
    } else {
        return 100; // Highest risk score
    }
}


function calculateLTVChangeRateScore(uint256 ltvChangeRate) internal pure returns (uint256) {
    // Define thresholds based on your platform's requirements
    if (ltvChangeRate >= 0.5 ether) {
        return 25; // Minimal risk score
    } else if (ltvChangeRate >= 0.3 ether) {
        return 50; // Low risk score
    } else if (ltvChangeRate >= 0.1 ether) {
        return 75; // Medium risk score
    } else {
        return 100; // Highest risk score
    }
}


}
