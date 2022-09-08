/// Module For Implementation of UniswapV2 Pool
module UniswapV2::Pool {
    use std::signer;
    use std::error;
    use std::string;

    use UniswapV2::Math;

    use aptos_framework::coin::{Self, MintCapability, BurnCapability, Coin};

    //
    // Errors
    //

    const COIN_NOT_REGITER: u64 = 1;
    const POOL_REGITERED: u64 = 2;

    //
    // Data structures
    //

    /// Represents `LP` coin with `CoinType1` and `CoinType2` coin types.
    struct PoolToken<phantom CoinType1, phantom CoinType2> {}

    /// Token Resource
    struct CoinsStore<phantom CoinType1, phantom CoinType2> has store {
        r0: Coin<CoinType1>,
        r1: Coin<CoinType2>,
    }

    /// r0, r1
    struct ReserveData has store {
        r0: u64,
        r1: u64,
        ts: u64,
    }

    struct Config has store {
        fee_rate: u64, //  x / 100
    }

    /// Reserve Info
    struct PoolData<phantom CoinType1, phantom CoinType2> has key {
        reserves: CoinsStore<CoinType1, CoinType2>,
        reserves_data: ReserveData,
        config_data: Config,
    }

    /// Mint & Burn lpToken
    struct Caps<phantom PoolType> has key {
        mint: MintCapability<PoolType>,
        burn: BurnCapability<PoolType>,
    }

    //
    // Public functions
    //

    /// Create Pool to address of Owner
    public entry fun create_pool<CoinType1, CoinType2>(owner: &signer) {

        // Check Coin Valid
        assert!(coin::is_coin_initialized<CoinType1>(), error::invalid_argument(COIN_NOT_REGITER));
        assert!(coin::is_coin_initialized<CoinType2>(), error::invalid_argument(COIN_NOT_REGITER));

        // Token0 & Token1 Order TODO

        // Check Pool Valid
        assert!(!coin::is_coin_initialized<PoolToken<CoinType1, CoinType2>>(), error::invalid_argument(POOL_REGITERED));

        // Get Symbol
        let symbol0 = coin::symbol<CoinType1>();
        let symbol1 = coin::symbol<CoinType2>();
        string::append(&mut symbol0, symbol1);

        // Depoloy LpToken
        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<PoolToken<CoinType1, CoinType2>>(
            owner,
            symbol0,
            string::utf8(b"LP-Token"),
            6,
            false,
        );
        // abandon freeze
        coin::destroy_freeze_cap(freeze_cap);
        // store mint & burn
        move_to(owner, Caps<PoolToken<CoinType1, CoinType2>> { mint: mint_cap, burn: burn_cap });
        // INIT PoolData
        let reserve = CoinsStore<CoinType1, CoinType2> {r0: coin::zero<CoinType1>(), r1: coin::zero<CoinType2>()};
        let reserve_data = ReserveData {r0: 0, r1: 0, ts: 0};
        let config_data = Config { fee_rate: 10 };
        // store PoolData
        move_to(owner, PoolData<CoinType1, CoinType2> { reserves: reserve, reserves_data: reserve_data, config_data: config_data });

    }

    /// add Liq to Pool
    public entry fun add_liquidity<CoinType1, CoinType2>(
        user: &signer,
        amount0: u64,
        amount1: u64,
    ) acquires PoolData, Caps {

        let user_addr = signer::address_of(user);

        // Check User register Pool Token
        if (!coin::is_account_registered<PoolToken<CoinType1, CoinType2>>(user_addr)) {
            coin::register<PoolToken<CoinType1, CoinType2>>(user);
        };

        // Read Pool_data
        // let pool_data = borrow_global<PoolData<CoinType1, CoinType2>>(@UniswapV2);
        let pool_store = borrow_global_mut<PoolData<CoinType1, CoinType2>>(@UniswapV2);

        // Mint Amount
        let (amount0, amount1, mintAmount) = Math::amount_to_share(pool_store.reserves_data.r0, pool_store.reserves_data.r1, amount0, amount1, pool_store.reserves_data.ts);

        // Transfer To Pool

        let res0 = coin::withdraw<CoinType1>(user, amount0);
        coin::merge(&mut pool_store.reserves.r0, res0);
        let res1 = coin::withdraw<CoinType2>(user, amount1);
        coin::merge(&mut pool_store.reserves.r1, res1);

        // udpate PoolStore
        pool_store.reserves_data.r0 = pool_store.reserves_data.r0 + amount0;
        pool_store.reserves_data.r1 = pool_store.reserves_data.r1 + amount1;
        pool_store.reserves_data.ts = pool_store.reserves_data.ts + mintAmount;

        // Mint Pool Token
        let cap = borrow_global<Caps<PoolToken<CoinType1, CoinType2>>>(@UniswapV2);
        let minted_lp = coin::mint<PoolToken<CoinType1, CoinType2>>(mintAmount, &cap.mint);
        coin::deposit<PoolToken<CoinType1, CoinType2>>(user_addr, minted_lp);

    }

    /// remove Liq
    public entry fun remove_liquidity<CoinType1, CoinType2>(
        user: &signer,
        amount: u64,
    ) acquires PoolData, Caps {

        let user_addr = signer::address_of(user);

        // Read Pool_data
        let pool_data = borrow_global_mut<PoolData<CoinType1, CoinType2>>(@UniswapV2);

        // Burn
        let cap = borrow_global<Caps<PoolToken<CoinType1, CoinType2>>>(@UniswapV2);
        coin::burn_from<PoolToken<CoinType1, CoinType2>>(user_addr, amount, &cap.burn);

        // Calculate
        let amount0 = pool_data.reserves_data.r0 * amount / pool_data.reserves_data.ts;
        let amount1 = pool_data.reserves_data.r1 * amount / pool_data.reserves_data.ts;

        // Transfer To User
        let tokenOut0 = coin::extract(&mut pool_data.reserves.r0, amount0);
        coin::deposit<CoinType1>(user_addr, tokenOut0);
        let tokenOut1 = coin::extract(&mut pool_data.reserves.r1, amount1);
        coin::deposit<CoinType2>(user_addr, tokenOut1);

        // udpate PoolStore
        pool_data.reserves_data.r0 = pool_data.reserves_data.r0 - amount0;
        pool_data.reserves_data.r1 = pool_data.reserves_data.r1 - amount1;
        pool_data.reserves_data.ts = pool_data.reserves_data.ts - amount;

    }

    /// swap Token
    public entry fun swap<CoinType1, CoinType2>(
        user: &signer,
        amountIn: u64,
        // minAmountOut: u64,
        zeroForOne: bool,
    ) acquires PoolData {

        let user_addr = signer::address_of(user);

        // Transfer To Pool
        let pool_store = borrow_global_mut<PoolData<CoinType1, CoinType2>>(@UniswapV2);

        // Fee Collect
        let fee = amountIn * pool_store.config_data.fee_rate / 100;
        let amount_in_without_fee = amountIn - fee;

        // swap
        if (zeroForOne) {
            // getAmountOut
            let amountOut = Math::get_amount_out(amount_in_without_fee, pool_store.reserves_data.r0, pool_store.reserves_data.r1);
            // withdraw user token0
            let tokenIn = coin::withdraw<CoinType1>(user, amountIn);
            coin::merge(&mut pool_store.reserves.r0, tokenIn);
            pool_store.reserves_data.r0 = pool_store.reserves_data.r0 + amount_in_without_fee;
            // Send user token1
            let tokenOut = coin::extract(&mut pool_store.reserves.r1, amountOut);
            coin::deposit<CoinType2>(user_addr, tokenOut);
            pool_store.reserves_data.r1 = pool_store.reserves_data.r1 - amountOut;
        } else {
            // getAmountOut
            let amountOut = Math::get_amount_out(amount_in_without_fee, pool_store.reserves_data.r1, pool_store.reserves_data.r0);
            // withdraw user token1
            let tokenIn = coin::withdraw<CoinType2>(user, amountIn);
            coin::merge(&mut pool_store.reserves.r1, tokenIn);
            pool_store.reserves_data.r1 = pool_store.reserves_data.r1 + amount_in_without_fee;
            // Send user token0
            let tokenOut = coin::extract(&mut pool_store.reserves.r0, amountOut);
            coin::deposit<CoinType1>(user_addr, tokenOut);
            pool_store.reserves_data.r0 = pool_store.reserves_data.r0 - amountOut;
        }

    }

    //
    // Tests
    //

    #[test_only]
    use std::debug;
    use aptos_framework::aptos_account;
    use UniswapV2::MockTokens;

    #[test_only]
    public fun get_balance<CoinType>(
        user: &signer
    ) : u64 {
        let user_addr = std::signer::address_of(user);
        coin::balance<CoinType>(user_addr)
    }

    #[test_only]
    public fun get_reserves<CoinType1, CoinType2>() : (u64, u64, u64) acquires PoolData {
        // Read Pool_data
        let pool_data = borrow_global<PoolData<CoinType1, CoinType2>>(@UniswapV2);
        (pool_data.reserves_data.r0, pool_data.reserves_data.r1, pool_data.reserves_data.ts)

    }

    #[test(owner = @0xe43e88c9c01cd2515367a3c7a74cbfa5817c965910f9a9ab91c65f72a2b5a47f, alice = @66, bob = @67)]
    public fun test_pool(
        owner: signer,
        alice: signer,
        bob: signer,
    ) acquires PoolData, Caps {

        // Register USDT & USDC
        MockTokens::register_coins(&owner);
        debug::print(&b"USDC & USDT");

        // Register Alice & Mint
        let alice_addr = signer::address_of(&alice);
        aptos_account::create_account(alice_addr);
        MockTokens::register<MockTokens::USDT>(&alice);
        MockTokens::mint_coin<MockTokens::USDT>(&owner, alice_addr, 100000);
        MockTokens::register<MockTokens::USDC>(&alice);
        MockTokens::mint_coin<MockTokens::USDC>(&owner, alice_addr, 100000);
        // Print
        debug::print<address>(&alice_addr);
        debug::print(&get_balance<MockTokens::USDT>(&alice));
        debug::print(&get_balance<MockTokens::USDC>(&alice));

        // Register Bob & Mint
        let bob_addr = signer::address_of(&bob);
        aptos_account::create_account(bob_addr);
        MockTokens::register<MockTokens::USDT>(&bob);
        MockTokens::mint_coin<MockTokens::USDT>(&owner, bob_addr, 100000);
        MockTokens::register<MockTokens::USDC>(&bob);
        MockTokens::mint_coin<MockTokens::USDC>(&owner, bob_addr, 100000);
        debug::print<address>(&bob_addr);
        debug::print(&get_balance<MockTokens::USDT>(&bob));
        debug::print(&get_balance<MockTokens::USDC>(&bob));

        // Create pool
        create_pool<MockTokens::USDT, MockTokens::USDC>(&owner);
        let (r0, r1, ts) = get_reserves<MockTokens::USDT, MockTokens::USDC>();
        debug::print(&r0);
        debug::print(&r1);
        debug::print(&ts);

        // Add liq
        add_liquidity<MockTokens::USDT, MockTokens::USDC>(&alice, 50000, 50000);
        let (r0, r1, ts) = get_reserves<MockTokens::USDT, MockTokens::USDC>();
        debug::print(&r0);
        debug::print(&r1);
        debug::print(&ts);

        // Swap
        debug::print<address>(&alice_addr);
        debug::print(&get_balance<MockTokens::USDT>(&alice));
        debug::print(&get_balance<MockTokens::USDC>(&alice));
        swap<MockTokens::USDT, MockTokens::USDC>(&alice, 1000, true);
        debug::print<address>(&alice_addr);
        debug::print(&get_balance<MockTokens::USDT>(&alice));
        debug::print(&get_balance<MockTokens::USDC>(&alice));

        let (r0, r1, ts) = get_reserves<MockTokens::USDT, MockTokens::USDC>();
        debug::print(&r0);
        debug::print(&r1);
        debug::print(&ts);

    }

}
