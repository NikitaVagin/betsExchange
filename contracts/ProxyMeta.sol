contract ProxyMeta {

struct MetaTransactionData {
    // Signer of meta-transaction. On whose behalf to execute the MTX.
    address payable signer;
    // Required sender, or NULL for anyone.
    address sender;
    // Minimum gas price.
    uint256 minGasPrice;
    // Maximum gas price.
    uint256 maxGasPrice;
    // MTX is invalid after this time.
    uint256 expirationTimeSeconds;
    // Nonce to make this MTX unique.
    uint256 salt;
    // Encoded call data to a function on the exchange proxy.
    bytes callData;
    // Amount of ETH to attach to the call.
    uint256 value;
    // ERC20 fee `signer` pays `sender`.
    //IERC20TokenV06 feeToken;
    // ERC20 fee amount.
    uint256 feeAmount;
}

}
    

