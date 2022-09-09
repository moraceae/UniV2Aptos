module UniswapV2::PoolV3 {

    // use std::signer;
    use std::error;
    use std::string;

    // use UniswapV2::Math;

    use aptos_framework::coin::{Self, MintCapability, BurnCapability, Coin};

    //
    // Errors
    //

    const COIN_NOT_REGITER: u64 = 1;
    const POOL_REGITERED: u64 = 2;

    //
    // Data structures
    //

    /// 0.003%
    struct FeeType0 {}

    /// Represents `LP` coin with `CoinType1` and `CoinType2` coin types.
    struct PoolToken<phantom CoinType1, phantom CoinType2, phantom FeeType> {}

    /// Token Resource
    struct CoinsStore<phantom CoinType1, phantom CoinType2> has store {
        r0: Coin<CoinType1>,
        r1: Coin<CoinType2>,
    }

    struct Slot0 has store {
        sqrtPrice: u64,
        tick: u64, // -880000 880000   ==  0 1760000
        feeGrowthGlobal0X128: u64,
        feeGrowthGlobal1X128: u64,
        liquidity: u64,
    }

    struct Config has store {
        tick_spacing: u64, // 60
        fee_rate: u64, //  x / 100
    }

    /// Reserve Info
    struct PoolData<phantom CoinType1, phantom CoinType2> has key {
        reserves: CoinsStore<CoinType1, CoinType2>,
        slot0: Slot0,
        config_data: Config,
    }

    struct TickInfo<phantom CoinType1, phantom CoinType2> has key {
        liquidityGross: u64,
        liquidityNet: u64,
        is_positive: bool,
        feeGrowthOutside0X128: u64,
        feeGrowthOutside1X128: u64,
        initialized: bool,
    }

    struct PositionInfo<phantom CoinType1, phantom CoinType2> has key {
        liquidity: u64,
        feeGrowthInside0LastX128: u64,
        feeGrowthInside1LastX128: u64,
        tokensOwed0: u64,
        tokensOwed1: u64,
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
        assert!(!coin::is_coin_initialized<PoolToken<CoinType1, CoinType2, FeeType0>>(), error::invalid_argument(POOL_REGITERED));

        // Get Symbol
        let symbol0 = coin::symbol<CoinType1>();
        let symbol1 = coin::symbol<CoinType2>();
        string::append(&mut symbol0, symbol1);

        // Depoloy LpToken
        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<PoolToken<CoinType1, CoinType2, FeeType0>>(
            owner,
            symbol0,
            string::utf8(b"LP-V3"),
            6,
            false,
        );
        // abandon freeze
        coin::destroy_freeze_cap(freeze_cap);
        // store mint & burn
        move_to(owner, Caps<PoolToken<CoinType1, CoinType2, FeeType0>> { mint: mint_cap, burn: burn_cap });
        // INIT PoolData
        let reserve = CoinsStore<CoinType1, CoinType2> {r0: coin::zero<CoinType1>(), r1: coin::zero<CoinType2>()};
        let slot_data = Slot0 {sqrtPrice: 0, tick: 0, feeGrowthGlobal0X128: 0, feeGrowthGlobal1X128: 0, liquidity: 0};
        let config_data = Config { tick_spacing: 60, fee_rate: 10 };
        // store PoolData
        move_to(owner, PoolData<CoinType1, CoinType2> { reserves: reserve, slot0: slot_data, config_data: config_data });

    }

    public entry fun initialize<CoinType1, CoinType2>(owner: &signer, sqrtPrice: u64) {

    }

    //
    // Tests
    //

    #[test_only]
    use std::debug;
    // use aptos_framework::aptos_account;
    use UniswapV2::MockTokens;

    #[test(owner = @0xe43e88c9c01cd2515367a3c7a74cbfa5817c965910f9a9ab91c65f72a2b5a47f)]
    public fun test_pool(owner: signer) {

        // Register USDT & USDC
        MockTokens::register_coins(&owner);
        debug::print(&b"USDC & USDT");

        // Create pool
        create_pool<MockTokens::USDT, MockTokens::USDC>(&owner);

    }

}


