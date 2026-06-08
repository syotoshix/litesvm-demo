use borsh::{BorshDeserialize, BorshSerialize};
use solana_program::{
    account_info::{next_account_info, AccountInfo},
    entrypoint,
    entrypoint::ProgramResult,
    msg,
    program::invoke,
    program_error::ProgramError,
    pubkey::Pubkey,
    system_instruction,
};

/// On-chain state stored in the vault account.
#[derive(BorshSerialize, BorshDeserialize, Clone, Debug)]
pub struct VaultState {
    pub is_initialized: bool,
    pub admin: Pubkey,
    pub total_deposits: u64,
}

impl VaultState {
    /// Byte size when Borsh-serialized: bool(1) + Pubkey(32) + u64(8)
    pub const SIZE: usize = 41;
}

#[derive(BorshSerialize, BorshDeserialize, Debug)]
pub enum VaultInstruction {
    /// Set the vault's admin. Must be called by the account that will own the vault.
    Initialize { admin: Pubkey },
    /// Deposit lamports from caller into the vault.
    Deposit { amount: u64 },
    /// Admin-only withdrawal.
    ///
    /// ⚠️  VULNERABILITY (CWE-862): The admin's public key is verified but
    /// `admin_account.is_signer` is never checked. An attacker can reference
    /// the admin's pubkey without including their signature, bypassing access
    /// control and draining the vault.
    AdminWithdraw { amount: u64 },
}

entrypoint!(process_instruction);

pub fn process_instruction(
    program_id: &Pubkey,
    accounts: &[AccountInfo],
    instruction_data: &[u8],
) -> ProgramResult {
    let instruction = VaultInstruction::try_from_slice(instruction_data)
        .map_err(|_| ProgramError::InvalidInstructionData)?;

    match instruction {
        VaultInstruction::Initialize { admin } => process_initialize(program_id, accounts, admin),
        VaultInstruction::Deposit { amount } => process_deposit(accounts, amount),
        VaultInstruction::AdminWithdraw { amount } => process_admin_withdraw(accounts, amount),
    }
}

fn process_initialize(
    program_id: &Pubkey,
    accounts: &[AccountInfo],
    admin: Pubkey,
) -> ProgramResult {
    let iter = &mut accounts.iter();
    let vault_account = next_account_info(iter)?;
    let payer = next_account_info(iter)?;

    if !payer.is_signer {
        return Err(ProgramError::MissingRequiredSignature);
    }
    if vault_account.owner != program_id {
        msg!("Vault account must be owned by this program");
        return Err(ProgramError::IllegalOwner);
    }

    let state = VaultState {
        is_initialized: true,
        admin,
        total_deposits: 0,
    };
    state.serialize(&mut &mut vault_account.data.borrow_mut()[..])?;

    msg!("Vault initialized. Admin: {}", admin);
    Ok(())
}

fn process_deposit(accounts: &[AccountInfo], amount: u64) -> ProgramResult {
    let iter = &mut accounts.iter();
    let vault_account = next_account_info(iter)?;
    let depositor = next_account_info(iter)?;
    let system_program = next_account_info(iter)?;

    if !depositor.is_signer {
        return Err(ProgramError::MissingRequiredSignature);
    }

    // CPI to system program: transfer SOL from depositor wallet into the vault
    invoke(
        &system_instruction::transfer(depositor.key, vault_account.key, amount),
        &[depositor.clone(), vault_account.clone(), system_program.clone()],
    )?;

    let mut state = VaultState::try_from_slice(&vault_account.data.borrow())
        .map_err(|_| ProgramError::InvalidAccountData)?;
    state.total_deposits += amount;
    state.serialize(&mut &mut vault_account.data.borrow_mut()[..])?;

    msg!("Deposited {} lamports. Vault total: {}", amount, state.total_deposits);
    Ok(())
}

/// VULNERABLE: Missing signer authorization check.
fn process_admin_withdraw(accounts: &[AccountInfo], amount: u64) -> ProgramResult {
    let iter = &mut accounts.iter();
    let vault_account = next_account_info(iter)?;
    let admin_account = next_account_info(iter)?;
    let destination = next_account_info(iter)?;

    let state = VaultState::try_from_slice(&vault_account.data.borrow())
        .map_err(|_| ProgramError::InvalidAccountData)?;

    if !state.is_initialized {
        return Err(ProgramError::UninitializedAccount);
    }

    // ✓ Public key check — admin's address must match the stored admin
    if state.admin != *admin_account.key {
        msg!("Error: provided admin does not match vault admin");
        return Err(ProgramError::InvalidAccountData);
    }

    // ❌ MISSING SIGNER CHECK — the following guard is absent in the default build.
    //    Compile with --features patched to enable the fix.
    #[cfg(feature = "patched")]
    if !admin_account.is_signer {
        msg!("PATCHED: admin signature required");
        return Err(ProgramError::MissingRequiredSignature);
    }

    let vault_lamports = **vault_account.try_borrow_lamports()?;
    if vault_lamports < amount {
        msg!("Insufficient funds: {} < {}", vault_lamports, amount);
        return Err(ProgramError::InsufficientFunds);
    }

    **vault_account.try_borrow_mut_lamports()? -= amount;
    **destination.try_borrow_mut_lamports()? += amount;

    msg!("Withdrew {} lamports to {}", amount, destination.key);
    Ok(())
}
