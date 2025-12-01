# 🤖 Starlight CLI (星光通用大模型聊天客户端)

**Version 1.5.0**

Starlight CLI 是一个基于 R 语言构建的轻量级、功能丰富的终端大模型（LLM）聊天客户端。它支持流式响应、自动会话管理、历史记录压缩以及多种对话控制指令，旨在提供纯粹、高效的命令行交互体验。

Starlight CLI is a lightweight, feature-rich terminal-based Large Language Model (LLM) chat client built with R. It features streaming responses, automatic session management, history compression, and various conversation control commands, designed to provide a pure and efficient command-line interaction experience.

------------------------------------------------------------------------

## ✨ 主要特性 / Key Features

-   **流式响应 (Streaming Output)**: 实时逐字显示 AI 回复，支持“思维链” (Chain of Thought) 内容的高亮显示。
    -   *Real-time token streaming with syntax highlighting for "Chain of Thought" reasoning.*
-   **智能会话管理 (Smart Session Management)**:
    -   自动生成会话标题 (Auto-generated session titles based on context).
    -   支持保存、恢复、切换 (`/switch`) 和删除 (`/delete`) 会话。
    -   *Save, restore, switch, and delete sessions locally.*
-   **上下文优化 (Context Optimization)**:
    -   **历史压缩**: 使用 `/compress` 指令将长对话总结为摘要，节省 Token 并保留核心记忆。
    -   *History compression via `/compress` to summarize long chats and save tokens.*
    -   **长期记忆**: 支持通过 `/setmemory` 注入长期记忆槽位。
    -   *Long-term memory injection via `/setmemory`.*
-   **文件读取 (File Loading)**: 通过 `/addtext` 将本地文本文件加载到对话上下文中。
    -   *Load local text files into context using `/addtext`.*
-   **多模型支持 (Multi-Model Support)**: 兼容 OpenAI 格式 API，支持动态切换模型 (`/setmodel`)。
    -   *Compatible with OpenAI-format APIs, allowing dynamic model switching.*

------------------------------------------------------------------------

## 🛠️ 安装要求 / Prerequisites

确保您的系统已安装 **R 语言环境** (Recommend R \>= 4.0.0)。

Ensure you have **R environment** installed (Recommend R \>= 4.0.0).

### 📦 依赖包 / Dependencies

在 R 控制台运行以下命令安装所需依赖： Run the following command in your R console to install dependencies:

``` r
install.packages(c("optparse", "httr", "jsonlite", "yaml", "cli", "crayon"))
```

------------------------------------------------------------------------

## ⚙️ 配置 / Configuration

在脚本同级目录下创建一个名为 `.env` 的文件，使用 YAML 格式配置您的 API 信息。 Create a `.env` file in the same directory using YAML format to configure your API credentials.

**示例 / Example `.env`:**

``` yaml
# 提供商名称 (Provider Name)
deepseek:
  baseurl: "https://api.deepseek.com/v1/chat/completions"
  api_key: "sk-your-api-key-here"
  model: 
    - "deepseek-chat"
    - "deepseek-coder"

openai:
  baseurl: "https://api.openai.com/v1/chat/completions"
  api_key: "sk-your-openai-key"
  model:
    - "gpt-4o"
    - "gpt-3.5-turbo"
```

------------------------------------------------------------------------

## 🚀 使用方法 / Usage

### 1. 赋予执行权限 / Make Executable

``` bash
chmod +x starlight.R
```

### 2. 启动对话 / Start Chat

``` bash
# 默认启动
./starlight.R

# 指定提供商和模型 / Specify provider and model
./starlight.R -p deepseek -m deepseek-chat

# 单次问答模式 / Single shot question
./starlight.R -q "解释一下量子纠缠"
```

### 3. 命令行参数 / Arguments

| 参数 / Flag | 全称 / Long Flag | 描述 / Description |
|:-----------------------|:-----------------------|:-----------------------|
| `-p` | `--provider` | 选择 `.env` 中的提供商配置 / Select provider from `.env` |
| `-m` | `--model` | 指定使用的模型名称 / Specify model name |
| `-S` | `--system` | 设置系统提示词 (System Prompt) / Set System Prompt |
| `-s` | `--show_reasoning` | 显示推理过程 (默认开启) / Show reasoning trace (Default: True) |
| `-q` | `--question` | 单次提问并退出 / Ask a single question and exit |
| `-r` | `--resume` | 恢复加载最新对话 / Resume latest conversation(Default: FALSE) |

------------------------------------------------------------------------

## 🎮 指令指南 / Command Guide

在对话过程中，输入以下指令进行控制： Type the following commands during the chat for control:

### 📂 会话管理 / Session Management

-   `/newsession`: 创建一个新的对话会话 / Create a new session.
-   `/switch`: 列出并切换到历史会话 / List and switch to history sessions.
-   `/sessions`: 查看所有已保存的会话 / View all saved sessions.
-   `/delete [file]`: 删除指定的会话文件 / Delete a specific session file.
-   `/title [text]`: 手动修改当前会话标题 / Manually rename session title.
-   `/quit` 或 `/exit`: 保存并退出 / Save and exit.

### 🧠 记忆与上下文 / Memory & Context

-   `/clean`: 清空当前对话历史 / Clear current conversation history.
-   `/compress`: 压缩历史记录为摘要 / Compress history into a summary.
-   `/history`: 查看完整对话记录 (含压缩前历史) / View full history (including pre-compressed).
-   `/setmemory [text]`: 添加长期记忆 / Append to long-term memory.
-   `/delmemory` :删除长期记忆 / Delete some long-term memory items.
-   `/addtext [path]`: 读取文件内容并发送 / Read and send file content.

### ⚙️ 系统设置 / System Settings

-   `/init`: 重新初始化 API 配置 / Re-initialize API config.
-   `/setmodel [name]`: 切换当前模型 / Switch current model.
-   `/lsmodel`: 从服务器获取可用模型列表 / Fetch available models from server.
-   `/systemprompt`: 修改系统提示词 (System Prompt) / Modify System Prompt.
-   `/execute [cmd]`: 执行系统 Shell 命令 / Execute system shell command.

------------------------------------------------------------------------

## 📂 文件结构 / File Structure

-   `starlight.R`: 主程序脚本 / Main script.
-   `.env`: 配置文件 (需手动创建) / Configuration file (Create manually).
-   `chat_logs/`: 存放所有对话历史 JSON 文件的目录 / Directory storing all chat history JSON files.

------------------------------------------------------------------------

## 📝 License

此项目仅供学习和个人使用。 This project is for educational and personal use only.
