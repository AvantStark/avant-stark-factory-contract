pub use starknet::{ContractAddress, ClassHash};

#[starknet::interface]
pub trait IPaymentFactory<TContractState> {
    fn create_payment(
        ref self: TContractState,
        store_name: felt252,
        store_wallet_address: ContractAddress,
        payment_token: ContractAddress
    ) -> ContractAddress;
    fn get_payment_class_hash(self: @TContractState) -> ClassHash;
    fn update_payment_class_hash(ref self: TContractState, new_class_hash: ClassHash);
}

#[starknet::contract]
pub mod PaymentFactory {
    use core::num::traits::Zero;
    use starknet::{
        ContractAddress, ClassHash, SyscallResultTrait, syscalls::deploy_syscall,
        get_caller_address, get_contract_address
    };
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerWriteAccess,
        StoragePointerReadAccess
    };
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::security::PausableComponent;

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: PausableComponent, storage: pausable, event: PausableEvent);

    // Ownable Mixin
    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl InternalImpl = OwnableComponent::InternalImpl<ContractState>;

    // Pausable
    #[abi(embed_v0)]
    impl PausableImpl = PausableComponent::PausableImpl<ContractState>;
    impl PausableInternalImpl = PausableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        pausable: PausableComponent::Storage,
        // Store all of the created payments instances' addresses and thei class hashes
        payments: Map::<(ContractAddress, ContractAddress), ClassHash>,
        // Store the class hash of the contract to deploy
        payment_class_hash: ClassHash,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        PausableEvent: PausableComponent::Event,
        PaymentCreated: PaymentCreated,
        ClassHashUpdated: ClassHashUpdated,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ClassHashUpdated {
        pub new_class_hash: ClassHash,
    }

    #[derive(Drop, starknet::Event)]
    pub struct PaymentCreated {
        pub creator: ContractAddress,
        pub contract_address: ContractAddress
    }

    pub mod Errors {
        pub const CLASS_HASH_ZERO: felt252 = 'Class hash cannot be zero';
        pub const ZERO_ADDRESS: felt252 = 'Zero address';
        pub const PAYMENT_NOT_FOUND: felt252 = 'Payment not found';
    }

    #[constructor]
    fn constructor(ref self: ContractState, class_hash: ClassHash, owner: ContractAddress) {
        assert(Zero::is_non_zero(@class_hash), Errors::CLASS_HASH_ZERO);
        self.payment_class_hash.write(class_hash);
        self.ownable.initializer(owner);
    }

    #[external(v0)]
    fn pause(ref self: ContractState) {
        self.ownable.assert_only_owner();
        self.pausable.pause();
    }

    #[external(v0)]
    fn unpause(ref self: ContractState) {
        self.ownable.assert_only_owner();
        self.pausable.unpause();
    }

    #[abi(embed_v0)]
    impl PaymentFactory of super::IPaymentFactory<ContractState> {
        fn create_payment(
            ref self: ContractState,
            store_name: felt252,
            store_wallet_address: ContractAddress,
            payment_token: ContractAddress
        ) -> ContractAddress {
            self.pausable.assert_not_paused();
            let creator = get_caller_address();

            // Create contructor arguments
            let mut constructor_calldata: Array::<felt252> = array![];
            (store_name, store_wallet_address, payment_token).serialize(ref constructor_calldata);

            // Contract deployment
            let (contract_address, _) = deploy_syscall(
                self.payment_class_hash.read(), 0, constructor_calldata.span(), false
            )
                .unwrap_syscall();

            // track new payment instance
            self.payments.write((creator, contract_address), self.payment_class_hash.read());

            self.emit(Event::PaymentCreated(PaymentCreated { creator, contract_address }));

            contract_address
        }

        fn get_payment_class_hash(self: @ContractState) -> ClassHash {
            self.payment_class_hash.read()
        }

        fn update_payment_class_hash(ref self: ContractState, new_class_hash: ClassHash) {
            self.ownable.assert_only_owner();
            assert(Zero::is_non_zero(@new_class_hash), Errors::CLASS_HASH_ZERO);

            self.payment_class_hash.write(new_class_hash);

            self.emit(Event::ClassHashUpdated(ClassHashUpdated { new_class_hash }));
        }
    }
}
