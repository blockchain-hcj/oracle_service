// SPDX-License-Identifier: MIT

module oracle_service::pricefeed {

    use std::vector;
    use std::string::{String};
    use std::simple_map::{Self, SimpleMap, borrow, borrow_mut, contains_key};
    use std::bcs::{to_bytes};
    use std::capability::{Self, Cap};
    use std::block::{get_block_info}; 
    use std::oracle;


    const ETokenOracleNotExist: u64 = 1000;
    const ETokenNotUpdated: u64 = 1001;
    const ETokenNotNonNative: u64 = 1002;



    struct DataSource has key{
        oracle_pair_id: SimpleMap<address, String>,
        token_updated_blocks: SimpleMap<address, vector<u64>>,
        round_data: SimpleMap<vector<u8>, u256>,
        token_decimals: SimpleMap<address, u64>,
        non_native: vector<address>
    }
    

    struct ADMIN has drop {}

    struct RequestKey has drop, copy {
        token_type: address,
        block_number: u64
    }

     fun init_module(deployer: &signer) {
            move_to(
            deployer,
            DataSource{
                oracle_pair_id:  simple_map::create(),
                token_updated_blocks: simple_map::create(),
                round_data:  simple_map::create(),
                token_decimals:  simple_map::create(),
                non_native: vector::empty()
                }
            );
            capability::create<ADMIN>(deployer, &ADMIN{});
     }
    
    public entry fun set_token_config(account: &signer, token_type: address,  _oracle_pair_id: String) acquires DataSource {
            acquire_admin_cap(account);
           let data_source = borrow_global_mut<DataSource>(@oracle_service);

            let oracle_pair_id_map = &mut data_source.oracle_pair_id;
            let token_decimals_map =  &mut data_source.token_decimals;
            let (_, _, decimals) =  oracle::get_price(_oracle_pair_id);
            if(contains_key(oracle_pair_id_map, &token_type)){
                 let oracle_pair_id_value = borrow_mut(oracle_pair_id_map, &token_type);
                 *oracle_pair_id_value = _oracle_pair_id;
                 let token_decimals_value = borrow_mut(token_decimals_map, &token_type);
                 *token_decimals_value = decimals;
             }else{
                simple_map::add(oracle_pair_id_map, token_type, _oracle_pair_id);
                simple_map::add(token_decimals_map, token_type, decimals);
             };
    }

    public entry fun set_non_native_token_config(account: &signer, token_type: address, token_decimals: u64) acquires DataSource{
            acquire_admin_cap(account); 
            let data_source = borrow_global_mut<DataSource>(@oracle_service);
            let token_decimals_map =  &mut data_source.token_decimals;
             if(!vector::contains(&data_source.non_native, &token_type)){
                vector::push_back(&mut data_source.non_native, token_type);
                simple_map::add(token_decimals_map, token_type, token_decimals); 
             }
    }




    #[view]
    public fun lastest_round_data(token_type: address): (u256, u64) acquires DataSource {
        let data_source = borrow_global<DataSource>(@oracle_service);
        assert!(contains_key(& data_source.token_updated_blocks, &token_type), ETokenNotUpdated);
        let updated_blocks = borrow(& data_source.token_updated_blocks, &token_type);
        let update_length = vector::length<u64>(updated_blocks);
        let latest_update_block = vector::borrow<u64>(updated_blocks, update_length - 1);
        let request_key = RequestKey{
            token_type: copy token_type,
            block_number: *latest_update_block
        };
        let key = to_bytes(&request_key);
        let round_data = borrow(&data_source.round_data, &key);
        let decimals = borrow(&data_source.token_decimals, &token_type);
        return (*round_data, *decimals)
    }

    #[view]
    public fun get_token_at_block_height_price(token_type: address, height: u64): (u256, u64) acquires DataSource {

       let data_source = borrow_global<DataSource>(@oracle_service); 
       let request_key = RequestKey{
            token_type: token_type,
            block_number: height
        };
        let key = to_bytes(&request_key);
        let round_data = borrow(&data_source.round_data, &key);
        let decimals = borrow(&data_source.token_decimals, &token_type);
        return (*round_data, *decimals)
    }

    #[view]
    public fun get_privious_update_round_block_height(token_type:address, height: u64):u64 acquires DataSource {
        let data_source = borrow_global<DataSource>(@oracle_service);
        let updated_blocks = borrow(& data_source.token_updated_blocks, &token_type);
        let (_, index) = vector::index_of(updated_blocks, &height);
        return *vector::borrow(updated_blocks, index - 1)
        
    }


    #[view]
    public fun get_last_update_block_height(token_type:address) :u64 acquires DataSource {
        let data_source = borrow_global<DataSource>(@oracle_service);
        let updated_blocks = borrow(& data_source.token_updated_blocks, &token_type);
        let length = vector::length(updated_blocks);
       return *vector::borrow(updated_blocks, length - 1)
    }


    public entry fun update_token_price(token_types: vector<address>) acquires DataSource{
   
        let data_source = borrow_global_mut<DataSource>(@oracle_service);

        let tokens_length = vector::length(&token_types);
        let i = 0;
        while (i < tokens_length) {
            let token_type = vector::borrow(&token_types, i);
            assert!(contains_key(& data_source.oracle_pair_id, token_type), ETokenOracleNotExist);
             let (block_height, _) = get_block_info();
             let oracle_pair_id = borrow(&data_source.oracle_pair_id, token_type);

        //set updated block
         if(contains_key(&data_source.token_updated_blocks, token_type)){
            let updated_blocks = borrow_mut(&mut data_source.token_updated_blocks, token_type);
            vector::push_back(updated_blocks, block_height);
         }else{
            let v = vector::empty<u64>();
            vector::push_back(&mut v, block_height);
             simple_map::add(&mut data_source.token_updated_blocks, *token_type, v); 
         };
        //set round data

        let (price, _, _) =  oracle::get_price(*oracle_pair_id);
        let request_key = RequestKey{
            token_type: *token_type,
            block_number: block_height
        };
        let key = to_bytes(&request_key);
        simple_map::add(&mut data_source.round_data, key, price);

            i = i + 1
        };
        
    }


     public entry fun update_non_native_token_price(account: &signer, token_type: address, price: u256) acquires DataSource{
        acquire_admin_cap(account);
        let data_source = borrow_global_mut<DataSource>(@oracle_service);
        assert!(vector::contains(&data_source.non_native, &token_type), ETokenNotNonNative);
        let (block_height, _) = get_block_info(); 

          if(contains_key(&data_source.token_updated_blocks, &token_type)){
            let updated_blocks = borrow_mut(&mut data_source.token_updated_blocks, &token_type);
            vector::push_back(updated_blocks, block_height);
         }else{
            let v = vector::empty<u64>();
            vector::push_back(&mut v, block_height);
             simple_map::add(&mut data_source.token_updated_blocks, token_type, v); 
         };


        let request_key = RequestKey{
            token_type: token_type,
            block_number: block_height
        };
        let key = to_bytes(&request_key);
        simple_map::add(&mut data_source.round_data, key, price);

     }
   




   

    fun acquire_admin_cap(account: &signer): Cap<ADMIN> {
        capability::acquire<ADMIN>(account, &ADMIN{})
    }

    

}   