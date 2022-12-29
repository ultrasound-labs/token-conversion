# Token Conversion 💱

A simple contract that allows for the conversion of one token to a stream of another token at fixed conversion terms. Specifically, the conversion terms include the following:
- Conversion price
- Stream duration
- Expiration of the conversion program

Note that the implementation assumes that both tokens (in and out) use the same precision.

## Requirements

**Important:** The implementation makes specific assumptions about `tokenIn` and `tokenOut` tokens which translate to strict requirements about the token pair for which the conversion contract is deployed. 

Specifically, these requirements are:
- 18 decimals precision for both tokens (strictly speaking, the requirement is that both tokens use the same precision but deploying the contract with low-decimal precision tokens may result in the loss of funds)
- Safe ERC20 implementation (specifically, `transfer` and `burn` need to revert if unsuccessful)

Note that the former requirement is enforced in the conversion contract's constructor but the latter is not. Hence, always make sure the desired token pair adheres to these requirements.

## Installation
This repository uses Foundry for building and testing and Solhint for formatting the contracts.
If you do not have Foundry already installed, you'll need to run the commands below.

### Install Foundry
```sh
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### Set .env
Copy and update contents from `.env.example` to `.env`

## Tests

After installing dependencies with `make`, run `make test` to run the tests.

Note that tests run on forked mainnet state so make sure the RPC endpoint is properly configured in the `.env` file.

## Building and testing

```sh
git clone https://github.com/ultrasound-labs/token-conversion.git
cd token-conversion
make # This installs the project's dependencies.
make test # This runs forked mainnet tests.
```

## Changes

Listed in the [CHANGELOG.md](./CHANGELOG.md) file which follows the https://keepachangelog.com/en/1.0.0/ format. 
