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
    struct ReserveData<phantom CoinType1, phantom CoinType2> has copy, store {
        r0: u64,
        r1: u64,
        ts: u64,
    }

    /// Reserve Info
    struct PoolData<phantom CoinType1, phantom CoinType2, phantom PoolType> has key {
        reserves: CoinsStore<CoinType1, CoinType2>,
        reserves_data: ReserveData<CoinType1, CoinType2>,
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

        // let owner_addr = signer::address_of(owner);

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
            18,
            true,
        );
        // abandon freeze
        coin::destroy_freeze_cap(freeze_cap);
        // store mint & burn
        move_to(owner, Caps<PoolToken<CoinType1, CoinType2>> { mint: mint_cap, burn: burn_cap });
        // INIT PoolData
        let reserve = CoinsStore<CoinType1, CoinType2> {r0: coin::zero<CoinType1>(), r1: coin::zero<CoinType2>()};
        let reserve_data = ReserveData<CoinType1, CoinType2> {r0: 0, r1: 0, ts: 0};
        // store PoolData
        move_to(owner, PoolData<CoinType1, CoinType2, PoolToken<CoinType1, CoinType2>> { reserves: reserve, reserves_data: reserve_data });

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
        let pool_data = borrow_global<PoolData<CoinType1, CoinType2, PoolToken<CoinType1, CoinType2>>>(@UniswapV2);

        // Mint Amount
        let (amount0, amount1, mintAmount) = Math::amount_to_share(pool_data.reserves_data.r0, pool_data.reserves_data.r1, amount0, amount1, pool_data.reserves_data.ts);

        // Transfer To Pool
        let pool_store = borrow_global_mut<PoolData<CoinType1, CoinType2, PoolToken<CoinType1, CoinType2>>>(@UniswapV2);
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
        let pool_data = borrow_global_mut<PoolData<CoinType1, CoinType2, PoolToken<CoinType1, CoinType2>>>(@UniswapV2);

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
    ) : u64 acquires PoolData {

        let user_addr = signer::address_of(user);

        // Transfer To Pool
        let pool_store = borrow_global_mut<PoolData<CoinType1, CoinType2, PoolToken<CoinType1, CoinType2>>>(@UniswapV2);

        // swap
        let amountOut;
        if (zeroForOne) {
            // getAmountOut
            amountOut = Math::get_amount_out(amountIn, pool_store.reserves_data.r0, pool_store.reserves_data.r1);
            // withdraw user token0
            let tokenIn = coin::withdraw<CoinType1>(user, amountIn);
            coin::merge(&mut pool_store.reserves.r0, tokenIn);
            pool_store.reserves_data.r0 = pool_store.reserves_data.r0 + amountIn;
            // Send user token1
            let tokenOut = coin::extract(&mut pool_store.reserves.r1, amountOut);
            coin::deposit<CoinType2>(user_addr, tokenOut);
            pool_store.reserves_data.r1 = pool_store.reserves_data.r1 - amountOut;
        } else {
            // getAmountOut
            amountOut = Math::get_amount_out(amountIn, pool_store.reserves_data.r1, pool_store.reserves_data.r0);
            // withdraw user token1
            let tokenIn = coin::withdraw<CoinType2>(user, amountIn);
            coin::merge(&mut pool_store.reserves.r1, tokenIn);
            pool_store.reserves_data.r1 = pool_store.reserves_data.r1 + amountIn;
            // Send user token0
            let tokenOut = coin::extract(&mut pool_store.reserves.r0, amountOut);
            coin::deposit<CoinType1>(user_addr, tokenOut);
            pool_store.reserves_data.r0 = pool_store.reserves_data.r0 - amountOut;
        };

        amountOut

    }

}
