In here we present our results regarding the security of LLM generated code. The tables bellow record the approximate number of vulnerabilities classified according to our [severity classification](Vulnerabilities_Classification.md).

## Analysis
From our data, it is noteworthy that most significant differences in vulnerability counts are observed in low-severity issues. These primarily consist of warnings or the absence of good coding practices. In contrast, high- and critical-severity vulnerabilities show a more uniform distribution across different LLMs.

A clear trend emerges as code length and complexity increase: the number of vulnerabilities across all severity levels rises considerably. Interestingly, ChatGPT and Gemini exhibit a nearly linear increase in the number of critical and high-severity vulnerabilities, with only a small increase in highly severe issues. Meanwhile, DeepSeek and LeChat demonstrate a more pronounced rise as contract complexity increases. Finally, Claude and Qwen show a substantial growth in the number of high-severity vulnerabilities as contracts become larger, highlightingtheir inability to maintain a secure code in more complex scenarios.

These findings underscore the essential role of human oversight during the development process of decentralized applications, particularly when dealing with highly complex systems, where LLMs scored worse. Such strategies are crucial to mitigating risks associated with security flaws introduced by AI-generated code. However, it is also important to highlight that in simple applications—such as the Notary Office and Condo Voting System—AI assistants did fare well, with few vulnerabilities (none, in the second case) of critical and high severity were identified.

## Notary Office

| Tool Name | Critical | High | Medium | Low | Total |
|:---------:|:--------:|:----:|:------:|:---:|:-----:|
| ChatGPT   | 1        | 2    | 3      | 24  | 30    |
| Gemini    | 1        | 2    | 3      | 20  | 26    |
| Claude    | 1        | 2    | 3      | 22  | 28    |
| DeepSeek  | 1        | 2    | 3      | 31  | 37    |
| Qwen      | 1        | 4    | 6      | 44  | 55    |
| LeChat    | 1        | 1    | 3      | 14  | 19    |

## Financing Pool

| Tool Name | Critical | High | Medium | Low | Total |
|:---------:|:--------:|:----:|:------:|:---:|:-----:|
| ChatGPT   | 2        | 6    | 22     | 124 | 154   |
| Gemini    | 2        | 29   | 20     | 98  | 149   |
| Claude    | 3        | 6    | 20     | 198 | 227   |
| DeepSeek  | 3        | 9    | 15     | 172 | 199   |
| Qwen      | 2        | 8    | 19     | 170 | 199   |
| LeChat    | 1        | 9    | 20     | 191 | 221   |

## Medical Supply-Chain

| Tool Name | Critical | High | Medium | Low | Total |
|:---------:|:--------:|:----:|:------:|:---:|:-----:|
| ChatGPT   | 3        | 16   | 4      | 91  | 114   |
| Gemini    | 5        | 8    | 4      | 86  | 103   |
| Claude    | 9        | 12   | 7      | 108 | 136   |
| DeepSeek  | 4        | 51   | 3      | 47  | 105   |
| Qwen      | 3        | 12   | 4      | 206 | 225   |
| LeChat    | 3        | 9    | 4      | 86  | 102   |

## Condo Voting System

| Tool Name | Critical | High | Medium | Low | Total |
|:---------:|:--------:|:----:|:------:|:---:|:-----:|
| ChatGPT   | 0        | 6    | 9      | 82  | 97    |
| Gemini    | 0        | 6    | 10     | 84  | 100   |
| Claude    | 0        | 5    | 8      | 98  | 111   |
| DeepSeek  | 0        | 48   | 6      | 39  | 93    |
| Qwen      | 0        | 3    | 8      | 103 | 114   |
| LeChat    | 0        | 3    | 8      | 77  | 88    |

## Inter-Chain Wallet

| Tool Name | Critical | High | Medium | Low | Total |
|:---------:|:--------:|:----:|:------:|:---:|:-----:|
| ChatGPT   | 3        | 25   | 17     | 330 | 375   |
| Gemini    | 3        | 30   | 14     | 453 | 497   |
| Claude    | 28       | 59   | 16     | 317 | 410   |
| DeepSeek  | 9        | 33   | 21     | 341 | 404   |
| Qwen      | 21       | 49   | 14     | 444 | 528   |
| LeChat    | 10       | 27   | 25     | 471 | 533   |

We would like to draw particular attention to Anthropic's Claude, a model that has been frequently promoted as a leading solution in secure code generation. Indeed, according to the [SWE-bench benchmark](https://www.swebench.com/), Claude consistently achieves high scores and often leads in the leaderboard. Such good performance has led into significant market traction within the software industry, with the company's models capturing over 40\% of the market share, as [assessed by Menlo Ventures](https://menlovc.com/perspective/2025-mid-year-llm-market-update/).

Despite its overall success in secure code implementation, Claude's did not perform particularly well in our study. Specifically, its code exhibited the highest number of vulnerabilities in various implemented applications. In addition, Claude's implementations were found to be the leading ones in terms of the occurrence of such critical issues. These results highlight an important observation: LLMs that demonstrate strong performance in one domain of secure code development may not necessarily perform equally well in other domains. Hence, it is important to carefully select coding assistants based on their specific strengths and capabilities. Our analysis suggests that task-specific LLMs could offer significant advantages in areas were security is key.

In summary, our results indicate that LLMs are indeed capable of producing functional and secure smart contracts of low to medium complexity. However, when dealing with more complex scenarios, despite some models being able to generate fully operational code, the occurrence of severe vulnerabilities increases significantly. Hence, we emphasize the continued necessity for human developers to exercise careful oversight during the development process.

## Limitations

It is important to note that our work does have some important limitations. First, not all identified vulnerabilities necessarily result directly from the reasoning processes of LLMs during code generation. For example, issues such as function visibility and timestamp dependency—classified as critical and medium severity, respectively—were explicitly defined in our prompt. Specifically, function visibility and the use of the *block.timestamp* variable were predefined by us, meaning that these vulnerabilities reflect decisions made by us, human researchers, rather than the AI models.

Furthermore, different vulnerability detection tools may identify the same vulnerability, as some analyzers support the same issues. However, due to time constraints in our work, we did not identify and remove such duplicates. As a result, the reported counts of the tables above likely overstate the actual number of distinct vulnerabilities present in each contract. Nevertheless, since our primary focus is on comparing different LLMs rather than providing an exact vulnerability count, this limitation has limited impact on the overall conclusions of our analysis.
