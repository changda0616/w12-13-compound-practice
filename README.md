1. In order to execute the script `DeployComp.s.sol`, it's necessary to first create a .env file. Copy the content from .env.example, ensuring you include the account and its corresponding private key needed for deploying the contract on the blockchain.

2. Once your .env file is properly set up, you can establish a local network on your device. Use the following script to deploy the contract:
    ```
    forge script script/DeployComp.s.sol --rpc-url http://localhost:8545  --broadcast --verify -vvvv
    ```
3. For the test file Compound.t.sol, the account specified in the first point is required to serve as an `admin`. This permits changes to the collateral factor or the token price within the oracle.