# Analysis of AI Potentials and Limitations in Secure Software Development for Industry 4.0

## ℹ️️ Project Information

⭐ **Financier:** FAPESP

📝 **Project ID:** #2024/01415-4

🏛️ **Institution:** Escola Politécnica da Universidade de São Paulo (USP), Brazil

📅 **Duration:** March 1, 2024 – February 28, 2026

📁 **Repository Structure:** Consult [here](/Repo_Structure.md)


## 📌 Project Overview
This project investigates the role of **Large Language Models (LLMs)** and AI-assisted tools in **Industry 4.0 applications** related areas, such as decentralized applications (dApps). Our main goal was to quantitatively measure code assistants capabilities in generating secure Solidity smart contracts. To do that, we evaluated:

- ✅ **Basic functional correctness** of LLM-generated code.
- ✅ **Security vulnerabilities** in LLM-generated smart contracts.

### 🎯 Key Objectives
1. **Benchmark Solidity Analyzers:** Determine the current state-of-the-art in Solidity code vulnerability detection tools.
2. **Generated code Testing:** Verify wether AI-assistants were able to implement functional and, most importantly, secure smart contracts.
3. **Benchmark Development:** Design rigorous evaluation frameworks for smart contract security tools.


## 🔬 Research Methodology
### 1. **Selected AI Tools**

For this project, We selected some of the most popular LLM assistants assistants available. All selected models were accessed and utilized through their respective providers' chat-bot interfaces, as detailed in the table below. In addition to commercial offerings, some of the selected developers alo provide similar or identical open-source models.

| Tool Name | Open-Source Available | Link |
|:---------:|:---------------------:|:----:|
| ChatGPT   | ❌                    | [OpenAI](https://openai.com/index/hello-gpt-4o) |
| Claude    | ❌                    | [Anthropic](https://claude.ai) |
| Gemini    | ❌                    | [Google](https://deepmind.google/technologies/gemini/pro) |
| Deepseek  | ✅                    | [DeepSeek](https://github.com/inferless/Deepseek-coder-6.7b-instruct) |
| Qwen      | ✅                    | [Alibaba](https://huggingface.co/Qwen/Qwen2.5-Coder-7B-Instruct) |
| LeChat    | ✅                    | [MistralAI](https://chat.mistral.ai/chat) |

### 2. **Smart Contract Applications**
The project tested the previously presented LLMs on developing five decentralized applications (dApps):

<table style="width: 100%; border-collapse: collapse;">
  <thead>
    <tr>
      <th style="text-align: center; padding: 8px;">Category</th>
      <th style="text-align: center; padding: 8px;">Use Case</th>
      <th style="text-align: center; padding: 8px;">Description</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td style="text-align: center; padding: 8px;">Tokenization</td>
      <td style="text-align: center; padding: 8px;">Notary office</td>
      <td style="text-align: justify; padding: 8px;">Second generation blockchains, such as Ethereum, enable the verifiable ownership of digital and real-world items. We chose a <code>notary office</code> as the most natural use case in this category.</td>
    </tr>
    <tr>
      <td style="text-align: center; padding: 8px;">Financial Services</td>
      <td style="text-align: center; padding: 8px;">Financial pool</td>
      <td style="text-align: justify; padding: 8px;">Blockchains tend to support an underlying cryptocurrency, making it ideal for financial services. We selected the <code>financial pool</code> use case for this category.</td>
    </tr>
    <tr>
      <td style="text-align: center; padding: 8px;">Digital Marketplace</td>
      <td style="text-align: center; padding: 8px;">Medicine prescription and purchase</td>
      <td style="text-align: justify; padding: 8px;">Blockchain's immutability combined with IoT can be used to effectively manage supply chains. In this category, we chose a <code>medicine prescription and purchase supply-chain system</code> use case.</td>
    </tr>
    <tr>
      <td style="text-align: center; padding: 8px;">Decentralized Decision Making</td>
      <td style="text-align: center; padding: 8px;">Condominium assemblies</td>
      <td style="text-align: justify; padding: 8px;">Blockchain tokens can represent voting power in decision-making processes. A prime example is the automatization of <code>condominium assemblies</code>, which we selected for this category.</td>
    </tr>
    <tr>
      <td style="text-align: center; padding: 8px;">Exchange Wallet</td>
      <td style="text-align: center; padding: 8px;">Bridge</td>
      <td style="text-align: justify; padding: 8px;">The emergence of different blockchain networks has led to the need for converting between them, a process called *bridge*. We chose a <code>bridge supporting wallet</code> this use case for implementation.</td>
    </tr>
  </tbody>
</table>

More information on each of the decentralized application above can be found [here](/More_Information/Decentralized_Application.md).

### 3. **Vulnerability Detection**
To assert the presence of vulnerabilities in LLM generated smart contracts, we employed [SmartBugs](https://github.com/smartbugs/smartbugs), a framework that seamlessly combine several state-of-the-art vulnerability detection tools. Specifically, we executed those tools that supported the analysis of Solidity source code. However, before feeding our contracts to SmartBugs, we undertook a process called "flattening", in which imports were resolved by copying the libraries code directly into the script. To do that we utilized HardHat's [flatten](https://v2.hardhat.org/hardhat-runner/docs/advanced/flattening) functionality.


## 📊 Key Findings

### 🔍 Benchmarking Solidity Vulnerability Detection Tools
- We noticed important challenges in benchmarking state-of-the-art vulnerability detection tools, particularly the absence of labeled datasets.
- Hence, we developed [VulLab](https://github.com/lsRyan/vullab), a framework that brigs together vulnerability insertion and detection tools, which enables a benchmark dataset to be constructed by collected contract and seamlessly using it to benchmark tools in SmartBugs.
- In that study, we identified Slither and Solhint as prime detection tools, while other analyzers presented mixed results.

### ⚙️ Functional Capabilities
- In cases wre the generated  was **not compilable**, mistakes tended to be simple ones, such as comparison of different variable types.
- After correcting compilations error, our tests showed that most of the generated applications were **functional**, with **Claude** excelling in all of the use cases.
- Interestingly, **ChatGPT** showed considerable deviations from our prompts instructions in some cases. Most of the time those, tended to enhance the code. However, in its Inter-Chain Wallet contract the model left some important functionalities out of the implementation.
- More information on our complete [functionality report](/More_Information/Functionalities_Analysis.md).

### ⚠️ Security Vulnerabilities
- Results were mixed among **all LLMs**, as critical and high severity vulnerabilities were present in all contracts. However, most vulnerabilities tented to be of low severity, which is a good sign.
- As expected, the number of vulnerabilities rose as contracts got larger and more complex, with **ChatGPT** and **Gemini** showing the smaller gains in critical and high severity vulnerability count. **LeChat** excelled in smaller, simpler contracts.
- Overall, **Claude** and **Qwen** performed worse, with the largest number of critical and high severity vulnerabilities ([vulnerability classification](/More_Information/Vulnerabilities_Classification.md)).
- More information on our complete [security report](/More_Information/Security_Analysis.md).


## 🤝 How to Cite This Work
Feel free to use our work in your own scientific and technical endeavors! If you do, make sure to cite us using the reference below:

```bibtex
@misc{achjian-2026,
  title = {Analysis of AI Potentials and Limitations in Secure Software Development for Industry 4.0},
  author = {Ryan Weege Achjian and Marcos Antonio Simplicio Junior},
  year = {2026},
  howpublished = {https://github.com/your-username/project-repo}
}
