module koiz::lpfarming{
  use aptos_framework::account::{Self, SignerCapability};
  use std::string::String;
  use std::signer::{address_of};
  use std::vector;
  use aptos_std::simple_map::{Self, SimpleMap};
  use aptos_framework::timestamp;
  use aptos_framework::type_info;
  use aptos_framework::coin;
  use koiz::koiz_coin::KoizCoin;  //reward coin

  // #[test_only]
  // use aptos_std::debug;

  const MODULE_KOIZ: address = @koiz;
  const SEC_PER_DAY: u64 = 86400;

  //Error Codes
  const INVALID_ADMIN_ADDR:u64 = 1;
  const ALREADY_INITIALIZED:u64 = 2;
  const INVALID_START_SEC:u64 =3;
  const INVALID_REWARD_PER_DAY:u64 = 4;
  const INVALID_REWARD_COIN_TYPE:u64 = 5;
  const INVALID_DEPOSIT_COIN_TYPE:u64 = 6;
  const NOT_AUTHORIZED:u64 = 7;
  const INVALID_AMOUNT:u64 = 8;
  const INVALID_USER:u64 = 9;
  const INSUFFICIENT_AMOUNT:u64 = 10;
  const NO_REWARDS: u64 = 11;
  const NOT_INITIALIZED:u64 = 12;

  struct UserPoolInfo has store, drop,copy{
    amount: u64,
    last_acc_reward_per_share: u64
  }

  struct UserInfo has key{
    user_info: SimpleMap<u64, UserPoolInfo>, //map of pid, userPoolInfo
    user_rewards: SimpleMap<u64, u64> // map of pid, reward
  }

  struct PoolInfo has store, drop{
    deposit_coin_type: String,
    alloc_point: u64,
    last_reward_sec: u64,
    acc_reward_per_share: u64,
    deposited_amount: u64
  }

  struct PoolCap has key{
    pool_cap:SignerCapability
  }

  struct EpochInfo has  store, drop{
    start_sec: u64,
    end_sec: u64,
    reward_per_day: u64
  }

  struct Pools has key{
    pool_info: vector<PoolInfo>,
    epoch: EpochInfo,
    total_alloc_point: u64
  }

  public entry fun init(admin:&signer){
    let admin_addr = address_of(admin);
    assert!(admin_addr == MODULE_KOIZ, INVALID_ADMIN_ADDR);
    assert!(!exists<PoolCap>(MODULE_KOIZ), ALREADY_INITIALIZED);
    assert!(coin::is_coin_initialized<KoizCoin>(), NOT_INITIALIZED);

    let (pool_signer, pool_signer_cap) = account::create_resource_account(admin, b"koiz_lpfarming");
    move_to(admin, PoolCap{
      pool_cap: pool_signer_cap
    });

    move_to(&pool_signer, Pools{
      pool_info: vector::empty<PoolInfo>(),
      epoch: EpochInfo{
        start_sec: 0,
        end_sec: 0,
        reward_per_day: 0
      },
      total_alloc_point: 0
    });

    if (!coin::is_account_registered<KoizCoin>(address_of(&pool_signer))){
      coin::register<KoizCoin>(&pool_signer);
    };
    if (!coin::is_account_registered<KoizCoin>(admin_addr)){
      coin::register<KoizCoin>(admin);
    };
  }

  public entry fun newEpoch(
    admin:&signer,
    start_sec: u64,
    end_sec: u64,
    reward_per_day: u64
  ) acquires PoolCap,Pools {
    let admin_addr = address_of(admin);
    assert!(admin_addr == MODULE_KOIZ, NOT_AUTHORIZED);
    let now = timestamp::now_seconds();

    if (start_sec == 0) {
        start_sec = now;
    }else{
      assert!( start_sec >= now, INVALID_START_SEC);
    };
    assert!(reward_per_day != 0, INVALID_REWARD_PER_DAY);

    let (pool_addr, pool_signer) = get_pool_signer();

    let pools = borrow_global_mut<Pools>(pool_addr);
    let epoch = &mut pools.epoch;
    mass_update_pools(&mut pools.pool_info, epoch, pools.total_alloc_point);

    let remaining_rewards = epoch.reward_per_day * (epoch.end_sec - sec_number(epoch)) / SEC_PER_DAY;
    let new_rewards = reward_per_day * (end_sec - start_sec) / SEC_PER_DAY;
    epoch.start_sec = start_sec;
    epoch.end_sec = end_sec;
    epoch.reward_per_day = reward_per_day;
    if (remaining_rewards > new_rewards) {
      //transfer from pool to user
      coin::transfer<KoizCoin>(&pool_signer, admin_addr, remaining_rewards - new_rewards);
    }else if ( remaining_rewards < new_rewards ){
        coin::transfer<KoizCoin>(admin, pool_addr, new_rewards - remaining_rewards);
    };
  }

  public entry fun add<DepositCoinType>(admin:&signer, alloc_point:u64)
   acquires PoolCap,Pools
  {
    let admin_addr = address_of(admin);
    assert!(admin_addr == MODULE_KOIZ, NOT_AUTHORIZED);
    assert!(coin::is_coin_initialized<DepositCoinType>(), NOT_INITIALIZED);
    let (pool_addr, _ ) = get_pool_signer();

    let pools = borrow_global_mut<Pools>(pool_addr);

    mass_update_pools(&mut pools.pool_info, &pools.epoch, pools.total_alloc_point);

    let last_reward_sec = sec_number(&pools.epoch);
    pools.total_alloc_point = pools.total_alloc_point + alloc_point;
    vector::push_back<PoolInfo>(&mut pools.pool_info, PoolInfo{
      deposit_coin_type: type_info::type_name<DepositCoinType>(),
      alloc_point,
      last_reward_sec,
      acc_reward_per_share: 0,
      deposited_amount: 0
    });
  }

  public entry fun set(admin:&signer, pid: u64, alloc_point: u64)
   acquires PoolCap,Pools,
  {
    let admin_addr = address_of(admin);
    assert!(admin_addr == MODULE_KOIZ, NOT_AUTHORIZED);
    let (pool_addr, _) = get_pool_signer();
    let pools = borrow_global_mut<Pools>(pool_addr);

    mass_update_pools(&mut pools.pool_info, &pools.epoch, pools.total_alloc_point);

    let pool = vector::borrow_mut<PoolInfo>(&mut pools.pool_info, pid);
    let prev_alloc_point  = pool.alloc_point;
    pool.alloc_point = alloc_point;
    if (prev_alloc_point != alloc_point){
      pools.total_alloc_point = pools.total_alloc_point - prev_alloc_point + alloc_point;
    };
  }

  public entry fun deposit<DepositCoinType>(user: &signer, pid: u64, amount: u64)
   acquires PoolCap,Pools, UserInfo
  {
    let user_addr = address_of(user);
    let (pool_addr, pool_signer) = get_pool_signer();
    let pools = borrow_global_mut<Pools>(pool_addr);
    let pool = vector::borrow_mut<PoolInfo>(&mut pools.pool_info, pid);
    assert!( pool.deposit_coin_type == type_info::type_name<DepositCoinType>(), INVALID_DEPOSIT_COIN_TYPE);

    update_pool(pool, &pools.epoch, pools.total_alloc_point);

    if (!exists<UserInfo>(user_addr)){
      let user_pool_info = UserPoolInfo{
        amount: 0,
        last_acc_reward_per_share: 0
      };

      let user_info = simple_map::create<u64, UserPoolInfo>();
      simple_map::add<u64, UserPoolInfo>(&mut user_info, pid, user_pool_info);
      let user_rewards = simple_map::create<u64,u64>();
      simple_map::add(&mut user_rewards, pid, 0);
      move_to(user, UserInfo{
        user_info,
        user_rewards
      });
    }else{
        let user_info = borrow_global_mut<UserInfo>(user_addr);
        if ( !simple_map::contains_key(&user_info.user_info, &pid)){
            let user_pool_info = UserPoolInfo{
                  amount: 0,
                  last_acc_reward_per_share: 0
            };
            simple_map::add(&mut user_info.user_info, pid, user_pool_info);
            simple_map::add(&mut user_info.user_rewards, pid, 0);
        }
    };

    let user_info = borrow_global_mut<UserInfo>(user_addr);
    let user_pool_info = simple_map::borrow_mut(&mut user_info.user_info, &pid);

    withdraw_reward(pool, pid, user_pool_info, &mut user_info.user_rewards);

    pool.deposited_amount = pool.deposited_amount + amount;
    user_pool_info.amount = user_pool_info.amount + amount;

    if (!coin::is_account_registered<DepositCoinType>(pool_addr)){
      coin::register<DepositCoinType>(&pool_signer);
    };

    coin::transfer<DepositCoinType>(user, pool_addr, amount);
  }

  public entry fun withdraw<DepositCoinType>(user:&signer, pid:u64, amount:u64)
    acquires PoolCap,Pools, UserInfo
  {
    assert!(amount !=0, INVALID_AMOUNT);

    let user_addr = address_of(user);
    let (pool_addr, pool_signer) = get_pool_signer();
    let pools = borrow_global_mut<Pools>(pool_addr);

    let pool = vector::borrow_mut<PoolInfo>(&mut pools.pool_info, pid);
    assert!( pool.deposit_coin_type == type_info::type_name<DepositCoinType>(), INVALID_DEPOSIT_COIN_TYPE);

    update_pool(pool, &pools.epoch, pools.total_alloc_point);

    assert!(exists<UserInfo>(user_addr), INVALID_USER);

    let user_info = borrow_global_mut<UserInfo>(user_addr);
    let user_pool_info = simple_map::borrow_mut(&mut user_info.user_info, &pid);
    let user_rewards = user_info.user_rewards;
    assert!(user_pool_info.amount >= amount, INSUFFICIENT_AMOUNT);

    withdraw_reward(pool, pid, user_pool_info, &mut user_rewards);
    pool.deposited_amount = pool.deposited_amount - amount;
    user_pool_info.amount = user_pool_info.amount - amount;
    coin::transfer<DepositCoinType>(&pool_signer, user_addr, amount);

    //claim
    let rewards = simple_map::borrow_mut(&mut user_rewards, &pid);
    if (*rewards == 0) return;
    if (!coin::is_account_registered<KoizCoin>(user_addr)){
      coin::register<KoizCoin>(user);
    };
    coin::transfer<KoizCoin>(&pool_signer, user_addr, *rewards);
    *rewards = 0;
  }

  public entry fun claim<DepositCoinType>(user:&signer, pid: u64)
    acquires PoolCap,Pools, UserInfo
  {
    let user_addr = address_of(user);
    let (pool_addr, pool_signer) = get_pool_signer();
    let pools = borrow_global_mut<Pools>(pool_addr);

    let pool = vector::borrow_mut<PoolInfo>(&mut pools.pool_info, pid);
    assert!( pool.deposit_coin_type == type_info::type_name<DepositCoinType>(), INVALID_DEPOSIT_COIN_TYPE);
    update_pool(pool, &pools.epoch, pools.total_alloc_point);

    let user_info = borrow_global_mut<UserInfo>(user_addr);
    let user_pool_info = simple_map::borrow_mut(&mut user_info.user_info, &pid);
    let user_rewards = user_info.user_rewards;

    withdraw_reward(pool, pid, user_pool_info, &mut user_rewards);

    let rewards = simple_map::borrow_mut(&mut user_rewards, &pid);

    assert!(*rewards != 0, NO_REWARDS);
    if (!coin::is_account_registered<KoizCoin>(user_addr)){
      coin::register<KoizCoin>(user);
    };
    coin::transfer<KoizCoin>(&pool_signer, user_addr, *rewards);
    *rewards = 0;
  }

  fun withdraw_reward(pool: &PoolInfo, pid: u64, user_pool_info: &mut UserPoolInfo, user_rewards: &mut SimpleMap<u64,u64>){
    let acc_reward_per_share = pool.acc_reward_per_share;
    let pending = (( (user_pool_info.amount as u128) * ((acc_reward_per_share - user_pool_info.last_acc_reward_per_share) as u128))/(100000000 as u128) as u64);
    if (pending  != 0) {
      if( simple_map::contains_key(user_rewards, &pid)){
          let rewards = simple_map::borrow_mut(user_rewards, &pid);
          *rewards = *rewards + pending;
      }else{
        simple_map::add(user_rewards, pid, pending);
      }
    };

    user_pool_info.last_acc_reward_per_share = acc_reward_per_share;
  }



  fun mass_update_pools(pool_info: &mut vector<PoolInfo>, epoch: &EpochInfo, total_alloc_point: u64) {
    let length:u64 = vector::length<PoolInfo>(pool_info);
    let i:u64 = 0;
    while ( i < length) {
      update_pool(vector::borrow_mut<PoolInfo>(pool_info, i), epoch, total_alloc_point);
      i = i + 1;
    };
  }

  fun update_pool(pool : &mut PoolInfo, epoch: &EpochInfo, total_alloc_point: u64){
    if (pool.alloc_point == 0){
      return
    };
    let sec_number_ = sec_number(epoch);
    let last_reward_sec = normalize_sec_number(pool.last_reward_sec, epoch);
    if (sec_number_ <= last_reward_sec){
      return
    };

    let lp_supply = pool.deposited_amount;
    if (lp_supply == 0){
      pool.last_reward_sec = sec_number_;
      return
    };
    let reward = (sec_number_ - last_reward_sec) * epoch.reward_per_day * pool.alloc_point / (SEC_PER_DAY * total_alloc_point);

    pool.acc_reward_per_share = pool.acc_reward_per_share + ((reward as u128)* (100000000 as u128) / (lp_supply as u128) as u64);
    pool.last_reward_sec = sec_number_;
  }

  fun sec_number(epoch: &EpochInfo):u64{
    normalize_sec_number(timestamp::now_seconds(), epoch)
  }

  fun normalize_sec_number(sec_number_:u64, epoch: &EpochInfo):u64{
    if (sec_number_ < epoch.start_sec){
      return epoch.start_sec
    };
    if ( sec_number_ > epoch.end_sec) {
      return epoch.end_sec
    };
    sec_number_
  }

  fun get_pool_signer():(address, signer) acquires PoolCap{
    let lpfarming_pool_cap = borrow_global<PoolCap>(MODULE_KOIZ);
    let pool_signer = account::create_signer_with_capability(&lpfarming_pool_cap.pool_cap);
    (address_of(&pool_signer), pool_signer)
  }

  #[test_only]
  public fun get_resource_account(): signer acquires PoolCap{
    let lpfarming_pool_cap = borrow_global<PoolCap>(MODULE_KOIZ);
    account::create_signer_with_capability(&lpfarming_pool_cap.pool_cap)
  }

}
