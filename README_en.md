# 🤖 Starlight LLM Chat Client (CLI)

This is a versatile command-line interface (CLI) client for large language models (LLMs), developed in R. It's not just powerful, featuring streaming output and multi-provider support, but also boasts a beautifully designed terminal user interface (TUI).

![R Script](https://img.shields.io/badge/Language-R-blue.svg) ![License](https://img.shields.io/badge/License-MIT-green.svg)

## ✨ Key Features

-   **🎨 Beautiful UI**: A colorful terminal interface crafted with `cli` and `crayon`, featuring progress bars, borders, and status icons.
-   **🌊 Streaming Output**: Supports Server-Sent Events (SSE) to deliver a real-time, typewriter-like output, similar to the ChatGPT web interface.
-   **🧠 Reasoning Display**: Perfectly supports reasoning models like DeepSeek-R1, distinguishing and highlighting the model's "thinking process" (Reasoning) from the "final answer".
-   **🎭 System Prompt Support**: Allows customizing the system prompt (persona) via the command line to make the model adopt a specific role.
-   **🔌 Multi-Provider/Multi-Model**: Easily manage multiple API providers (e.g., OpenAI, DeepSeek, Ollama) and models through a `.env` configuration file.
-   **📄 Context-Aware**: Supports automatically loading local documents (like a README) as conversational context.

## 🛠️ Prerequisites

### 1. Install R

Ensure you have the R language environment installed on your system. \### 2. Install Dependencies Open R or RStudio and run the following command to install the necessary libraries:

``` r
install.packages(c("optparse", "httr", "jsonlite", "yaml", "cli", "crayon"))
```

## ⚙️ Configuration Guide

Create a file named `.env` in the same directory as the script. This is a YAML-formatted configuration file used to store API keys and endpoint information (compatible with the OpenAI format).

**Example `.env` file:**

``` yaml
# DeepSeek API
deepseek:
  baseurl: "https://api.deepseek.com/v1/chat/completions"
  api_key: "sk-your-deepseek-key"
  model:
    - "deepseek-chat"
    - "deepseek-reasoner"
# Local Ollama (No Key Required)
ollama:
  baseurl: "http://localhost:11434/v1/chat/completions"
  api_key: "ollama"
  model:
    - "llama3"
    - "qwen2.5"
# Other OpenAI-compatible services
other_provider:
  baseurl: "https://api.example.com/v1/chat/completions"
  api_key: "sk-xxxxxx"
  model:
    - "gpt-4o"
```

## 🚀 Usage

Save the script as `starlight.R`. \### 1. Basic Chat Ask a question using a randomly selected provider and model from your configuration.

``` bash
Rscript starlight.R -q "Hello, please introduce the R language in one sentence"
```

### 2. Set a Persona (System Prompt) 🆕

Use the `-S` or `--system` parameter to set the AI's role.

``` bash
Rscript starlight.R -S "You are an ancient scholar who can only speak in classical Chinese" -q "The weather is nice today"
```

### 3. Specify Provider and Model

Use `-p` to specify the provider (corresponding to a key in `.env`) and `-m` to specify the model name.

``` bash
Rscript starlight.R -p deepseek -m deepseek-reasoner -q "Analyze which is larger, 9.11 or 9.9"
```

### 4. Show/Hide Reasoning Process

By default, the script will display the model's reasoning content if it's provided (like from DeepSeek-R1). You can control this with `-s`.

``` bash
# Hide the reasoning process and only see the final answer
Rscript starlight.R -s FALSE -q "A complex math problem..."
```

### 5. Add a Text File as Context

By default, the script supports adding a text file as context. You can control this with `-t`.

``` bash
# Add a text file as context
Rscript starlight.R -q "I'm a beginner, tell me how to use a supercomputer in a humorous way" --model deepseek-ai/DeepSeek-V3.2-Exp-thinking --use_text inst/example.Rmd
```

## 📋 Parameter Details

| Parameter (Short/Long) | Type | Default Value | Description |
|:---|:---|:---|:---|
| `-q`, `--question` | String | (Default question) | **Required**. The question you want to send to the model. |
| `-S`, `--system` | String | "You are..." | **New**. The system prompt to define the model's behavior/persona. |
| `-p`, `--provider` | String | Random | Specify the provider name configured in the `.env` file. |
| `-m`, `--model` | String | Random | Specify the model name to use. |
| `-s`, `--show_reasoning` | Logical | `TRUE` | Whether to display the model's chain-of-thought/reasoning process (yellow highlight). |
| `-t`, `--use_text` | String | `NULL` | Reads a text file from the specified path to be used as additional context. |

## 🖼️ Preview

The script will produce a colorful, structured output like the following when run:

``` text
════════════════════════════════════════════════════════════════════════════════
    🤖 Starlight LLM Chat Client v1.1
════════════════════════════════════════════════════════════════════════════════
📁 Loading config file .env ... done
🎯 Using specified provider: deepseek
🎲 Randomly selected model: deepseek-reasoner
📋 Configuration Summary
  ├─ Provider:      deepseek
  ├─ Model:         deepseek-reasoner
  ├─ API:           https://api.deepseek.com/v1...
  ├─ System Prompt: You are a professional programmer...
  └─ Reasoning:     ✓ Show
╭──────────────────────────────── User Question ────────────────────────────────╮
│ Write a Hello World in R                                                       │
╰──────────────────────────────────────────────────────────────────────────╯
🚀 Starting Chat
┌────────────────────────────────────────────────────────────────────┐
│ 💭 Reasoning Process                                                        │
│ The user wants a Hello World code snippet in R...                              │
└────────────────────────────────────────────────────────────────────┘
┌────────────────────────────────────────────────────────────────────┐
│ 🤖 AI Response                                                             │
│ Here is a standard Hello World example in R...                               │
└────────────────────────────────────────────────────────────────────┘
✨ Chat Ended
  Thanks for using the Starlight LLM Chat Client!
```

## ❓ FAQ

1.  **Error: `config file not found`**: Please check if the `.env` file exists in the current directory.

2.  **Error regarding `cli_rule` parameter**: This is a known compatibility issue. The latest version of the script includes a backward-compatibility fix. If the problem persists, try upgrading the `cli` package: `install.packages("cli")`.

3.  **Garbled text or incorrect display**: Please ensure your terminal supports UTF-8 encoding and ANSI escape sequences. For Windows users, it is recommended to use Windows Terminal or PowerShell Core.

*Created by fallingstar, with the help of* Gemini 2.5 pro/Gemini 3 pro/claude 4.5.
