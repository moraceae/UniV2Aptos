module UniswapV2::Math {

    //
    // Errors
    //

    //
    // Data structures
    //

    //
    // Public functions
    //

    public fun amount_to_share(r0: u64, r1: u64, amount0: u64, amount1: u64, ts: u64): (u64, u64, u64) {

        let mint_amount;
        if (ts == 0) {
            // Should use sqrt(r0*r1);
            if (r0 > r1) {
                mint_amount = amount0;
            } else {
                mint_amount = amount1;
            };
            (amount0, amount1, mint_amount)
        } else {
            let mint0 = amount0 * ts / r0;
            let mint1 = amount1 * ts / r1;
            if (mint0 > mint1) {
                (mint1 * r0 / ts, amount1, mint1)
            } else {
                (amount0, mint0 * r1 / ts, mint0)
            }
        }

    }

    public fun get_amount_out(input_amount: u64, input_reserve: u64, output_reserve: u64): u64 {
        let input_amount_with_fee = input_amount * 997;
        let numerator = input_amount_with_fee * output_reserve;
        let denominator = (input_reserve * 1000) + input_amount_with_fee;
        numerator / denominator
    }

}