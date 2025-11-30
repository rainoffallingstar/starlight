# 🤖 Starlight LLM Chat Client (CLI)

这是一个基于 R 语言开发的通用大模型命令行客户端。它不仅功能强大，支持流式输出和多服务商配置，还拥有经过精心设计的美观终端界面（TUI）。

![R Script](https://img.shields.io/badge/Language-R-blue.svg) ![License](https://img.shields.io/badge/License-MIT-green.svg)

## ✨ 主要特性

-   **🎨 精美 UI**: 使用 `cli` 和 `crayon` 打造的彩色终端界面，包含进度条、边框和状态图标。
-   **🌊 流式输出 (Streaming)**: 支持 Server-Sent Events (SSE)，实现类似 ChatGPT 网页版的打字机即时输出效果。
-   **🧠 推理过程展示**: 完美支持 DeepSeek-R1 等推理模型，能够区分并高亮显示模型的“思考过程” (Reasoning) 和“最终回答”。
-   **🎭 System Prompt 支持**: 支持通过命令行自定义系统提示词（人设），让模型扮演特定角色。
-   **🔌 多服务商/多模型**: 通过 `.env` 配置文件轻松管理多个 API 服务商（如 OpenAI, DeepSeek, Ollama 等）和模型。
-   **📄 上下文感知**: 支持自动加载本地文档（如 README）作为对话上下文。

## 🛠️ 环境准备

### 1. 安装 R

确保你的系统已安装 R 语言环境。

### 2. 安装依赖包

打开 R 或 RStudio，运行以下命令安装必要的依赖库：

``` r
install.packages(c("optparse", "httr", "jsonlite", "yaml", "cli", "crayon"))
```

## ⚙️ 配置指南

在脚本同级目录下创建一个名为 `.env` 的文件。这是一个 YAML 格式的配置文件，用于存储 API 密钥和端点信息(兼容openai格式)。

**`.env` 文件示例：**

``` yaml
# DeepSeek API
deepseek:
  baseurl: "https://api.deepseek.com/v1/chat/completions"
  api_key: "sk-your-deepseek-key"
  model:
    - "deepseek-chat"
    - "deepseek-reasoner"

# 本地 Ollama (无需 Key)
ollama:
  baseurl: "http://localhost:11434/v1/chat/completions"
  api_key: "ollama"
  model:
    - "llama3"
    - "qwen2.5"

# 兼容 OpenAI 格式的其他服务
other_provider:
  baseurl: "https://api.example.com/v1/chat/completions"
  api_key: "sk-xxxxxx"
  model:
    - "gpt-4o"
```

## 🚀 使用方法

脚本保存为 `starlight.R`。

### 1. 基础对话

随机选择一个配置的服务商和模型进行提问。

``` bash
Rscript starlight.R -q "你好，请用一句话介绍 R 语言"
```

### 2. 设定人设 (System Prompt) 🆕

使用 `-S` 或 `--system` 参数设定 AI 的角色。

``` bash
Rscript starlight.R -S "你是一个只会说文言文的古代书生" -q "今天天气不错"
```

### 3. 指定服务商和模型

使用 `-p` 指定服务商（对应 `.env` 中的 key），使用 `-m` 指定模型名称。

``` bash
Rscript starlight.R -p deepseek -m deepseek-reasoner -q "分析一下 9.11 和 9.9 哪个大"
```

### 4. 隐藏/显示推理过程

默认情况下，如果模型返回推理内容（如 DeepSeek-R1），脚本会显示它。你可以通过 `-s` 控制。

``` bash
# 隐藏推理过程，只看结果
Rscript starlight.R -s FALSE -q "复杂的数学问题..."
```

### 5. 添加文本文件作为上下文

默认情况下，如果需要添加文本文件作为上下文，脚本会显示它。你可以通过 `-t` 控制。

``` {.bash .bash}
# 添加文本文件作为上下文
Rscript starlight.R  -q "我是小白，使用幽默风趣的语言告诉我怎么使用超算"  --model deepseek-ai/DeepSeek-V3.2-Exp-thinking --use_text inst/example.Rmd
```

## 📋 参数详解

| 参数 (简写/全称) | 类型 | 默认值 | 说明 |
|:-----------------|:-----------------|:-----------------|:-----------------|
| `-q`, `--question` | 字符 | (默认问题) | **必填**。你要发送给模型的问题内容。 |
| `-S`, `--system` | 字符 | "你是一个..." | **新增**。系统提示词，用于设定模型行为/人设。 |
| `-p`, `--provider` | 字符 | Random | 指定 `.env` 文件中配置的服务商名称。 |
| `-m`, `--model` | 字符 | Random | 指定要使用的模型名称。 |
| `-s`, `--show_reasoning` | 逻辑 | `TRUE` | 是否显示模型的思维链/推理过程（黄色高亮）。 |
| `-t`,`--use_text` | 字符 | `NULL` | 读取指定目录的文本文件作为附加上下文。 |

## 🖼️ 运行效果预览

脚本运行时会呈现如下结构的彩色输出：

``` text
════════════════════════════════════════════════════════════════════════════════
    🤖 Starlight LLM 聊天客户端 v1.1
════════════════════════════════════════════════════════════════════════════════

📁 加载配置文件 .env ... done
🎯 使用指定服务商: deepseek
🎲 随机选择模型: deepseek-reasoner

📋 配置摘要
  ├─ 服务商: deepseek
  ├─ 模型:   deepseek-reasoner
  ├─ API:    https://api.deepseek.com/v1...
  ├─ System: 你是一个专业的程序员...
  └─ 推理:   ✓ 显示

╭──────────────────────────────── 用户问题 ────────────────────────────────╮
│ 用 R 语言写一个 Hello World                                              │
╰──────────────────────────────────────────────────────────────────────────╯

🚀 开始对话

┌────────────────────────────────────────────────────────────────────┐
│ 💭 推理过程                                                         │
│ 用户想要 R 语言的 Hello World 代码...                                 │
└────────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────────┐
│ 🤖 AI 回答                                                          │
│ 这是一个标准的 R 语言 Hello World 示例...                             │
└────────────────────────────────────────────────────────────────────┘

✨ 对话结束
  感谢使用 Starlight LLM 聊天客户端！
```

## ❓ 常见问题

1.  **报错 `config file not found`**: 请检查当前目录下是否存在 `.env` 文件。
2.  **报错 `cli_rule` 参数错误**: 这是一个已知兼容性问题，最新版脚本已包含自动降级修复逻辑。如果仍有问题，请尝试升级 `cli` 包：`install.packages("cli")`。
3.  **显示乱码**: 请确保你的终端支持 UTF-8 编码以及 ANSI 转义序列（Windows 用户建议使用 Windows Terminal 或 PowerShell Core）。

------------------------------------------------------------------------

*Created by fallingstar,under the help of* Gemini 2.5 pro/Gemini 3 pro/claude 4.5.
