module koiz::nft_staking {
  use aptos_framework::account::{Self, SignerCapability};
  use aptos_framework::timestamp;
  use aptos_framework::coin;
  use std::signer::{address_of};
  use std::string::{Self, String};
  use std::vector;
  use aptos_std::simple_map::{Self, SimpleMap};
  use aptos_token::token::{Self, TokenId};
  use koiz::koiz_coin::KoizCoin;
  // #[test_only]
  // use aptos_std::debug;

  const MODULE_KOIZ: address = @koiz;
  const SEC_PER_DAY: u64 = 86400;

  //Error Codes
  const INVALID_ADMIN_ADDR:u64 = 1;
  const ALREADY_INITIALIZED:u64 = 2;
  const ALREADY_ALLOCATED:u64 = 3;
  const INVALID_START_SEC:u64 = 4;
  const INVALID_END_SEC:u64 = 5;
  const INVALID_REWARDS_PER_DAY:u64 = 6;
  const INVALID_REWARD_COIN_TYPE:u64 = 7;
  const INVALID_POOL_ADDR:u64 = 8;
  const NOT_STARTED:u64 = 9;
  const INVALID_NFTS:u64 = 10;
  const NOT_AUTHORIZED: u64 =11;
  const NO_REWARDS: u64 = 12;

  struct StakingStatus has key{
    pool_cap: SignerCapability
  }

  struct PoolState has key{
    //start second where rewards were emitted
    start_sec: u64,
    // number of NFT reward token distributed per day
    rewards_per_day: u64,
    // number of rewards distributed per NFT
    rewards_per_nft: u64,
    // last reward-emitting second
    end_sec: u64,
    //NFT info
    collection_creator: address,
    collection_name: String,
    total_nft_staked: u64,
  }

  struct DepositState has key{
    deposit_info: SimpleMap<TokenId, u64>
  }

  public entry fun init(admin: &signer, collection_creator: address, collection_name: vector<u8>) {
    let admin_addr = address_of(admin);
    assert!(admin_addr == MODULE_KOIZ, INVALID_ADMIN_ADDR);
    assert!(!exists<StakingStatus>(MODULE_KOIZ), ALREADY_INITIALIZED);

    let (pool_signer, pool_signer_cap) = account::create_resource_account(admin, b"koiz_nft_staking");
    move_to(admin, StakingStatus{
      pool_cap: pool_signer_cap
    });

    move_to(&pool_signer, PoolState{
      start_sec: 0,
      rewards_per_day: 0,
      rewards_per_nft: 0,
      end_sec: 0,
      collection_creator,
      collection_name: string::utf8(collection_name),
      total_nft_staked: 0
    });

    if (!coin::is_account_registered<KoizCoin>(address_of(&pool_signer))){
      coin::register<KoizCoin>(&pool_signer);
    };

    if (!coin::is_account_registered<KoizCoin>(admin_addr)){
      coin::register<KoizCoin>(admin);
    };

  }

  public entry fun allocate_rewards(
    admin: &signer,
    start_sec: u64,
    rewards_per_day: u64,
    end_sec: u64
  ) acquires StakingStatus, PoolState
  {
    let admin_addr = address_of(admin);
    assert!(admin_addr == MODULE_KOIZ, INVALID_ADMIN_ADDR);

    let staking_status = borrow_global<StakingStatus>(MODULE_KOIZ);
    let pool_signer = account::create_signer_with_capability(&staking_status.pool_cap);
    let pool_addr = address_of(&pool_signer);

    // assert!(exists<PoolState>(pool_addr), INVALID_POOL_ADDR);

    let pool_state = borrow_global_mut<PoolState>(pool_addr);
    let now = timestamp::now_seconds();
    assert!(pool_state.start_sec == 0, ALREADY_ALLOCATED);
    assert!(start_sec >= now, INVALID_START_SEC);
    assert!(rewards_per_day > 0, INVALID_REWARDS_PER_DAY );
    assert!(end_sec > start_sec, INVALID_END_SEC);

    pool_state.start_sec = start_sec;
    pool_state.rewards_per_day = rewards_per_day;
    pool_state.end_sec = end_sec;

    //transfer reward coin from admin to Pool
    coin::transfer<KoizCoin>(admin, pool_addr, (end_sec - start_sec) * rewards_per_day / SEC_PER_DAY );
  }

  //Allows users to stake multiple NFTs at once
  public entry fun deposit(user: &signer, token_names: vector<vector<u8>>) acquires StakingStatus, PoolState, DepositState{
    let user_addr = address_of(user);
    let staking_status = borrow_global<StakingStatus>(MODULE_KOIZ);
    let pool_signer = account::create_signer_with_capability(&staking_status.pool_cap);
    let pool_addr = address_of(&pool_signer);
    let pool_state = borrow_global_mut<PoolState>(pool_addr);
    assert!(pool_state.start_sec > 0, NOT_STARTED);
    let nft_length = vector::length(&token_names);
    assert!( nft_length > 0, INVALID_NFTS );
    update(pool_state);

    pool_state.total_nft_staked = pool_state.total_nft_staked + nft_length;

    let accRewardPerNFT = pool_state.rewards_per_nft;
    let i:u64 = 0;

    if (exists<DepositState>(user_addr)){
      let deposit_state = borrow_global_mut<DepositState>(user_addr);
      while (i < nft_length){
        let token_name = vector::borrow<vector<u8>>(&token_names, i);
        let token_id = token::create_token_id_raw(
            pool_state.collection_creator,
            pool_state.collection_name,
            string::utf8(*token_name),
            0
        );
        simple_map::add<TokenId, u64>(&mut deposit_state.deposit_info, token_id, accRewardPerNFT);
        //transfer token
        token::direct_transfer(user, &pool_signer, token_id, 1);
        i = i + 1;
      };
    }else{
      let deposit_info = simple_map::create<TokenId, u64>();
      while (i < nft_length){
        let token_name = vector::borrow<vector<u8>>(&token_names, i);
        let token_id = token::create_token_id_raw(
            pool_state.collection_creator,
            pool_state.collection_name,
            string::utf8(*token_name),
            0
        );
        simple_map::add<TokenId, u64>(&mut deposit_info, token_id, accRewardPerNFT);
        //transfer token
        token::direct_transfer(user, &pool_signer, token_id, 1);
        i = i + 1;
      };
      move_to(user, DepositState{
         deposit_info
      });
    };
  }

  public entry fun withdraw(user:&signer, token_names:vector<vector<u8>>)
    acquires StakingStatus, PoolState, DepositState
  {
    let user_addr = address_of(user);
    let staking_status = borrow_global<StakingStatus>(MODULE_KOIZ);
    let pool_signer = account::create_signer_with_capability(&staking_status.pool_cap);
    let pool_addr = address_of(&pool_signer);
    let pool_state = borrow_global_mut<PoolState>(pool_addr);
    let nft_length = vector::length(&token_names);
    assert!( nft_length > 0, INVALID_NFTS );
    update(pool_state);

    pool_state.total_nft_staked = pool_state.total_nft_staked - nft_length;
    let rewardPerNft = pool_state.rewards_per_nft;
    let i:u64 = 0;

    let deposit_state = borrow_global_mut<DepositState>(user_addr);
    let to_claim:u64 = 0;

    while(i < nft_length){
      let token_name = vector::borrow<vector<u8>>(&token_names, i);
      let token_id = token::create_token_id_raw(
          pool_state.collection_creator,
          pool_state.collection_name,
          string::utf8(*token_name),
          0
      );
      assert!(simple_map::contains_key<TokenId, u64>(&deposit_state.deposit_info, &token_id), NOT_AUTHORIZED);
      let ( _, lastRewardPerNft) = simple_map::remove(&mut deposit_state.deposit_info, &token_id);
      to_claim = to_claim + (rewardPerNft - lastRewardPerNft)/100000000;
      //transfer token to user
      token::direct_transfer(&pool_signer, user, token_id, 1);
      i = i + 1;
    };

    //transfer coin to user
    if (to_claim >0){
      //transfer coin to user
      if (!coin::is_account_registered<KoizCoin>(user_addr)){
	      coin::register<KoizCoin>(user);
      };
      coin::transfer<KoizCoin>(&pool_signer, user_addr, to_claim );
    }
  }

  public entry fun claim(user:&signer, token_names:vector<vector<u8>>)
    acquires StakingStatus, PoolState, DepositState
  {
    let user_addr = address_of(user);
    let staking_status = borrow_global<StakingStatus>(MODULE_KOIZ);
    let pool_signer = account::create_signer_with_capability(&staking_status.pool_cap);
    let pool_addr = address_of(&pool_signer);
    let pool_state = borrow_global_mut<PoolState>(pool_addr);
    let nft_length = vector::length(&token_names);

    assert!( nft_length > 0, INVALID_NFTS );

    update(pool_state);

    let rewardPerNft = pool_state.rewards_per_nft;
    let i:u64 = 0;

    let deposit_state = borrow_global_mut<DepositState>(user_addr);

    let claimable:u64 = 0;

    while(i < nft_length){
      let token_name = vector::borrow<vector<u8>>(&token_names, i);
      let token_id = token::create_token_id_raw(
          pool_state.collection_creator,
          pool_state.collection_name,
          string::utf8(*token_name),
          0
      );
      assert!(simple_map::contains_key<TokenId, u64>(&deposit_state.deposit_info, &token_id), NOT_AUTHORIZED);
      let lastRewardPerNft = simple_map::borrow_mut<TokenId, u64>(&mut deposit_state.deposit_info, &token_id);

      let to_claim = (rewardPerNft - *lastRewardPerNft)/100000000;
      *lastRewardPerNft = rewardPerNft;
      claimable = claimable + to_claim;
      i = i + 1;
    };

    assert!(claimable >0, NO_REWARDS);
    //transfer coin to user
    if (!coin::is_account_registered<KoizCoin>(user_addr)){
	      coin::register<KoizCoin>(user);
    };
    coin::transfer<KoizCoin>(&pool_signer, user_addr, claimable );
  }


  fun update(poolState: &mut PoolState){
    let now = timestamp::now_seconds();
    if (now > poolState.end_sec){
      now = poolState.end_sec;
    };
    if (now <= poolState.start_sec) return;
    if (poolState.total_nft_staked == 0){
      poolState.start_sec = now;
      return
    };

    let reward:u64 = (((now - poolState.start_sec) as u128)* (poolState.rewards_per_day as u128)* (100000000 as u128) / (SEC_PER_DAY as u128) as u64);
    poolState.rewards_per_nft = poolState.rewards_per_nft + reward / poolState.total_nft_staked;
    poolState.start_sec = now;
  }

  #[test_only]
  public fun get_resource_account(admin: &signer): signer acquires StakingStatus{
    let admin_addr = address_of(admin);
    let staking_status = borrow_global<StakingStatus>(admin_addr);
    account::create_signer_with_capability(&staking_status.pool_cap)
  }
}