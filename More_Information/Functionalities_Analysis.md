Here we present the results concerning the compilation success and functionality of the LLMs' generated code. It is important to note that all functional tests were conducted after resolving compilation errors in the generated scripts.

From the tables provided below, we observed that most LLMs were capable of generating smart contracts with functional implementations. Claude demonstrated particularly strong performance by successfully implementing all core functionalities across the selected applications, at least based on our simple functional tests. Gemini, DeepSeek, and Qwen also performed adequately, each managing to implement four out of the five applications. Failures in these cases were attributed to minor issues. LeChat was the only model for which only three out of its implementations functioned correctly.

Interestingly, in some instances ChatGPT showed significant deviations from the prompt specifications, which may reflect an attempt by the model to improve the code based on broader contextual understanding. However, this increased autonomy led to the omission of essential functionalities described in the instructions in certain cases. For example, in the Inter-Chain Wallet application, authorized users were expected to operate under functions tagged as "AUTH," which enabled transactions on behalf of other accounts. While ChatGPT correctly implemented the authorization and revocation process, it failed to include any of the AUTH functions themselves. The generated code can be reviewed [here](../Code/ChatGPT/Wallet.sol). This omission naturally resulted in the non-operational status of this particular functionality. We suspect that similarities between the functions names may have led ChatGPT to perceive those functions as redundant, ultimately removing them from its output.

## Notary Office

| Tool Name | Compilation | Functionalities |
|-----------|-------------|-----------------|
| ChatGPT   | ❌          | ✅             |
| Gemini    | ✅          | ✅             |
| Claude    | ✅          | ✅             |
| DeepSeek  | ❌          | ✅             |
| Qwen      | ❌          | ✅             |
| LeChat    | ❌          | ✅             |

## Financing Pool

| Tool Name | Compilation | Functionalities |
|-----------|-------------|-----------------|
| ChatGPT   | ✅          | ❌             |
| Gemini    | ✅          | ❌             |
| Claude    | ✅          | ✅             |
| DeepSeek  | ✅          | ❌             |
| Qwen      | ✅          | ✅             |
| LeChat    | ✅          | ❌             |

## Medical Supply-Chain

| Tool Name | Compilation | Functionalities |
|-----------|-------------|-----------------|
| ChatGPT   | ✅          | ✅             |
| Gemini    | ✅          | ✅             |
| Claude    | ✅          | ✅             |
| DeepSeek  | ❌          | ✅             |
| Qwen      | ❌          | ✅             |
| LeChat    | ❌          | ✅             |

## Condo Voting System

| Tool Name | Compilation | Functionalities |
|-----------|-------------|-----------------|
| ChatGPT   | ✅          | ✅             |
| Gemini    | ✅          | ✅             |
| Claude    | ✅          | ✅             |
| DeepSeek  | ❌          | ✅             |
| Qwen      | ✅          | ✅             |
| LeChat    | ❌          | ❌             |

## Inter-Chain Wallet

| Tool Name | Compilation | Functionalities |
|-----------|-------------|-----------------|
| ChatGPT   | ✅          | ❌             |
| Gemini    | ✅          | ✅             |
| Claude    | ✅          | ✅             |
| DeepSeek  | ❌          | ✅             |
| Qwen      | ❌          | ❌             |
| LeChat    | ❌          | ✅             |