// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {ConfirmedOwner} from "@chainlink/contracts/v0.8/shared/access/ConfirmedOwner.sol";
import {FunctionsClient} from "@chainlink/contracts/v0.8/functions/dev/v1_0_0/FunctionsClient.sol";
import {FunctionsRequest} from "@chainlink/contracts/v0.8/functions/dev/v1_0_0/libraries/FunctionsRequest.sol";
import {ERC20} from "@openzepelin/contracts/token/ERC20/ERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/v0.8/interfaces/AggregatorV3Interface.sol";

/*
 * @title dTSLA
 * @author thurendous
*/

error dTSLA_NotEnoughCollateral();

contract dTSLA is ConfirmedOwner, FunctionsClient, ERC20 {
    using FunctionsRequest for FunctionsRequest.Request;

    enum MintOrRedeem {
        MINT,
        REDEEM
    }

    struct dTslaRequest {
        uint256 amountOfToken;
        address requester;
        MintOrRedeem mintOrRedeem;
    }

    // Math constants
    uint256 constant PRECISION = 1e18;

    address constant SEPOLIA_FUNCTIONS_ROUTER = 0xb83E47C2bC239B3bf370bc41e1459A34b41238D0;
    uint32 constant GAS_LIMIT = 300_000;
    bytes32 constant DON_ID = hex"66756e2d657468657265756d2d7365706f6c69612d3100000000000000000000";
    address constant SEPOLIA_TSLA_PRICE_FEED = 0xc59E3633BAAC79493d908e63626716e204A45EdF; // This is actually Link token price feed for demonstration purposes
    address constant SEPOLIA_USDC_PRICE_FEED = 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E; // This is actually Link token price feed for demonstration purposes
    uint64 constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint32 constant COLLATERAL_RATIO = 200; // 200% collateral ratio
    // If there is $200 of TSLA in the brokerage, we can mint at most $100 of dTSLA
    uint32 constant COLLATERAL_PRECISION = 100;
    uint256 constant MINIMUM_WITHDRAWAL_AMOUNT = 1100e18;

    string private s_mintSourceCode;
    uint64 public immutable i_subId;
    uint256 private s_portfolioBalance;

    mapping(bytes32 => dTslaRequest request) public s_requestIdToRequest;

    constructor(string memory _mintSourceCode, address _newOwner, uint64 _subId)
        ConfirmedOwner(_newOwner)
        // 0xb83E47C2bC239B3bf370bc41e1459A34b41238D0 sepolia's address
        FunctionsClient(SEPOLIA_FUNCTIONS_ROUTER)
    {
        s_mintSourceCode = _mintSourceCode;
        i_subId = _subId;
    }

    /// major functions are below 4:

    /// send an http request to:
    /// 1. see how much TSLA is bought
    /// 2. If enough TSLA is in the alpaca account, mint dTSLA
    /// mint dTSLA
    /// 2 transaction function
    function sendMintRequest(uint256 _amount) external onlyOwner returns (bytes32) {
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(s_mintSourceCode);
        bytes32 requestId = _sendRequest(req.encodeCBOR(), i_subId, GAS_LIMIT, DON_ID);

        return requestId;
    }

    /// Return the amount of TSLAvalue is stored in our broker
    /// If we have enough TSLA, mint dTSLA
    function _mintFulFillRequest(bytes32 requestId, bytes memory response) internal {
        uint256 amountOfTokensToMint = s_requestIdToRequest[requestId].amountOfToken;
        s_portfolioBalance = uint256(bytes32(response));

        // if TSLAcollateral > dTSLAvalue, mint dTSLA
        // how much TSLAin $$$ do we have?
        // how much dTSLA in $$$ are we minting?
        if (_getCollateralRatioAdjustedTotalBalance(amountOfTokensToMint) >= amountOfTokensToMint) {
            revert dTSLA_NotEnoughCollateral();
        }

        if (amountOfTokensToMint != 0) {
            _mint(s_requestIdToRequest[requestId].requester, amountOfTokensToMint);
        }
    }

    /// @notice user sends a request to sell TSLA for USDC(redemptionToken)
    /// This will, have the chainlink function call our alpaca (bank)
    /// and do the followings:
    /// 1. Sell TSLAon the brokerage
    /// 2. Buy USDC to the user
    /// 3. Burn dTSLA token
    function sendRedeemRequest(uint256 amountdTsla) external onlyOwner {
        uint256 amountTslaInUsdc = getUsdcValueOfUsdc(getUsdValueOfTsla(amountdTsla));
    }

    // USDC == USD???

    function _redeemFulFillRequest() internal {}

    function fulfillRequest(bytes32 requestId, bytes memory response, bytes memory /*err*/ ) internal override {
        if (s_requestIdToRequest[requestId].mintOrRedeem == MintOrRedeem.MINT) {
            _mintFulFillRequest(requestId, response);
        } else {
            _redeemFulFillRequest();
        }
    }

    function _getCollateralRatioAdjustedTotalBalance(uint256 amountOfTokensToMint) internal view returns (uint256) {
        uint256 calculatedNewTotalValue = getCalculatedNewTotalValue(amountOfTokensToMint);
        return (s_portfolioBalance * COLLATERAL_RATIO) / COLLATERAL_PRECISION;
    }

    // the new expected total value in USD of all the TSLA tokens combined
    function getCalculatedNewTotalValue(uint256 addedNumberOfTokens) internal view returns (uint256) {
        return ((totalSupply() + addedNumberOfTokens) * getTslaPrice()) / PRECISION;
    }

    function getTslaPrice() public view returns (uint256) {
        // get the price of TSLA
        AggregatorV3Interface pricefeed = AggregatorV3Interface(SEPOLIA_TSLA_PRICE_FEED);
        (, int256 price,,,) = pricefeed.latestRoundData();
        // return the price of TSLA
        return uint256(price) * ADDITIONAL_FEED_PRECISION;
    }

    function getUsdcValueOfUsd(uint256 usdAmount) public view returns (uint256) {
        return (usdAmount / getUsdcPrice()) / PRECISION;
    }

    function getUsdValueOfTsla(uint256 tslaAmount) public view returns (uint256) {
        return (tslaAmount * getTslaPrice()) / PRECISION;
    }

    function getUsdcPrice() public view returns (uint256) {
        // get the price of USDC
        AggregatorV3Interface pricefeed = AggregatorV3Interface(SEPOLIA_USDC_PRICE_FEED);
        (, int256 price,,,) = pricefeed.latestRoundData();
        // return the price of USDC
        return uint256(price) * ADDITIONAL_FEED_PRECISION;
    }
}
