#[test_only]
module koiz::lpfarming_test{
  use aptos_framework::signer::address_of;
  use aptos_framework::coin::{ Self, MintCapability, FreezeCapability, BurnCapability};
  use aptos_framework::account;
  use aptos_framework::timestamp;
  use std::string::utf8;
  // use aptos_std::debug;

  use koiz::lpfarming;
  use koiz::koiz_coin::KoizCoin;

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
    admin: &signer
  ){

    account::create_account_for_test(address_of(admin));
    create_koiz_coin(admin);
    lpfarming::init(admin);

  }
  #[test(admin = @koiz, aptos_framework = @aptos_framework)]
  public fun test_add(
    admin: &signer,
    aptos_framework: &signer
  ) {
    test_init(admin);
    timestamp::set_time_has_started_for_testing(aptos_framework);
    lpfarming::add<KoizCoin>(admin, 100);
  }

  #[test(admin = @koiz, aptos_framework = @aptos_framework)]
   public fun test_new_epoch(
     admin: &signer,
     aptos_framework: &signer
  ) acquires KoizCoinCapabilities{
    test_init(admin); //create POOL list
    timestamp::set_time_has_started_for_testing(aptos_framework);
    lpfarming::add<KoizCoin>(admin, 100); //create POOL

    //mint 1 KOIZ to admin

    let koiz_coin_cap = borrow_global<KoizCoinCapabilities>(address_of(admin));
    let koiz_coin_minted = coin::mint<KoizCoin>(1000000, &koiz_coin_cap.mint_cap);
    //deposit 1 KOIZ to admin
    coin::deposit(address_of(admin), koiz_coin_minted);

    // from 0 second to 86400(1day), reward_per_day= 1 KOIZ
    lpfarming::newEpoch(admin, 0, 86400, 1000000); //1 day
  }

  #[test(admin = @koiz, aptos_framework = @aptos_framework, user=@0x123)]
  public fun test_deposit(
    admin: &signer,
    aptos_framework: &signer,
    user: &signer
  ) acquires KoizCoinCapabilities{
    test_init(admin); //create POOL list
    timestamp::set_time_has_started_for_testing(aptos_framework);
    lpfarming::add<KoizCoin>(admin, 100); //create POOL

    //set epoch
    let koiz_coin_cap = borrow_global<KoizCoinCapabilities>(address_of(admin));
    let koiz_coin_minted = coin::mint<KoizCoin>(1000000, &koiz_coin_cap.mint_cap);
    //deposit 1 KOIZ to admin
    coin::deposit(address_of(admin), koiz_coin_minted);
    // from 0 second to 86400(1day), reward_per_day= 1 KOIZ
    lpfarming::newEpoch(admin, 0, 86400, 1000000); //1 day

    account::create_account_for_test(address_of(user));
    coin::register<KoizCoin>(user);
    //mint 1 KOIZ to user
    koiz_coin_minted = coin::mint<KoizCoin>(1000000, &koiz_coin_cap.mint_cap);
    coin::deposit(address_of(user), koiz_coin_minted);
    lpfarming::deposit<KoizCoin>(user, 0, 1000000);
    //check balance of user
    assert!( coin::balance<KoizCoin>(address_of(user)) == 0 , 1);
  }

  #[test(admin = @koiz, aptos_framework = @aptos_framework, user=@0x123)]
  public fun test_claim(
    admin: &signer,
    aptos_framework: &signer,
    user: &signer
  ) acquires KoizCoinCapabilities {
    //deposit 1KOIZ to Pool
    test_deposit(admin, aptos_framework, user);
    //passed 0.5 day
    timestamp::fast_forward_seconds(43200);
    lpfarming::claim<KoizCoin>(user, 0);
    //claim 0.5 KOIZ
    assert!( coin::balance<KoizCoin>(address_of(user)) == 500000 , 1);
    //passed 0.1 day
    timestamp::fast_forward_seconds(8640);
    //claim 0.1 KOIZ
    lpfarming::claim<KoizCoin>(user, 0);
    //total 0.5 + 0.1 KOIZ
    assert!( coin::balance<KoizCoin>(address_of(user)) == 600000 , 1);
  }

  #[test(admin = @koiz, aptos_framework = @aptos_framework, user=@0x123)]
  public fun test_withdraw(
    admin: &signer,
    aptos_framework: &signer,
    user: &signer
  ) acquires KoizCoinCapabilities{
    //deposit 1 KOIZ to Pool
    test_deposit(admin, aptos_framework, user);
    //passed 0.5 day
    timestamp::fast_forward_seconds(43200);
    //withdraw 0.5 KOIZ
    lpfarming::withdraw<KoizCoin>(user, 0, 500000);
    //total 0.5 KOIZ + 0.5 KOIZ (rewards)
    assert!( coin::balance<KoizCoin>(address_of(user)) == 1000000 , 1);
  }

  //test for two user
  #[test(admin = @koiz, aptos_framework = @aptos_framework, user1=@0x123, user2= @0x345)]
  public fun test_claim2(
    admin: &signer,
    aptos_framework: &signer,
    user1: &signer,
    user2: &signer
  ) acquires KoizCoinCapabilities{
    test_init(admin); //create POOL list
    timestamp::set_time_has_started_for_testing(aptos_framework);
    lpfarming::add<KoizCoin>(admin, 100); //create POOL

    //set epoch
    let koiz_coin_cap = borrow_global<KoizCoinCapabilities>(address_of(admin));
    let koiz_coin_minted = coin::mint<KoizCoin>(1000000, &koiz_coin_cap.mint_cap);
    //deposit 1 KOIZ to admin
    coin::deposit(address_of(admin), koiz_coin_minted);
    // from 0 second to 86400(1day), reward_per_day= 1 KOIZ
    lpfarming::newEpoch(admin, 0, 86400, 1000000); //1 day

    account::create_account_for_test(address_of(user1));
    account::create_account_for_test(address_of(user2));
    coin::register<KoizCoin>(user1);
    coin::register<KoizCoin>(user2);
    //mint 1 KOIZ to user1
    koiz_coin_minted = coin::mint<KoizCoin>(1000000, &koiz_coin_cap.mint_cap);
    coin::deposit(address_of(user1), koiz_coin_minted);

    //mint 1 KOIZ to user2
    koiz_coin_minted = coin::mint<KoizCoin>(1000000, &koiz_coin_cap.mint_cap);
    coin::deposit(address_of(user2), koiz_coin_minted);

    //deposit
    lpfarming::deposit<KoizCoin>(user1, 0, 1000000);
    lpfarming::deposit<KoizCoin>(user2, 0, 1000000);

    //passed 1 day
    timestamp::fast_forward_seconds(86400);

    //claim 0.5 KOIZ
    lpfarming::claim<KoizCoin>(user1, 0);
    //claim 0.5 KOIZ
    lpfarming::claim<KoizCoin>(user2, 0);

    assert!( coin::balance<KoizCoin>(address_of(user1)) == 500000 , 1);
    assert!( coin::balance<KoizCoin>(address_of(user2)) == 500000 , 1);
  }
}