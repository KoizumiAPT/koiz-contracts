module koiz::koiz_coin {
    use aptos_framework::managed_coin;
    use std::signer;
    struct KoizCoin {}

    const MODULE_KOIZ: address = @koiz;

    //error codes
    const NOT_AUTHORIZED: u64 = 1;

    public entry fun init_coin(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == MODULE_KOIZ, NOT_AUTHORIZED);
        managed_coin::initialize<KoizCoin>(
            admin,
            b"Koiz Coin",
            b"KOIZ",
            6,
            false,
        );
        managed_coin::register<KoizCoin>(admin);
        managed_coin::mint<KoizCoin>(admin, admin_addr, 1000000 * 1000000);
    }
}
