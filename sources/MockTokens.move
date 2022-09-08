/// Moduler For Mock Tokens
module UniswapV2::MockTokens {
    use std::signer;
    use std::string::utf8;

    use aptos_framework::coin::{Self, MintCapability, BurnCapability};

    //
    // Errors
    //


    //
    // Data structures
    //

    /// Represents test USDT coin.
    struct USDT {}

    /// Represents test USDC coin.
    struct USDC {}

    /// Storing mint/burn capabilities for `USDT` and `USDC` coins under user account.
    struct Caps<phantom CoinType> has key {
        mint: MintCapability<CoinType>,
        burn: BurnCapability<CoinType>,
    }

    //
    // Public functions
    //

    /// Initializes `USDC` and `USDT` coins.
    public entry fun register_coins(token_admin: &signer) {

        // Initial USDC
        let (usdc_b, usdc_f, usdc_m) = coin::initialize<USDC>(
            token_admin,
            utf8(b"USDC"),
            utf8(b"USDC"),
            6,
            true
        );
        // Initial USDT
        let (usdt_b, usdt_f, usdt_m) = coin::initialize<USDT>(
            token_admin,
            utf8(b"Tether"),
            utf8(b"USDT"),
            6,
            true
        );
        // Destroy Freeze cap
        coin::destroy_freeze_cap(usdc_f);
        coin::destroy_freeze_cap(usdt_f);
        // Move to
        move_to(token_admin, Caps<USDC> { mint: usdc_m, burn: usdc_b });
        move_to(token_admin, Caps<USDT> { mint: usdt_m, burn: usdt_b });

    }

    /// Register Token to User
    public entry fun register<CoinType>(account: &signer) {
        coin::register<CoinType>(account);
    }

    /// Mints new coin `CoinType` on account `acc_addr`.
    public entry fun mint_coin<CoinType>(
        token_admin: &signer,
        acc_addr: address,
        amount: u64
    ) acquires Caps {
        let token_admin_addr = signer::address_of(token_admin);
        let caps = borrow_global<Caps<CoinType>>(token_admin_addr);
        let coins = coin::mint<CoinType>(amount, &caps.mint);
        coin::deposit(acc_addr, coins);
    }

}