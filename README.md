# 🤖 Starlight CLI (星光通用大模型聊天客户端)

**Version 2.5.0 - RAG + Image Generation Edition**

Starlight CLI 是一个基于 R 语言构建的轻量级、功能丰富的终端大模型（LLM）聊天客户端。它支持流式响应、自动会话管理、历史记录压缩、**PDF 文档向量化检索（RAG）**、**多模态图像处理**、**🆕 AI 图片生成**以及多种对话控制指令，旨在提供纯粹、高效的命令行交互体验。

Starlight CLI is a lightweight, feature-rich terminal-based Large Language Model (LLM) chat client built with R. It features streaming responses, automatic session management, history compression, **PDF vectorization retrieval (RAG)**, **multimodal image processing**, **🆕 AI image generation**, and various conversation control commands, designed to provide a pure and efficient command-line interaction experience.

------------------------------------------------------------------------

## ✨ 主要特性 / Key Features

### 🔥 **2.5.0 新增功能 / New in 2.5.0**

-   **🎨 AI 图片生成**:
    -   支持通过 `/imagegen` 指令调用 ModelScope、DALL-E 等图片生成 API。
    -   *AI image generation via* `/imagegen` *command (ModelScope, DALL-E, etc.).*
    -   异步任务管理，自动轮询生成状态。
    -   *Async task management with automatic status polling.*
    -   高级参数支持：负面提示词、尺寸、数量等。
    -   *Advanced parameters: negative prompt, size, quantity, etc.*
    -   自动下载生成的图片并渲染到终端。
    -   *Auto-download and render generated images in terminal.*

### 🌟 **2.4.0 核心功能 / Core Features from 2.4.0**

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

### 💎 **基础功能 / Base Features**

-   **流式响应 (Streaming Output)**: 实时逐字显示 AI 回复，支持"思维链" (Chain of Thought) 内容的高亮显示。
    -   *Real-time token streaming with syntax highlighting for "Chain of Thought" reasoning.*
-   **智能会话管理 (Smart Session Management)**:
    -   自动生成会话标题 (Auto-generated session titles based on context).
    -   支持保存、恢复、切换 (`/switch`) 和删除 (`/delete`) 会话。
    -   *Save, restore, switch, and delete sessions locally.*
    -   PDF 向量和图片生成记录随会话持久化存储。
    -   *PDF vectors and image generation history persist with sessions.*
-   **上下文优化 (Context Optimization)**:
    -   **历史压缩**: 使用 `/compress` 指令将长对话总结为摘要，节省 Token。
    -   *History compression via* `/compress` *to summarize long chats and save tokens.*
    -   **长期记忆**: 支持通过 `/setmemory` 注入长期记忆槽位。
    -   *Long-term memory injection via* `/setmemory`*.*
    -   **自动上下文注入**: PDF 内容和图片自动注入，无需手动粘贴。
    -   *Automatic context injection for PDFs and images without manual copy-paste.*

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

### **示例 / Example** `.env`:

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
# 🆕 图片生成配置
# Image Generation Configuration
# ===========================
imagegen:
  base_url: "https://api-inference.modelscope.cn/"
  model: "Tongyi-MAI/Z-Image-Turbo"
  api_key: "<MODELSCOPE_TOKEN>"
  timeout: 300           # 最大等待时间（秒）/ Max wait time (seconds)
  poll_interval: 5       # 轮询间隔（秒）/ Poll interval (seconds)

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
    - "dall-e-3"  # 🆕 支持图片生成模型 / Image generation model
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

-   `embedding`: 全局 Embedding 配置，用于 PDF 向量化。如果不使用 RAG 功能，可省略此部分。\
    *Global Embedding configuration for PDF vectorization. Can be omitted if RAG is not used.*

-   **🆕** `imagegen`: 图片生成 API 配置，支持 ModelScope、OpenAI DALL-E 等。\
    *Image generation API config, supports ModelScope, OpenAI DALL-E, etc.*

-   `title_model`: 可选字段，指定用于生成会话标题的模型。\
    *Optional field to specify a dedicated model for session title generation.*

-   **多提供商支持**: 可配置多个提供商，通过 `-p` 参数选择。\
    *Multi-provider support: configure multiple providers and select with* `-p` *flag.*

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
| `-r` | `--resume` | 恢复加载最新对话 / Resume latest conversation |
| `-i` | `--image` | 指定图片路径（逗号分隔）/ Specify image paths (comma-separated) |
| `-d` | `--debug` | 启用调试模式 / Enable debug mode |
| `-o` | `--output_dir` | 设置图片保存目录 / Set image output directory (默认: `image_gen`) |

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

-   **🆕** `/imagegen [prompt]`: **AI 生成图片**，支持高级参数：\
    *AI image generation with advanced parameters:*

    -   基础用法 / Basic: `/imagegen A golden cat`
    -   负面提示 / Negative prompt: `/imagegen A cat --negative ugly, blurry`
    -   指定尺寸 / Specify size: `/imagegen A cat --size 1024x1024`
    -   生成多张 / Multiple images: `/imagegen A cat --n 4`
    -   组合使用 / Combined: `/imagegen A sunset --negative clouds --size 512x512 --n 2`

### ⚙️ 系统设置 / System Settings

-   `/init`: 重新初始化 API 配置 / Re-initialize API config.
-   `/setmodel [name]`: 切换当前模型 / Switch current model.
-   `/lsmodel`: 从服务器获取可用模型列表 / Fetch available models from server.
-   `/systemprompt`: 修改系统提示词 (System Prompt) / Modify System Prompt.
-   `/debug`: 切换调试模式 / Toggle debug mode.
-   `/help`: 显示所有可用指令 / Show all available commands.

------------------------------------------------------------------------

## 📖 使用示例 / Usage Examples

### 🎨 图片生成工作流 / Image Generation Workflow

``` bash
# 1. 启动 Starlight CLI
./starlight.R -p openai -m dall-e-3

# 2. 生成基础图片
/imagegen A futuristic city at sunset

# 3. 使用负面提示词优化
/imagegen A beautiful landscape --negative buildings, people

# 4. 生成多张不同尺寸的图片
/imagegen A cute puppy --size 1024x1024 --n 4

# 5. 查看生成的图片
# 图片会自动下载到 image_gen/ 目录并在终端预览

# 6. 结合对话使用
> 帮我设计一个科技感的logo
AI: 我建议使用蓝色和银色的配色...
/imagegen Futuristic tech logo, blue and silver, minimalist --size 512x512

# 7. 保存会话（图片生成记录会自动保存）
/quit
```

### 📄 RAG + 图片生成联动 / RAG + Image Generation Combined

``` bash
# 1. 导入研究报告
/addpdf market_analysis.pdf
# 选择：3. 向量化存储

# 2. 分析数据
> 报告中提到的主要趋势是什么？

# 3. 基于分析生成可视化
/imagegen Create a chart showing the market trends mentioned in the report: [AI总结的趋势]

# 4. 生成演示图片
/imagegen Professional presentation slide about [报告主题] --size 1920x1080
```

### 🖼️ 多模态交互示例 / Multimodal Interaction Example

``` bash
# 1. 上传产品照片
/image product1.jpg product2.jpg

# 2. 请求分析
> 比较这两个产品的设计特点

# 3. 根据反馈生成改进版
/imagegen Improved product design based on: [AI的建议]

# 4. 继续优化
> 能否调整颜色方案？
/imagegen Same design but with warmer color palette
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
└── image_gen/           # 🆕 AI 生成/下载图片保存目录 / AI-generated/downloaded images
    ├── generated_20240115_143022.png
    ├── downloaded_20240115_143030.jpg
    └── ...
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
    *Use a model with larger token limit in* `.env` *(e.g.,* `text-embedding-3-large`*).*

2.  启用调试模式检查分块大小：\
    *Enable debug mode to check chunk size:*

``` bash
./starlight.R -d
/addpdf large_doc.pdf
```

3.  脚本会自动调整分块策略，但如果仍然失败，尝试减小 PDF 文件大小。\
    *The script auto-adjusts chunking strategy, but if it still fails, try reducing PDF file size.*

### 🆕 问题 3: 图片生成超时 / Image Generation Timeout

**原因**: 生成任务耗时过长或网络不稳定。\
*Reason: Generation task takes too long or unstable network.*

**解决方案 / Solution**:

1.  在 `.env` 中增大 `timeout` 值（默认 300 秒）：

``` yaml
imagegen:
  timeout: 600  # 增加到 10 分钟
```

2.  检查网络连接和 API 服务状态。

3.  启用调试模式查看详细错误信息：

``` bash
./starlight.R -d
/imagegen A complex scene
```

### 问题 4: 图片无法在终端显示 / Images Not Rendering in Terminal

**解决方案 / Solution**:

1.  **iTerm2 用户**: 确保使用最新版本。\
    *iTerm2 users: Ensure using the latest version.*

2.  **其他终端**: 安装 `imager` 或 `magick` 包以启用 ASCII 艺术渲染。\
    *Other terminals: Install* `imager` *or* `magick` *for ASCII art rendering.*

``` r
install.packages("imager")
# 或 / or
install.packages("magick")
```

3.  图片仍会保存到 `image_gen/` 目录，可以手动查看。\
    *Images are still saved to* `image_gen/` *and can be viewed manually.*

------------------------------------------------------------------------

## 🎯 最佳实践 / Best Practices

1.  **RAG 使用建议 / RAG Usage Tips**:
    -   单个 PDF 建议 \<100 页 / Recommend \<100 pages per PDF.
    -   使用调试模式检查检索质量 / Use debug mode to check retrieval quality.
    -   定期使用 `/unloadpdf` 清理无关文档 / Regularly clean up irrelevant docs with `/unloadpdf`.
2.  **图片生成建议 / Image Generation Tips**:
    -   使用详细的提示词获得更好效果 / Use detailed prompts for better results.
    -   负面提示词有助于排除不需要的元素 / Negative prompts help exclude unwanted elements.
    -   生成高分辨率图片时增加 timeout / Increase timeout for high-resolution images.
3.  **会话管理 / Session Management**:
    -   长对话使用 `/compress` 节省 token / Use `/compress` for long chats to save tokens.
    -   重要会话使用 `/title` 设置易识别标题 / Set recognizable titles with `/title` for important sessions.
    -   图片生成记录会自动保存在对话历史中 / Image generation history is auto-saved in conversation history.
4.  **调试技巧 / Debugging Tips**:
    -   遇到问题时先启用 `/debug` / Enable `/debug` when encountering issues.
    -   检查 `.env` 配置格式是否正确 / Check `.env` format correctness.
    -   查看生成任务的 task_id 以便追踪 / Check task_id for tracking generation tasks.

------------------------------------------------------------------------

## 📝 更新日志 / Changelog

### Version 2.5.0 (2025-12-02)

-   ✨ **新增 AI 图片生成功能** / Added AI image generation feature:
    -   支持 ModelScope、DALL-E 等异步图片生成 API / Support for ModelScope, DALL-E async APIs.
    -   `/imagegen` 指令支持高级参数（负面提示、尺寸、数量）/ `/imagegen` command with advanced parameters.
    -   自动任务轮询和状态管理 / Automatic task polling and status management.
    -   生成的图片自动下载并渲染 / Auto-download and render generated images.
-   🔧 优化图片处理流程 / Optimized image processing:
    -   统一图片保存目录管理 / Unified image save directory management.
    -   改进 Base64 图片检测和处理 / Improved Base64 image detection.
-   🐛 修复会话持久化相关 bug / Fixed session persistence bugs.

### Version 2.4.0 (2025-12-01)

-   ✨ 新增完整 RAG 支持（PDF 向量化检索）/ Added full RAG support (PDF vectorization retrieval).
-   ✨ 新增多模态图像处理（发送、接收、渲染）/ Added multimodal image processing (send, receive, render).
-   ✨ 新增 Embedding 配置和自适应分块策略 / Added Embedding config and adaptive chunking.
-   ✨ 新增 `/unloadpdf`、`/image`、`/imagedir` 等指令 / Added `/unloadpdf`, `/image`, `/imagedir` commands.
-   🐛 修复 Unicode 处理和编码安全问题 / Fixed Unicode handling and encoding safety.
-   🔧 优化会话持久化（支持 PDF 向量数据存储）/ Optimized session persistence (PDF vector storage).

### Version 1.5.0

-   初始版本，支持基础对话和会话管理 / Initial release with basic chat and session management.

------------------------------------------------------------------------

## 🌟 功能对比 / Feature Comparison

| 功能 / Feature                   | v1.5.0 | v2.4.0 | v2.5.0 |
|----------------------------------|--------|--------|--------|
| 基础对话 / Basic Chat            | ✅     | ✅     | ✅     |
| 流式响应 / Streaming             | ✅     | ✅     | ✅     |
| 会话管理 / Session Management    | ✅     | ✅     | ✅     |
| 历史压缩 / History Compression   | ✅     | ✅     | ✅     |
| PDF RAG 检索 / PDF RAG Retrieval | ❌     | ✅     | ✅     |
| 图片理解 / Image Understanding   | ❌     | ✅     | ✅     |
| 图片生成 / Image Generation      | ❌     | ❌     | ✅     |
| 调试模式 / Debug Mode            | ❌     | ✅     | ✅     |

------------------------------------------------------------------------

## 📜 许可证 / License

此项目仅供学习和个人使用。禁止用于商业用途或违反相关 API 服务条款的行为。\
This project is for educational and personal use only. Commercial use or violation of API terms of service is prohibited.

------------------------------------------------------------------------

## 🤝 贡献 / Contributing

欢迎提交 Issue 和 Pull Request！\
Issues and Pull Requests are welcome!

**功能建议 / Feature Requests**: - 更多图片生成 API 支持（Stable Diffusion、Midjourney 等） - 语音输入/输出功能 - 更丰富的图片编辑功能（inpainting、outpainting）

**联系方式 / Contact**: 请在 GitHub 仓库提交 Issue / Please submit issues on GitHub repository.

------------------------------------------------------------------------

## ⭐ Star History

如果这个项目对您有帮助，请给个 Star ⭐！\
If this project helps you, please give it a Star ⭐!

**感谢使用 Starlight CLI！/ Thank you for using Starlight CLI!**

------------------------------------------------------------------------

## 🎁 致谢 / Acknowledgments

特别感谢以下开源项目和服务：\
Special thanks to the following open-source projects and services:

-   [httr](https://httr.r-lib.org/) - R HTTP 客户端 / R HTTP client
-   [pdftools](https://github.com/ropensci/pdftools) - PDF 文本提取 / PDF text extraction
-   [imager](https://github.com/dahtah/imager) - 图像处理 / Image processing
-   OpenAI, DeepSeek, ModelScope 等 API 服务提供商 / API service providers

------------------------------------------------------------------------

**Version 2.5.0** \| 构建时间 / Build Date: 2025-12-02 \| Made with ❤️ and R
