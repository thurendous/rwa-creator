// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {ConfirmedOwner} from "./ConfirmedOwner.sol";

/*
 * @title dTSLA
 * @author thurendous
*/
contract dTSLA {
    /// major functions are below 4:

    /// send an http request to:
    /// 1. see how much TSLA is bought
    /// 2. If enough TSLA is in the alpaca account, mint dTSLA
    /// mint dTSLA
    /// 2 transaction function
    function sendMintRequest(uint256 _amount) external onlyOwner {}

    function _mintFulFillRequest() internal {}

    /// @notice user sends a request to sell TSLA for USDC(redemptionToken)
    /// This will, have the chainlink function call our alpaca (bank)
    /// and do the followings:
    /// 1. Sell TSLAon the brokerage
    /// 2. Buy USDC to the user
    /// 3. Burn dTSLA token
    function sendRedeemRequest() external {}

    function _redeemFulFillRequest() internal {}
}
