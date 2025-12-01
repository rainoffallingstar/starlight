# 🤖 Starlight CLI (星光通用大模型聊天客户端)

**Version 2.4.0 - RAG Full Edition**

Starlight CLI 是一个基于 R 语言构建的轻量级、功能丰富的终端大模型（LLM）聊天客户端。它支持流式响应、自动会话管理、历史记录压缩、**PDF 文档向量化检索（RAG）**、**多模态图像处理**以及多种对话控制指令，旨在提供纯粹、高效的命令行交互体验。

Starlight CLI is a lightweight, feature-rich terminal-based Large Language Model (LLM) chat client built with R. It features streaming responses, automatic session management, history compression, **PDF vectorization retrieval (RAG)**, **multimodal image processing**, and various conversation control commands, designed to provide a pure and efficient command-line interaction experience.

------------------------------------------------------------------------

## ✨ 主要特性 / Key Features

### 🔥 **2.4.0 新增功能 / New in 2.4.0**

-   **📄 PDF 文档智能检索 (RAG)**:
    -   支持 PDF 文档导入、文本提取和向量化存储。
    -   *PDF import, text extraction, and vectorized storage.*
    -   基于 Embedding API 的智能语义检索，自动注入相关上下文。
    -   *Semantic retrieval based on Embedding API with automatic context injection.*
    -   支持批量向量化、动态分块和 token 限制优化。
    -   *Batch vectorization, dynamic chunking, and token limit optimization.*
-   **🖼️ 多模态图像支持**:
    -   支持本地图片和网络图片的 Base64 编码发送。
    -   *Local and remote image Base64 encoding support.*
    -   自动检测、下载和渲染 AI 生成的图片（支持 iTerm2 内联显示和 ASCII 艺术）。
    -   *Auto-detect, download, and render AI-generated images (iTerm2 inline & ASCII art).*
    -   图片批量管理（添加、查看、清除）。
    -   *Batch image management (add, view, clear).*
-   **🧮 Embedding 配置**:
    -   独立的 Embedding 模型配置（OpenAI、BGE 等）。
    -   *Separate Embedding model configuration (OpenAI, BGE, etc.).*
    -   自动调整分块大小和批次处理策略。
    -   *Automatic chunk size and batch processing strategy adjustment.*

### 🌟 **核心功能 / Core Features**

-   **流式响应 (Streaming Output)**: 实时逐字显示 AI 回复，支持"思维链" (Chain of Thought) 内容的高亮显示。
    -   *Real-time token streaming with syntax highlighting for "Chain of Thought" reasoning.*
-   **智能会话管理 (Smart Session Management)**:
    -   自动生成会话标题 (Auto-generated session titles based on context).
    -   支持保存、恢复、切换 (`/switch`) 和删除 (`/delete`) 会话。
    -   *Save, restore, switch, and delete sessions locally.*
    -   **新增**: PDF 向量数据随会话持久化存储。
    -   *New: PDF vectors persist with sessions.*
-   **上下文优化 (Context Optimization)**:
    -   **历史压缩**: 使用 `/compress` 指令将长对话总结为摘要，节省 Token 并保留核心记忆。
    -   *History compression via `/compress` to summarize long chats and save tokens.*
    -   **长期记忆**: 支持通过 `/setmemory` 注入长期记忆槽位。
    -   *Long-term memory injection via `/setmemory`.*
    -   **新增**: 自动 PDF 上下文注入，无需手动粘贴文档内容。
    -   *New: Automatic PDF context injection without manual copy-paste.*
-   **文件读取 (File Loading)**: 通过 `/addtext` 将本地文本文件加载到对话上下文中。
    -   *Load local text files into context using `/addtext`.*
-   **多模型支持 (Multi-Model Support)**: 兼容 OpenAI 格式 API，支持动态切换模型 (`/setmodel`)。
    -   *Compatible with OpenAI-format APIs, allowing dynamic model switching.*
-   **调试模式 (Debug Mode)**: 使用 `/debug` 或 `-d` 启用详细日志输出。
    -   *Enable verbose logging with `/debug` or `-d`.*

------------------------------------------------------------------------

## 🛠️ 安装要求 / Prerequisites

确保您的系统已安装 **R 语言环境** (Recommend R \>= 4.0.0)。\
Ensure you have **R environment** installed (Recommend R \>= 4.0.0).

### 📦 依赖包 / Dependencies

在 R 控制台运行以下命令安装所需依赖：\
Run the following command in your R console to install dependencies:

``` r
# 核心依赖 / Core dependencies (必须 / Required)
install.packages(c("optparse", "httr", "jsonlite", "yaml", "cli", "crayon", "base64enc"))

# PDF 处理 / PDF processing (必须，用于 RAG / Required for RAG)
install.packages("pdftools")

# 图像处理 / Image processing (可选 / Optional, 用于终端渲染图片 / for terminal image rendering)
install.packages("imager")   # ASCII 艺术渲染 / ASCII art rendering
# 或 / or
install.packages("magick")   # ImageMagick 渲染 / ImageMagick rendering
```

------------------------------------------------------------------------

## ⚙️ 配置 / Configuration

在脚本同级目录下创建一个名为 `.env` 的文件，使用 YAML 格式配置您的 API 信息。\
Create a `.env` file in the same directory using YAML format to configure your API credentials.

### **示例 / Example `.env`**:

``` yaml
# ===========================
# Embedding 配置（用于 PDF RAG）
# Embedding Configuration (for PDF RAG)
# ===========================
embedding:
  url: "https://api.openai.com/v1/embeddings"
  model: "text-embedding-3-small"   # 或 BAAI/bge-m3 等 / or BAAI/bge-m3, etc.
  api_key: "sk-your-embedding-api-key"  # 可选，未设置时使用聊天 API Key / Optional, uses chat API key if not set

# ===========================
# 聊天模型配置 / Chat Model Configuration
# ===========================
deepseek:
  baseurl: "https://api.deepseek.com/v1/chat/completions"
  api_key: "sk-your-deepseek-key"
  model: 
    - "deepseek-chat"
    - "deepseek-reasoner"
  title_model: "deepseek-chat"  # 可选：专用于生成标题的模型 / Optional: dedicated model for title generation

openai:
  baseurl: "https://api.openai.com/v1/chat/completions"
  api_key: "sk-your-openai-key"
  model:
    - "gpt-4o"
    - "gpt-4o-mini"
    - "gpt-3.5-turbo"
  title_model: "gpt-4o-mini"

# 本地模型示例 / Local Model Example (Ollama)
ollama:
  baseurl: "http://localhost:11434/v1/chat/completions"
  api_key: "ollama"  # Ollama 不需要真实 Key / Ollama doesn't need real key
  model:
    - "qwen2.5:32b"
    - "llama3.2-vision"
```

### 📝 配置说明 / Configuration Notes

-   **`embedding`**: 全局 Embedding 配置，用于 PDF 向量化。如果不使用 RAG 功能，可省略此部分。\
    *Global Embedding configuration for PDF vectorization. Can be omitted if RAG is not used.*

-   **`title_model`**: 可选字段，指定用于生成会话标题的模型。如果未设置，将使用当前对话模型。\
    *Optional field to specify a dedicated model for session title generation. If not set, uses the current chat model.*

-   **多提供商支持**: 可配置多个提供商，通过 `-p` 参数选择。\
    *Multi-provider support: configure multiple providers and select with `-p` flag.*

------------------------------------------------------------------------

## 🚀 使用方法 / Usage

### 1. 赋予执行权限 / Make Executable

``` bash
chmod +x starlight.R
```

### 2. 启动对话 / Start Chat

``` bash
# 默认启动（随机选择提供商和模型）
# Default start (random provider and model)
./starlight.R

# 指定提供商和模型 / Specify provider and model
./starlight.R -p deepseek -m deepseek-chat

# 单次问答模式 / Single shot question
./starlight.R -q "解释一下量子纠缠"

# 恢复最新会话 / Resume latest session
./starlight.R -r

# 启用调试模式 / Enable debug mode
./starlight.R -d

# 附带图片提问 / Ask with images
./starlight.R -i "photo.jpg,https://example.com/image.png" -q "描述这些图片"

# 设置图片保存目录 / Set image output directory
./starlight.R -o "./my_images"
```

### 3. 命令行参数 / Arguments

| 参数 / Flag | 全称 / Long Flag | 描述 / Description |
|----|----|----|
| `-p` | `--provider` | 选择 `.env` 中的提供商配置 / Select provider from `.env` |
| `-m` | `--model` | 指定使用的模型名称 / Specify model name |
| `-S` | `--system` | 设置系统提示词 (System Prompt) / Set System Prompt |
| `-s` | `--show_reasoning` | 显示推理过程 (默认开启) / Show reasoning trace (Default: True) |
| `-q` | `--question` | 单次提问并退出 / Ask a single question and exit |
| `-r` | `--resume` | 恢复加载最新对话 / Resume latest conversation (Default: FALSE) |
| `-i` | `--image` | **新增**: 指定图片路径（逗号分隔）/ Specify image paths (comma-separated) |
| `-d` | `--debug` | **新增**: 启用调试模式 / Enable debug mode |
| `-o` | `--output_dir` | **新增**: 设置图片保存目录 / Set image output directory (默认: `image_gen`) |

------------------------------------------------------------------------

## 🎮 指令指南 / Command Guide

在对话过程中，输入以下指令进行控制：\
Type the following commands during the chat for control:

### 📂 会话管理 / Session Management

-   `/newsession`: 创建一个新的对话会话 / Create a new session.
-   `/switch`: 列出并切换到历史会话 / List and switch to history sessions.
-   `/sessions`: 查看所有已保存的会话 / View all saved sessions.
-   `/delete [file]`: 删除指定的会话文件 / Delete a specific session file.
-   `/title [text]`: 手动修改当前会话标题 / Manually rename session title.
-   `/quit` 或 `/exit`: 保存并退出 / Save and exit.

### 🧠 记忆与上下文 / Memory & Context

-   `/clean`: 清空当前对话历史（可选保留图片）/ Clear current conversation history (optional: keep images).
-   `/compress`: 压缩历史记录为摘要 / Compress history into a summary.
-   `/history`: 查看完整对话记录 (含压缩前历史) / View full history (including pre-compressed).
-   `/setmemory [text]`: 添加长期记忆 / Append to long-term memory.
-   `/delmemory`: 删除指定长期记忆条目 / Delete specific long-term memory items.

### 📄 文档处理 (RAG) / Document Processing

-   `/addpdf [path]`: **导入 PDF 文档**，支持三种处理方式：\
    *Import PDF document with three processing modes:*
    1.  **直接添加**: 适合短文档 (\<5000 字) / Direct add: for short docs (\<5000 chars).
    2.  **生成摘要**: AI 总结核心内容 / Generate summary: AI summarizes core content.
    3.  **向量化存储（推荐）**: 智能检索，自动注入上下文 / Vectorization (Recommended): smart retrieval with auto context injection.
-   `/unloadpdf [n]`: **卸载已向量化的 PDF**：\
    *Unload vectorized PDFs:*
    -   输入编号：卸载指定 PDF / Enter number: unload specific PDF.
    -   输入 `all`：卸载所有 PDF / Enter `all`: unload all PDFs.
-   `/addtext [path]`: 读取文本文件内容并发送 / Read and send text file content.

### 🖼️ 图像功能 / Image Features

-   `/image [paths]`: **添加图片**（支持本地路径和 URL，空格分隔）。\
    *Add images (local paths or URLs, space-separated).*\
    示例 / Example: `/image photo.jpg https://example.com/pic.png`

-   `/imageinfo`: 查看当前待发送的图片列表 / View pending image list.

-   `/clearimages`: 清除所有待发送图片 / Clear all pending images.

-   `/imagedir [path]`: 设置 AI 生成图片的保存目录 / Set save directory for AI-generated images.

### ⚙️ 系统设置 / System Settings

-   `/init`: 重新初始化 API 配置 / Re-initialize API config.
-   `/setmodel [name]`: 切换当前模型 / Switch current model.
-   `/lsmodel`: 从服务器获取可用模型列表 / Fetch available models from server.
-   `/systemprompt`: 修改系统提示词 (System Prompt) / Modify System Prompt.
-   `/debug`: **切换调试模式** / Toggle debug mode.
-   `/help`: 显示所有可用指令 / Show all available commands.

------------------------------------------------------------------------

## 📖 RAG 工作流程示例 / RAG Workflow Example

``` bash
# 1. 启动 Starlight CLI
./starlight.R -p openai -m gpt-4o

# 2. 导入 PDF 文档
/addpdf research_paper.pdf
# 选择：3. 向量化存储

# 3. 直接提问（自动检索相关内容）
> 这篇论文的核心结论是什么？
# AI 会自动检索最相关的 3 个文本块并基于此回答

# 4. 查看检索到的片段（调试模式）
/debug
> 文中提到的实验方法有哪些？
# 输出会显示检索到的片段编号、相关度和内容预览

# 5. 卸载不需要的 PDF
/unloadpdf
# 选择编号或输入 all

# 6. 保存会话（PDF 向量数据会自动持久化）
/quit
```

------------------------------------------------------------------------

## 🖼️ 图像处理示例 / Image Processing Example

``` bash
# 1. 添加本地图片
/image photo.jpg diagram.png

# 2. 添加网络图片
/image https://example.com/chart.png

# 3. 查看待发送图片
/imageinfo

# 4. 发送问题（图片会随问题一起发送）
> 分析这些图片的共同特征

# 5. AI 生成图片后自动下载和渲染
# 输出示例：
# ✓ Base64图片已保存: generated_20240115_143022.png
# [图片预览] (ASCII 艺术或 iTerm2 内联显示)

# 6. 清除图片缓存
/clearimages
```

------------------------------------------------------------------------

## 📂 文件结构 / File Structure

```         
.
├── starlight.R          # 主程序脚本 / Main script
├── .env                 # 配置文件 (需手动创建) / Config file (create manually)
├── chat_logs/           # 对话历史 JSON 文件目录 / Chat history JSON files
│   ├── chat_20240115_140000.json
│   └── ...
└── image_gen/           # AI 生成图片保存目录 / AI-generated images (default)
    ├── generated_20240115_143022.png
    └── downloaded_20240115_143030.jpg
```

### **会话 JSON 结构 / Session JSON Structure**

``` json
{
  "session_id": "20240115_140000",
  "title": "量子纠缠原理探讨",
  "created_at": "2024-01-15 14:00:00",
  "updated_at": "2024-01-15 15:30:00",
  "model": "gpt-4o",
  "system_prompt": "你是一个智能助手。",
  "memory": "用户偏好使用中文\n关注科技领域",
  "conversations": [...],
  "compressed_summary": "之前讨论了量子力学基础...",
  "full_history_before_compress": [...],
  "pdf_vectors": {
    "research_paper_20240115140500": {
      "filename": "research_paper.pdf",
      "created_at": "2024-01-15 14:05:00",
      "chunks": ["文本块1", "文本块2", ...],
      "embeddings": [[0.1, 0.2, ...], [0.3, 0.4, ...], ...],
      "chunk_count": 45,
      "embedding_model": "text-embedding-3-small"
    }
  }
}
```

------------------------------------------------------------------------

## 🔧 故障排查 / Troubleshooting

### 问题 1: `pdftools` 安装失败 / `pdftools` Installation Failure

**解决方案 / Solution**:

``` bash
# macOS (需要 Homebrew)
brew install poppler

# Ubuntu/Debian
sudo apt-get install libpoppler-cpp-dev

# 然后重新安装 R 包 / Then reinstall R package
install.packages("pdftools")
```

### 问题 2: Embedding API 返回 413 错误 / Embedding API Returns 413 Error

**原因**: 单个文本块超过模型 token 限制。\
*Reason: Single text chunk exceeds model token limit.*

**解决方案 / Solution**:

1.  在 `.env` 中使用支持更大 token 的模型（如 `text-embedding-3-large`）。\
    *Use a model with larger token limit in `.env` (e.g., `text-embedding-3-large`).*

2.  启用调试模式检查分块大小：\
    *Enable debug mode to check chunk size:*

``` bash
./starlight.R -d
/addpdf large_doc.pdf
```

3.  脚本会自动调整分块策略，但如果仍然失败，尝试减小 PDF 文件大小。\
    *The script auto-adjusts chunking strategy, but if it still fails, try reducing PDF file size.*

### 问题 3: 图片无法在终端显示 / Images Not Rendering in Terminal

**解决方案 / Solution**:

1.  **iTerm2 用户**: 确保使用最新版本。\
    *iTerm2 users: Ensure using the latest version.*

2.  **其他终端**: 安装 `imager` 或 `magick` 包以启用 ASCII 艺术渲染。\
    *Other terminals: Install `imager` or `magick` for ASCII art rendering.*

``` r
install.packages("imager")
# 或 / or
install.packages("magick")
```

3.  图片仍会保存到 `image_gen/` 目录，可以手动查看。\
    *Images are still saved to `image_gen/` and can be viewed manually.*

------------------------------------------------------------------------

## 🎯 最佳实践 / Best Practices

1.  **RAG 使用建议 / RAG Usage Tips**:
    -   单个 PDF 建议 \<100 页 / Recommend \<100 pages per PDF.
    -   使用调试模式检查检索质量 / Use debug mode to check retrieval quality.
    -   定期使用 `/unloadpdf` 清理无关文档 / Regularly clean up irrelevant docs with `/unloadpdf`.
2.  **会话管理 / Session Management**:
    -   长对话使用 `/compress` 节省 token / Use `/compress` for long chats to save tokens.
    -   重要会话使用 `/title` 设置易识别标题 / Set recognizable titles with `/title` for important sessions.
3.  **图片处理 / Image Processing**:
    -   大图片建议压缩后再发送 / Compress large images before sending.
    -   使用 `/imagedir` 自定义保存路径 / Customize save path with `/imagedir`.
4.  **调试技巧 / Debugging Tips**:
    -   遇到问题时先启用 `/debug` / Enable `/debug` when encountering issues.
    -   检查 `.env` 配置格式是否正确 / Check `.env` format correctness.

------------------------------------------------------------------------

## 📝 更新日志 / Changelog

### Version 2.4.0 (2024-01-15)

-   ✨ 新增完整 RAG 支持（PDF 向量化检索）/ Added full RAG support (PDF vectorization retrieval).
-   ✨ 新增多模态图像处理（发送、接收、渲染）/ Added multimodal image processing (send, receive, render).
-   ✨ 新增 Embedding 配置和自适应分块策略 / Added Embedding config and adaptive chunking.
-   ✨ 新增 `/unloadpdf`、`/image`、`/imagedir` 等指令 / Added `/unloadpdf`, `/image`, `/imagedir` commands.
-   🐛 修复 Unicode 处理和编码安全问题 / Fixed Unicode handling and encoding safety.
-   🔧 优化会话持久化（支持 PDF 向量数据存储）/ Optimized session persistence (PDF vector storage).

### Version 1.5.0

-   初始版本，支持基础对话和会话管理 / Initial release with basic chat and session management.

------------------------------------------------------------------------

## 📜 许可证 / License

此项目仅供学习和个人使用。禁止用于商业用途或违反相关 API 服务条款的行为。\
This project is for educational and personal use only. Commercial use or violation of API terms of service is prohibited.

------------------------------------------------------------------------

## 🤝 贡献 / Contributing

欢迎提交 Issue 和 Pull Request！\
Issues and Pull Requests are welcome!

**联系方式 / Contact**: 请在 GitHub 仓库提交 Issue / Please submit issues on GitHub repository.

------------------------------------------------------------------------

## ⭐ Star History

如果这个项目对您有帮助，请给个 Star ⭐！\
If this project helps you, please give it a Star ⭐!
