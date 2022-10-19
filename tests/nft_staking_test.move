#[test_only]
module koiz::nft_staking_test{
  use aptos_framework::signer::address_of;
  use aptos_framework::coin::{ Self, MintCapability, FreezeCapability, BurnCapability};
  use aptos_framework::account;
  use aptos_framework::timestamp;
  use std::string::{Self, utf8};
  use aptos_token::token;

  // use aptos_std::debug;

  use koiz::nft_staking;
  use koiz::koiz_coin::KoizCoin;
  const COLLECTION_CREATOR:address= @0x111;
  const COLLECTION_NAME:vector<u8> = b"collection";

  const SEC_PER_DAY: u64 = 86400;
  const REWARDS_PER_DAY: u64 = 10000000; //10KOIZ

  struct KoizCoinCapabilities has key{
    burn_cap: BurnCapability<KoizCoin>,
    freeze_cap: FreezeCapability<KoizCoin>,
    mint_cap: MintCapability<KoizCoin>
  }

  fun create_koiz_coin(
      admin: &signer
  ){
      let (burn_cap, freeze_cap, mint_cap) = coin::initialize<KoizCoin>( admin, utf8(b"koiz"), utf8(b"KOIZ"), 6, true);
      move_to(admin, KoizCoinCapabilities{
          burn_cap,
          freeze_cap,
          mint_cap
      });
  }


  #[test(admin = @koiz)]
  public fun test_init(
    admin: &signer,
  ){
    account::create_account_for_test(address_of(admin));
    create_koiz_coin(admin);
    nft_staking::init(admin, COLLECTION_CREATOR, COLLECTION_NAME );
  }

  #[test(admin = @koiz, aptos_framework = @aptos_framework)]
  public fun test_allocate_rewards(
    admin: &signer,
    aptos_framework: &signer
  ) acquires KoizCoinCapabilities{
    test_init(admin);
    //mint 100KOIZ
    let koiz_coin_cap = borrow_global<KoizCoinCapabilities>(address_of(admin));
    let koiz_coin_minted = coin::mint<KoizCoin>(100000000, &koiz_coin_cap.mint_cap);
    //deposit 100 KOIZ to admin
    coin::deposit(address_of(admin), koiz_coin_minted);

    timestamp::set_time_has_started_for_testing(aptos_framework);
    //10 days
    nft_staking::allocate_rewards(admin, 1, REWARDS_PER_DAY, 864000 + 1);
    assert!( coin::balance<KoizCoin>(address_of(admin)) == 0 , 1);
  }

  #[test(admin = @koiz, aptos_framework = @aptos_framework, user = @0x123, collection_creator = @0x111)]
  public fun test_deposit(
    admin: &signer,
    aptos_framework: &signer,
    user: &signer,
    collection_creator: &signer
  ) acquires KoizCoinCapabilities{
    test_allocate_rewards(admin, aptos_framework);

    let token_names = vector<vector<u8>>[b"token1"];
    //initialize collection_creator & user account
    account::create_account_for_test(address_of(collection_creator));
    account::create_account_for_test(address_of(user));
    //create nft for user
    test_create_token_for_user(collection_creator, user, b"token1");

    let token_id = token::create_token_id_raw(
      address_of(collection_creator),
      utf8(COLLECTION_NAME),
      utf8(b"token1"),
      0
    );

    assert!(token::balance_of(address_of(user), token_id) == 1, 1);

    nft_staking::deposit(user, token_names);
  }

  //claim
  #[test(admin = @koiz, aptos_framework = @aptos_framework, user = @0x123, collection_creator = @0x111)]
  public fun test_claim(
    admin: &signer,
    aptos_framework: &signer,
    user: &signer,
    collection_creator: &signer
  ) acquires KoizCoinCapabilities{

    test_deposit(admin, aptos_framework, user, collection_creator);
    timestamp::fast_forward_seconds(SEC_PER_DAY * 1 + 1); // passed 1 days
    nft_staking::claim(user, vector<vector<u8>>[b"token1"]);
    assert!(coin::balance<KoizCoin>(address_of(user)) == 1 * REWARDS_PER_DAY , 1);
    //double claim
    // debug::print<u64>(&coin::balance<KoizCoin>(address_of(user)));

    timestamp::fast_forward_seconds(SEC_PER_DAY * 1 ); // passed 1 days
    nft_staking::claim(user, vector<vector<u8>>[b"token1"]);
    // debug::print<u64>(&coin::balance<KoizCoin>(address_of(user)));
    assert!(coin::balance<KoizCoin>(address_of(user)) == 2 * REWARDS_PER_DAY , 1);

  }

  //withdraw
  #[test(admin = @koiz, aptos_framework = @aptos_framework, user = @0x123, collection_creator = @0x111)]
  public fun test_withdraw(
    admin: &signer,
    aptos_framework: &signer,
    user: &signer,
    collection_creator: &signer
  ) acquires KoizCoinCapabilities{
    test_deposit(admin, aptos_framework, user, collection_creator);
    timestamp::fast_forward_seconds(SEC_PER_DAY * 1 + 1); // passed 1 days
    nft_staking::withdraw(user, vector<vector<u8>>[b"token1"]);
    //check nft balance

    let token_id = token::create_token_id_raw(
      address_of(collection_creator),
      utf8(COLLECTION_NAME),
      utf8(b"token1"),
      0
    );

    assert!(token::balance_of(address_of(user), token_id) == 1, 1);

    //check claim balance
    assert!(coin::balance<KoizCoin>(address_of(user)) == 1 * REWARDS_PER_DAY , 1);
    
    //claim, too. error
    // nft_staking::claim(user, vector<vector<u8>>[b"token1"]);
    // debug::print<u64>(&coin::balance<KoizCoin>(address_of(user)));

  }


  fun test_create_token_for_user(collection_creator: &signer, user: &signer, token_name: vector<u8>){
    //create collection
    token::create_collection(
      collection_creator,
      utf8(COLLECTION_NAME),
      utf8(b""), // description
      utf8(b""), // uri
      100,
      vector<bool>[false, false, false]
    );
    // create token
    token::create_token_script(
        collection_creator,
        utf8(COLLECTION_NAME),
        utf8(token_name),
        utf8(b""), //token_description
        1,
        1,
        utf8(b""),
        address_of(collection_creator),
        100,  //royalty_points_denominator
        100,  //royalty_points_numerator
        vector<bool>[ false, false, false, false, false, false ],
        vector<string::String>[],
        vector<vector<u8>>[],
          vector<string::String>[]
    );

    let token_data_id = token::create_token_data_id(
      address_of(collection_creator),
      utf8(COLLECTION_NAME),
      utf8(token_name)
    );
    let token_id = token::create_token_id(token_data_id, 0);
    token::direct_transfer(collection_creator,user, token_id, 1);
  }

  // // fun create_account<CoinType>(user: &signer, amount: u64) acquires AptosCoinTest{
  // //   let user_addr = address_of(user);
  // //   account::create_account_for_test(user_addr);

  // //   let aptosCoinTest = borrow_global<AptosCoinTest<CoinType>>(@koiz);

  // //   let minted_coin = coin::mint<CoinType>(amount, &aptosCoinTest.mint_cap);
  // //   if (!coin::is_account_registered<CoinType>(user_addr)){
  // //     managed_coin::register<CoinType>(user);
  // //   };
  // //   coin::deposit<CoinType>(user_addr, minted_coin);
  // // }
}