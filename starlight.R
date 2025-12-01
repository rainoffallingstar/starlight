#!/usr/bin/env Rscript
# =========================================================================
#           🤖 星光通用大模型聊天客户端 (Starlight CLI)
#          Version: 2.4.0 (RAG 完整版)
# =========================================================================

# 强制设置 UTF-8 编码
invisible(Sys.setlocale("LC_ALL", "en_US.UTF-8"))
invisible(options(encoding = "UTF-8"))

suppressPackageStartupMessages({
  library(optparse)
  library(httr)
  library(jsonlite)
  library(yaml)
  library(cli)
  library(crayon)
  library(base64enc)
  
  # PDF 处理
  if (requireNamespace("pdftools", quietly = TRUE)) {
    library(pdftools)
  }
  
  # 图像处理库（可选）
  if (requireNamespace("imager", quietly = TRUE)) {
    library(imager)
  }
  if (requireNamespace("magick", quietly = TRUE)) {
    library(magick)
  }
})

# 空操作符定义
`%||%` <- function(a, b) if (is.null(a)) b else a

# =========================================================================
# 1. 全局环境上下文
# =========================================================================
chat_context <- new.env()
chat_context$history <- list()              # 短期对话历史
chat_context$memory_slot <- ""              # 长期记忆
chat_context$base_system <- ""              # 基础人设
chat_context$config <- NULL                 # 当前配置
chat_context$embedding_config <- NULL       # Embedding 配置
chat_context$current_model <- ""            # 当前模型
chat_context$current_provider <- ""         # 当前渠道
chat_context$compressed_summary <- ""       # 压缩后的摘要
chat_context$full_history <- list()         # 完整历史记录(压缩前保留)
chat_context$session_file <- ""             # 当前会话文件路径
chat_context$session_title <- ""            # 会话标题
chat_context$pending_images <- NULL         # 待发送的图片
chat_context$debug_mode <- FALSE            # 调试模式
chat_context$image_gen_dir <- "image_gen"   # 图片生成保存目录

# =========================================================================
# 2. 编码安全工具
# =========================================================================

# UTF-8 合法性检查
validUTF8 <- function(x) {
  tryCatch({
    grepl(".", x, perl = TRUE)
    TRUE
  }, error = function(e) {
    FALSE
  })
}

# 安全字符串清理
safe_string <- function(x) {
  if (is.null(x) || is.na(x)) return("")
  x <- as.character(x)
  x <- enc2utf8(x)
  # 移除控制字符（保留换行符和制表符）
  x <- gsub("[\x01-\x08\x0B\x0C\x0E-\x1F\x7F]", "", x, perl = TRUE)
  return(x)
}

# =========================================================================
# 3. 统一输出格式工具
# =========================================================================

print_message <- function(type, text, emoji = NULL, width = 70) {
  type_config <- list(
    success = list(color = green, emoji = "✓", prefix = "SUCCESS"),
    info    = list(color = cyan, emoji = "ℹ", prefix = "INFO"),
    warning = list(color = yellow, emoji = "⚠", prefix = "WARNING"),
    error   = list(color = red, emoji = "✗", prefix = "ERROR"),
    header  = list(color = magenta$bold, emoji = "★", prefix = ""),
    stream  = list(color = cyan, emoji = "💬", prefix = ""),
    debug   = list(color = silver, emoji = "🔍", prefix = "DEBUG")
  )
  
  cfg <- type_config[[type]]
  if (is.null(cfg)) cfg <- type_config$info
  
  display_emoji <- if (!is.null(emoji)) emoji else cfg$emoji
  prefix_text <- if (nchar(cfg$prefix) > 0) paste0("[", cfg$prefix, "]") else ""
  
  # 安全处理文本
  text <- safe_string(text)
  
  if (type == "stream") {
    cat("\n")
    cat(cfg$color(paste0("┌", strrep("─", width - 2), "┐")), "\n")
    title_text <- paste(display_emoji, text)
    padding <- max(0, width - nchar(text, type="width") - 4)
    cat(cfg$color("│"), title_text, strrep(" ", padding), cfg$color("│"), "\n")
    cat(cfg$color(paste0("└", strrep("─", width - 2), "┘")), "\n\n")
  } else if (type == "header") {
    cat("\n")
    tryCatch({
      cli_rule(left = paste(display_emoji, cfg$color(text)), col = "cyan")
    }, error = function(e) {
      cat(cfg$color(paste0(strrep("─", 10), " ", display_emoji, " ", text, " ", strrep("─", 10))), "\n")
    })
    cat("\n")
  } else {
    cat(cfg$color(paste(display_emoji, prefix_text, text)), "\n")
  }
}

msg_success <- function(text) print_message("success", text)
msg_info <- function(text) print_message("info", text)
msg_warning <- function(text) print_message("warning", text)
msg_error <- function(text) print_message("error", text)
msg_header <- function(text, emoji = "🎯") print_message("header", text, emoji)
msg_stream <- function(text, emoji = "💬") print_message("stream", text, emoji)
msg_debug <- function(text) if (chat_context$debug_mode) print_message("debug", text)

# =========================================================================
# 4. 图像处理工具
# =========================================================================

# 本地图片转 Base64
encode_image <- function(image_path) {
  if (!file.exists(image_path)) {
    msg_error(paste("图片不存在:", image_path))
    return(NULL)
  }
  
  # 检测文件类型
  ext <- tolower(tools::file_ext(image_path))
  mime_type <- switch(
    ext,
    "jpg" = , "jpeg" = "image/jpeg",
    "png" = "image/png",
    "gif" = "image/gif",
    "webp" = "image/webp",
    "bmp" = "image/bmp",
    {
      msg_warning(paste("不支持的图片格式:", ext, "- 尝试作为 JPEG 处理"))
      "image/jpeg"
    }
  )
  
  # 检查文件大小
  file_size <- file.info(image_path)$size
  if (file_size > 20 * 1024 * 1024) {  # 20MB 限制
    msg_warning(paste("图片过大 (", round(file_size/1024/1024, 2), "MB), 建议压缩后使用"))
  }
  
  # Base64 编码
  tryCatch({
    raw_data <- readBin(image_path, "raw", file.info(image_path)$size)
    b64 <- base64enc::base64encode(raw_data)
    
    # 构建标准格式
    result <- list(
      type = "image_url",
      image_url = list(
        url = paste0("data:", mime_type, ";base64,", b64)
      )
    )
    
    # 调试输出
    msg_debug(paste("图片编码成功:", basename(image_path)))
    msg_debug(paste("  MIME类型:", mime_type))
    msg_debug(paste("  Base64长度:", nchar(b64)))
    msg_debug(paste("  数据前缀:", substr(b64, 1, 30), "..."))
    
    return(result)
  }, error = function(e) {
    msg_error(paste("图片编码失败:", e$message))
    return(NULL)
  })
}

# URL 图片构建
build_image_url <- function(url) {
  result <- list(
    type = "image_url",
    image_url = list(url = url)
  )
  msg_debug(paste("添加网络图片:", url))
  return(result)
}

# 下载图片到本地
download_image <- function(image_url, gen_dir = NULL) {
  # 确定保存目录
  if (is.null(gen_dir)) {
    gen_dir <- chat_context$image_gen_dir
  }
  
  # 创建目录
  if (!dir.exists(gen_dir)) {
    dir.create(gen_dir, recursive = TRUE)
    msg_debug(paste("创建图片保存目录:", gen_dir))
  }
  
  # 生成文件名
  timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  
  tryCatch({
    # 处理 Base64 数据
    if (grepl("^data:", image_url)) {
      msg_debug("检测到 Base64 图片数据")
      
      # 提取 MIME 类型和数据
      mime_match <- regmatches(image_url, regexpr("data:image/([^;]+)", image_url))
      if (length(mime_match) > 0) {
        ext <- gsub("data:image/", "", mime_match)
        ext <- gsub("jpeg", "jpg", ext)
      } else {
        ext <- "png"  # 默认
      }
      
      # 提取 Base64 数据
      b64_data <- sub("^data:image/[^;]+;base64,", "", image_url)
      
      # 生成文件路径
      filename <- paste0("generated_", timestamp, ".", ext)
      filepath <- file.path(gen_dir, filename)
      
      # 解码并保存
      raw_data <- base64enc::base64decode(b64_data)
      writeBin(raw_data, filepath)
      
      msg_success(paste("✓ Base64图片已保存:", filename))
      msg_debug(paste("  路径:", filepath))
      return(filepath)
      
    } else {
      # 网络图片
      msg_debug(paste("下载网络图片:", image_url))
      
      # 从 URL 推断扩展名
      ext <- "jpg"
      if (grepl("\\.(png|jpg|jpeg|gif|webp|bmp)($|\\?)", image_url, ignore.case = TRUE)) {
        ext_match <- regmatches(image_url, regexpr("\\.(png|jpg|jpeg|gif|webp|bmp)",
                                                   image_url, ignore.case = TRUE))
        ext <- tolower(gsub("\\.", "", ext_match))
        ext <- gsub("jpeg", "jpg", ext)
      }
      
      # 生成文件路径
      filename <- paste0("downloaded_", timestamp, ".", ext)
      filepath <- file.path(gen_dir, filename)
      
      # 下载
      download.file(image_url, filepath, mode = "wb", quiet = TRUE)
      
      msg_success(paste("✓ 网络图片已下载:", filename))
      msg_debug(paste("  URL:", image_url))
      msg_debug(paste("  路径:", filepath))
      return(filepath)
    }
  }, error = function(e) {
    msg_error(paste("图片下载失败:", e$message))
    return(NULL)
  })
}

# 渲染图片到终端
render_image <- function(image_url_or_path) {
  # 判断是本地文件还是 URL
  if (file.exists(image_url_or_path)) {
    # 已经是本地文件
    local_path <- image_url_or_path
    msg_debug(paste("渲染本地文件:", local_path))
  } else {
    # 需要下载
    msg_debug("渲染前先下载图片")
    local_path <- download_image(image_url_or_path)
    if (is.null(local_path)) {
      msg_warning("无法下载图片，跳过渲染")
      return(FALSE)
    }
  }
  
  # 1. iTerm2 内联显示
  if (Sys.getenv("TERM_PROGRAM") == "iTerm.app") {
    tryCatch({
      # 使用 iTerm2 内联图片协议
      img_data <- base64enc::base64encode(local_path)
      cat(sprintf("\033]1337;File=inline=1:%s\a\n", img_data))
      return(TRUE)
    }, error = function(e) {
      msg_debug(paste("iTerm2渲染失败:", e$message))
    })
  }
  
  # 2. ASCII 艺术渲染 (使用 imager)
  if (requireNamespace("imager", quietly = TRUE)) {
    tryCatch({
      # 加载图片
      img <- imager::load.image(local_path)
      img_gray <- imager::grayscale(img)
      
      # 调整大小 (保持宽高比)
      max_width <- 80
      aspect_ratio <- dim(img)[2] / dim(img)[1]
      new_height <- as.integer(max_width / aspect_ratio / 2)
      img_resized <- imager::resize(img_gray, max_width, new_height)
      
      # 转换为字符矩阵
      chars <- " .'`^\",:;Il!i><~+_-?][}{1)(|\\/tfjrxnuvczXYUJCLQ0OZmwqpdbkhao*#MW&8%B@$"
      mat <- as.matrix(img_resized[,,1,1])
      mat_normalized <- (mat - min(mat)) / (max(mat) - min(mat))
      char_indices <- pmax(1, pmin(nchar(chars), ceiling(mat_normalized * nchar(chars))))
      
      cat(cyan$bold("\n┌─ 图片预览 ─┐\n"))
      for (i in 1:nrow(mat)) {
        row_chars <- sapply(char_indices[i,], function(idx) {
          substr(chars, idx, idx)
        })
        cat("│ ", paste(row_chars, collapse = ""), "\n")
      }
      cat(cyan$bold("└"), strrep("─", max_width + 2), cyan$bold("┘\n\n"))
      return(TRUE)
    }, error = function(e) {
      msg_debug(paste("imager渲染失败:", e$message))
    })
  }
  
  # 3. 使用 magick 包渲染
  if (requireNamespace("magick", quietly = TRUE)) {
    tryCatch({
      img <- magick::image_read(local_path)
      # 缩放
      img <- magick::image_scale(img, "80x40")
      cat(cyan$bold("\n【图片预览】\n"))
      print(img)
      cat("\n")
      return(TRUE)
    }, error = function(e) {
      msg_debug(paste("magick渲染失败:", e$message))
    })
  }
  
  # 4. 最后降级：仅显示路径
  msg_warning("无法渲染图片 (建议安装 imager 或 magick 包)")
  cat(cyan(paste("🖼️  图片已保存:", local_path)), "\n\n")
  return(FALSE)
}

# 从文本中提取图片 URL
extract_image_urls <- function(text) {
  # 匹配 Markdown 图片: ![alt](url)
  md_pattern <- "!\\[.*?\\]\\((https?://[^)\\s]+)\\)"
  md_matches <- gregexpr(md_pattern, text, perl = TRUE)
  md_urls <- character(0)
  if (md_matches[[1]][1] != -1) {
    md_captured <- regmatches(text, md_matches)[[1]]
    md_urls <- gsub("!\\[.*?\\]\\((.+?)\\)", "\\1", md_captured)
  }
  
  # 匹配普通 URL (更宽松的规则)
  url_pattern <- "https?://[^\\s)>]+\\.(jpg|jpeg|png|gif|webp|bmp|svg)"
  url_matches <- gregexpr(url_pattern, text, perl = TRUE, ignore.case = TRUE)
  plain_urls <- character(0)
  if (url_matches[[1]][1] != -1) {
    plain_urls <- regmatches(text, url_matches)[[1]]
  }
  
  # 匹配不带扩展名的图片 URL (常见于图片生成 API)
  generic_pattern <- "https?://[^\\s)>]+/(image|img|picture|photo|file)/[^\\s)>]+"
  generic_matches <- gregexpr(generic_pattern, text, perl = TRUE, ignore.case = TRUE)
  generic_urls <- character(0)
  if (generic_matches[[1]][1] != -1) {
    generic_urls <- regmatches(text, generic_matches)[[1]]
  }
  
  # 合并去重
  all_urls <- unique(c(md_urls, plain_urls, generic_urls))
  
  # 调试输出
  if (length(all_urls) > 0) {
    msg_debug(paste("提取到", length(all_urls), "个图片 URL:"))
    for (url in all_urls) {
      msg_debug(paste("  -", substr(url, 1, 80)))
    }
  }
  
  return(all_urls)
}

# =========================================================================
# 5. Embedding 和 PDF 处理工具
# =========================================================================

# Embedding API 调用函数（增强版）
call_embedding_api <- function(texts) {
  if (is.null(chat_context$embedding_config)) {
    msg_error("未配置 Embedding，请在 .env 中添加 embedding 配置")
    return(NULL)
  }
  
  url <- chat_context$embedding_config$url
  model <- chat_context$embedding_config$model
  api_key <- chat_context$embedding_config$api_key %||% chat_context$config$api_key
  
  msg_debug(paste("调用 Embedding API:", url))
  msg_debug(paste("模型:", model))
  msg_debug(paste("文本数量:", length(texts)))
  
  # 显示第一个文本的预览
  if (chat_context$debug_mode && length(texts) > 0) {
    preview <- substr(texts[[1]], 1, 100)
    msg_debug(paste("首个文本预览:", preview, "..."))
    msg_debug(paste("首个文本长度:", nchar(texts[[1]]), "字符"))
  }
  
  body <- list(
    model = model,
    input = texts
  )
  
  headers <- add_headers(
    `Content-Type` = "application/json",
    `Authorization` = paste("Bearer", api_key)
  )
  
  tryCatch({
    resp <- POST(
      url,
      headers,
      body = jsonlite::toJSON(body, auto_unbox = TRUE),
      encode = "json",
      timeout(60)
    )
    
    if (status_code(resp) != 200) {
      error_text <- content(resp, as = "text", encoding = "UTF-8")
      msg_error(paste("Embedding API 错误:", status_code(resp)))
      msg_debug(error_text)
      
      # 解析错误信息
      tryCatch({
        error_json <- jsonlite::fromJSON(error_text, simplifyVector = FALSE)
        if (!is.null(error_json$message)) {
          msg_error(paste("详细错误:", error_json$message))
        }
        
        # 特殊处理 token 超限错误
        if (status_code(resp) == 413 || grepl("token", error_json$message, ignore.case = TRUE)) {
          msg_warning("检测到 token 超限，建议:")
          cat(yellow("  • 减小分块大小（当前可能过大）\n"))
          cat(yellow("  • 检查单个文本块的字符数\n"))
          cat(yellow("  • 尝试使用更小的批次大小\n\n"))
        }
      }, error = function(e) {
        # 忽略错误解析失败
      })
      
      return(NULL)
    }
    
    result <- content(resp, as = "parsed")
    
    # 提取向量
    embeddings <- lapply(result$data, function(item) {
      item$embedding
    })
    
    msg_debug(paste("成功生成", length(embeddings), "个向量"))
    if (length(embeddings) > 0 && chat_context$debug_mode) {
      msg_debug(paste("向量维度:", length(embeddings[[1]])))
    }
    
    return(embeddings)
    
  }, error = function(e) {
    msg_error(paste("Embedding API 调用失败:", e$message))
    return(NULL)
  })
}

# 文本分块函数（优化版 - 修复 Unicode 问题）
chunk_text <- function(text, chunk_size = 500, overlap = 50, max_tokens = 6000) {
  # 估算 token 数（中文按 1.5 字符/token，英文按 0.25 字符/token）
  estimate_tokens <- function(text) {
    # 使用 R 原生的 Unicode 范围检测中文
    tryCatch({
      chars <- utf8ToInt(text)
      # 中文 Unicode 范围: 0x4E00 - 0x9FA5 (十进制 19968 - 40869)
      cn_chars <- sum(chars >= 19968 & chars <= 40869)
      total_chars <- length(chars)
      
      if (cn_chars > total_chars * 0.5) {
        # 中文为主
        return(ceiling(total_chars / 1.5))
      } else {
        # 英文为主
        return(ceiling(total_chars / 4))
      }
    }, error = function(e) {
      # 降级方案：按字节数估算
      msg_debug(paste("Token 估算降级:", e$message))
      return(ceiling(nchar(text) / 3))
    })
  }
  
  # 动态调整分块大小
  text_tokens <- estimate_tokens(text)
  
  if (text_tokens > max_tokens * 10) {
    # 超大文档，缩小分块
    chunk_size <- 200
    overlap <- 20
    msg_debug(paste("检测到超大文档，调整分块大小:", chunk_size))
  } else if (text_tokens > max_tokens * 5) {
    chunk_size <- 300
    overlap <- 30
    msg_debug(paste("检测到大文档，调整分块大小:", chunk_size))
  }
  
  # 按句子分割（使用字符类而非 Unicode 范围）
  sentences <- unlist(strsplit(text, "(?<=[。.!?\\n])", perl = TRUE))
  sentences <- sentences[nchar(trimws(sentences)) > 0]
  
  chunks <- list()
  current_chunk <- ""
  
  for (sentence in sentences) {
    test_chunk <- paste0(current_chunk, sentence)
    test_tokens <- estimate_tokens(test_chunk)
    
    # 检查 token 限制
    if (test_tokens < max_tokens && nchar(current_chunk) + nchar(sentence) < chunk_size * 10) {
      current_chunk <- test_chunk
    } else {
      if (nchar(current_chunk) > 0) {
        chunks <- append(chunks, list(trimws(current_chunk)))
        msg_debug(paste("分块", length(chunks), ":", estimate_tokens(current_chunk), "tokens,", 
                        nchar(current_chunk), "字符"))
      }
      
      # 保留部分重叠
      if (overlap > 0 && nchar(current_chunk) > overlap) {
        current_chunk <- paste0(
          substr(current_chunk, nchar(current_chunk) - overlap + 1, nchar(current_chunk)),
          sentence
        )
      } else {
        current_chunk <- sentence
      }
      
      # 检查单个句子是否过长
      if (estimate_tokens(current_chunk) > max_tokens) {
        msg_warning(paste("单个句子过长 (", nchar(current_chunk), "字符), 强制截断"))
        # 强制按字符截断
        max_chars <- max_tokens * 1.5  # 安全边界
        while (nchar(current_chunk) > max_chars) {
          chunk_part <- substr(current_chunk, 1, max_chars)
          chunks <- append(chunks, list(trimws(chunk_part)))
          msg_debug(paste("强制分块", length(chunks), ":", nchar(chunk_part), "字符"))
          current_chunk <- substr(current_chunk, max_chars + 1, nchar(current_chunk))
        }
      }
    }
  }
  
  if (nchar(trimws(current_chunk)) > 0) {
    chunks <- append(chunks, list(trimws(current_chunk)))
    msg_debug(paste("最后分块:", estimate_tokens(current_chunk), "tokens,", 
                    nchar(current_chunk), "字符"))
  }
  
  # 验证所有分块
  msg_debug(paste("=== 分块验证 ==="))
  for (i in seq_along(chunks)) {
    chunk_tokens <- estimate_tokens(chunks[[i]])
    chunk_chars <- nchar(chunks[[i]])
    
    msg_debug(paste("分块", i, ":", chunk_tokens, "tokens,", chunk_chars, "字符"))
    
    if (chunk_tokens > max_tokens) {
      msg_warning(paste("分块", i, "超过限制 (", chunk_tokens, "tokens) - 将被截断"))
      # 强制截断到安全长度
      safe_length <- floor(max_tokens * 1.5)
      chunks[[i]] <- substr(chunks[[i]], 1, safe_length)
      msg_debug(paste("  截断后:", nchar(chunks[[i]]), "字符"))
    }
  }
  
  msg_debug(paste("分块完成，共", length(chunks), "块"))
  
  return(chunks)
}

# 保存向量到会话
save_pdf_vectors <- function(filename, chunks, embeddings) {
  if (is.null(chat_context$session_file) || !file.exists(chat_context$session_file)) {
    msg_error("会话文件不存在，无法保存向量")
    return(FALSE)
  }
  
  tryCatch({
    # 读取现有会话
    con <- file(chat_context$session_file, "r", encoding = "UTF-8")
    session_data <- jsonlite::fromJSON(readLines(con, warn = FALSE), simplifyVector = FALSE)
    close(con)
    
    # 初始化向量存储
    if (is.null(session_data$pdf_vectors)) {
      session_data$pdf_vectors <- list()
    }
    
    # 添加新的 PDF 向量
    pdf_id <- gsub("\\.pdf$", "", basename(filename), ignore.case = TRUE)
    pdf_id <- paste0(pdf_id, "_", format(Sys.time(), "%Y%m%d%H%M%S"))
    
    session_data$pdf_vectors[[pdf_id]] <- list(
      filename = basename(filename),
      created_at = as.character(Sys.time()),
      chunks = chunks,
      embeddings = embeddings,
      chunk_count = length(chunks),
      embedding_model = chat_context$embedding_config$model
    )
    
    # 保存
    json_text <- jsonlite::toJSON(
      session_data,
      pretty = TRUE,
      auto_unbox = TRUE,
      ensure_ascii = FALSE
    )
    
    con <- file(chat_context$session_file, "w", encoding = "UTF-8")
    writeLines(enc2utf8(json_text), con, useBytes = TRUE)
    close(con)
    
    msg_success(paste("向量已保存到会话:", pdf_id))
    msg_debug(paste("  文件:", basename(filename)))
    msg_debug(paste("  分块数:", length(chunks)))
    msg_debug(paste("  向量维度:", length(embeddings[[1]])))
    
    return(TRUE)
    
  }, error = function(e) {
    msg_error(paste("保存向量失败:", e$message))
    return(FALSE)
  })
}

# =========================================================================
# 向量检索相关函数
# =========================================================================

# 计算余弦相似度（增强版 - 类型安全）
cosine_similarity <- function(vec1, vec2) {
  # 类型转换和验证
  tryCatch({
    # 确保是数值向量
    vec1 <- as.numeric(unlist(vec1))
    vec2 <- as.numeric(unlist(vec2))
    
    # 检查维度
    if (length(vec1) != length(vec2)) {
      msg_warning(paste("向量维度不匹配:", length(vec1), "vs", length(vec2)))
      return(0)
    }
    
    # 检查是否有 NA 或 NaN
    if (any(is.na(vec1)) || any(is.na(vec2))) {
      msg_warning("向量中包含 NA 值")
      return(0)
    }
    
    # 计算余弦相似度
    dot_product <- sum(vec1 * vec2)
    norm1 <- sqrt(sum(vec1^2))
    norm2 <- sqrt(sum(vec2^2))
    
    if (norm1 == 0 || norm2 == 0) {
      msg_debug("向量范数为 0")
      return(0)
    }
    
    similarity <- dot_product / (norm1 * norm2)
    
    # 确保结果在 [-1, 1] 范围内
    similarity <- max(-1, min(1, similarity))
    
    return(similarity)
    
  }, error = function(e) {
    msg_warning(paste("相似度计算错误:", e$message))
    return(0)
  })
}
# 从会话中检索相关 PDF 内容（增强版 - 错误处理）
# 从会话中检索相关 PDF 内容（增强版 - 错误处理）
retrieve_pdf_context <- function(query, top_k = 3, similarity_threshold = 0.3) {
  # 检查是否有 PDF 向量数据
  if (is.null(chat_context$session_file) || !file.exists(chat_context$session_file)) {
    msg_debug("会话文件不存在")
    return(NULL)
  }
  
  tryCatch({
    # 读取会话数据
    con <- file(chat_context$session_file, "r", encoding = "UTF-8")
    session_data <- jsonlite::fromJSON(readLines(con, warn = FALSE), simplifyVector = FALSE)
    close(con)
    
    if (is.null(session_data$pdf_vectors) || length(session_data$pdf_vectors) == 0) {
      msg_debug("当前会话无 PDF 向量数据")
      return(NULL)
    }
    
    msg_debug(paste("检测到", length(session_data$pdf_vectors), "个 PDF 文档"))
    
    # 1. 将问题向量化
    msg_debug("正在向量化查询问题...")
    query_embedding <- call_embedding_api(list(query))
    
    if (is.null(query_embedding) || length(query_embedding) == 0) {
      msg_warning("问题向量化失败，无法检索 PDF 内容")
      return(NULL)
    }
    
    # 确保向量是数值类型
    query_vec <- as.numeric(unlist(query_embedding[[1]]))
    msg_debug(paste("问题向量维度:", length(query_vec)))
    
    # 验证向量有效性
    if (any(is.na(query_vec))) {
      msg_warning("问题向量包含 NA 值")
      return(NULL)
    }
    
    # 2. 遍历所有 PDF，计算相似度
    all_results <- list()
    
    for (pdf_id in names(session_data$pdf_vectors)) {
      pdf_data <- session_data$pdf_vectors[[pdf_id]]
      
      msg_debug(paste("检索 PDF:", pdf_data$filename, "-", pdf_data$chunk_count, "个分块"))
      
      # 验证数据结构
      if (is.null(pdf_data$chunks) || is.null(pdf_data$embeddings)) {
        msg_warning(paste("PDF", pdf_data$filename, "数据不完整，跳过"))
        next
      }
      
      # 确保 chunks 和 embeddings 数量一致
      if (length(pdf_data$chunks) != length(pdf_data$embeddings)) {
        msg_warning(paste("PDF", pdf_data$filename, "分块与向量数量不匹配"))
        next
      }
      
      # 计算每个分块的相似度
      for (i in seq_along(pdf_data$chunks)) {
        chunk_text <- pdf_data$chunks[[i]]
        chunk_embedding_raw <- pdf_data$embeddings[[i]]
        
        # 类型转换
        tryCatch({
          chunk_embedding <- as.numeric(unlist(chunk_embedding_raw))
          
          # 验证维度
          if (length(chunk_embedding) != length(query_vec)) {
            msg_debug(paste("分块", i, "向量维度不匹配，跳过"))
            next
          }
          
          # 验证有效性
          if (any(is.na(chunk_embedding))) {
            msg_debug(paste("分块", i, "向量包含 NA，跳过"))
            next
          }
          
          # 计算相似度
          similarity <- cosine_similarity(query_vec, chunk_embedding)
          
          msg_debug(sprintf("分块 %d 相似度: %.4f", i, similarity))
          
          all_results <- append(all_results, list(list(
            pdf_id = pdf_id,
            filename = pdf_data$filename,
            chunk_index = i,
            chunk_text = chunk_text,
            similarity = similarity
          )))
          
        }, error = function(e) {
          msg_debug(paste("处理分块", i, "时出错:", e$message))
        })
      }
    }
    
    # 检查是否有结果
    if (length(all_results) == 0) {
      msg_debug("未找到有效的检索结果")
      return(NULL)
    }
    
    # 3. 按相似度排序，取 Top-K
    similarities <- sapply(all_results, function(x) x$similarity)
    
    # 确保 similarities 是数值型
    similarities <- as.numeric(similarities)
    
    # 过滤掉无效值
    valid_indices <- which(!is.na(similarities) & !is.nan(similarities))
    if (length(valid_indices) == 0) {
      msg_debug("所有相似度计算结果无效")
      return(NULL)
    }
    
    all_results <- all_results[valid_indices]
    similarities <- similarities[valid_indices]
    
    # 排序并取 Top-K
    top_indices <- order(similarities, decreasing = TRUE)[1:min(top_k, length(all_results))]
    top_results <- all_results[top_indices]
    
    # 4. 过滤低相似度结果
    top_results <- top_results[sapply(top_results, function(x) x$similarity > similarity_threshold)]
    
    if (length(top_results) == 0) {
      msg_debug(paste("未找到相关度足够高的内容（阈值:", similarity_threshold, ")"))
      return(NULL)
    }
    
    # 5. 构建上下文文本
    context_parts <- list()
    
    msg_debug("=== 检索结果 ===")
    for (i in seq_along(top_results)) {
      result <- top_results[[i]]
      msg_debug(sprintf("[%d] 文件: %s | 分块: %d | 相似度: %.4f", 
                        i, result$filename, result$chunk_index, result$similarity))
      msg_debug(paste("  内容预览:", substr(result$chunk_text, 1, 100), "..."))
      
      context_parts <- append(context_parts, paste0(
        "【来源: ", result$filename, " - 片段 ", result$chunk_index, " | 相关度: ", 
        sprintf("%.1f%%", result$similarity * 100), "】\n",
        result$chunk_text
      ))
    }
    
    context_text <- paste(context_parts, collapse = "\n\n━━━━━━━━━━━━━━━━━━━━\n\n")
    
    msg_success(paste("✓ 检索到", length(top_results), "个相关片段"))
    
    return(context_text)
    
  }, error = function(e) {
    msg_warning(paste("PDF 内容检索失败:", e$message))
    msg_debug(paste("完整错误:", toString(e)))
    return(NULL)
  })
}

# =========================================================================
# 6. 会话文件管理
# =========================================================================

# 生成对话标题（优化版）
generate_session_title <- function() {
  if (length(chat_context$history) == 0) {
    return("新对话")
  }
  
  # 智能选择标题模型
  title_model <- NULL
  
  # 1. 优先使用渠道配置的 title_model
  if (!is.null(chat_context$config$title_model) && 
      nchar(trimws(chat_context$config$title_model)) > 0) {
    title_model <- chat_context$config$title_model
    msg_debug(paste("使用渠道配置的标题模型:", title_model))
  } 
  # 2. 回退到当前对话模型
  else {
    title_model <- chat_context$current_model
    msg_debug(paste("使用当前对话模型生成标题:", title_model))
  }
  
  # 构建标题生成请求
  sample_history <- head(chat_context$history, 6)
  title_messages <- c(
    list(list(
      role = "system",
      content = "你是一个专业的对话标题生成助手。根据用户对话内容,生成一个简洁精准的中文标题(8-15字),直接输出标题,不要有任何其他内容。"
    )),
    sample_history,
    list(list(
      role = "user",
      content = "请为上述对话生成一个简洁的标题(8-15字)"
    ))
  )
  
  cli_process_start("🏷️  生成对话标题中...")
  
  # 临时切换模型
  old_model <- chat_context$current_model
  chat_context$current_model <- title_model
  
  title <- simple_chat_request(title_messages)
  
  # 恢复原模型
  chat_context$current_model <- old_model
  cli_process_done()
  
  if (!is.null(title) && nchar(title) > 0) {
    # 清理标题
    title <- gsub("[\"'『』【】《》\n\r]", "", title)
    title <- trimws(title)
    if (nchar(title, type = "width") > 20) {
      title <- substr(title, 1, 20)
    }
    return(title)
  }
  
  # 生成失败，使用首句作为标题
  first_user_msg <- NULL
  for (msg in chat_context$history) {
    if (msg$role == "user") {
      content <- msg$content
      if (is.list(content)) {
        for (part in content) {
          if (!is.null(part$type) && part$type == "text") {
            first_user_msg <- part$text
            break
          }
        }
      } else {
        first_user_msg <- content
      }
      if (!is.null(first_user_msg)) break
    }
  }
  
  if (!is.null(first_user_msg)) {
    title <- substr(first_user_msg, 1, 15)
    if (nchar(first_user_msg) > 15) title <- paste0(title, "...")
    return(title)
  }
  
  return("新对话")
}

# 获取或创建会话文件
init_session_file <- function(force_new = FALSE, json = NULL) {
  session_dir <- file.path(getwd(), "chat_logs")
  if (!dir.exists(session_dir)) {
    dir.create(session_dir, recursive = TRUE)
  }
  
  if (!force_new) {
    existing_files <- list.files(
      session_dir,
      pattern = "^chat_.*\\.json$",
      full.names = TRUE
    )
    
    if (length(existing_files) > 0) {
      if (!is.null(json) && file.exists(json)) {
        latest_file <- json
      } else {
        latest_file <- existing_files[order(file.mtime(existing_files), decreasing = TRUE)[1]]
      }
      
      tryCatch({
        con <- file(latest_file, "r", encoding = "UTF-8")
        session_data <- jsonlite::fromJSON(readLines(con, warn = FALSE), simplifyVector = FALSE)
        close(con)
        
        chat_context$session_file <- latest_file
        chat_context$current_model <- session_data$model
        chat_context$base_system <- session_data$system_prompt
        chat_context$memory_slot <- session_data$memory %||% ""
        chat_context$history <- session_data$conversations %||% list()
        chat_context$compressed_summary <- session_data$compressed_summary %||% ""
        chat_context$full_history <- session_data$full_history_before_compress %||% list()
        chat_context$session_title <- session_data$title %||% "未命名对话"
        
        msg_success(paste("已恢复会话:", chat_context$session_title))
        msg_info(paste("创建时间:", session_data$created_at))
        msg_info(paste("历史消息:", length(chat_context$history), "条"))
        
        # 显示 PDF 向量信息
        if (!is.null(session_data$pdf_vectors) && length(session_data$pdf_vectors) > 0) {
          total_chunks <- sum(sapply(session_data$pdf_vectors, function(x) x$chunk_count))
          msg_info(paste("已加载", length(session_data$pdf_vectors), "个 PDF，共", total_chunks, "个文本块"))
        }
        
        return(latest_file)
      }, error = function(e) {
        msg_warning(paste("加载会话失败,将创建新会话:", e$message))
      })
    }
  }
  
  timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  session_file <- file.path(session_dir, paste0("chat_", timestamp, ".json"))
  chat_context$session_file <- session_file
  chat_context$session_title <- "新对话"
  
  session_data <- list(
    session_id = timestamp,
    title = "新对话",
    created_at = as.character(Sys.time()),
    updated_at = as.character(Sys.time()),
    model = chat_context$current_model,
    system_prompt = chat_context$base_system,
    memory = chat_context$memory_slot,
    conversations = list(),
    compressed_summary = "",
    full_history_before_compress = list(),
    pdf_vectors = list()
  )
  
  save_session(session_data)
  msg_info(paste("新会话:", basename(session_file)))
  return(session_file)
}

# 保存会话数据
save_session <- function(session_data = NULL) {
  if (is.null(session_data)) {
    created_at <- tryCatch({
      if (file.exists(chat_context$session_file)) {
        con <- file(chat_context$session_file, "r", encoding = "UTF-8")
        existing <- jsonlite::fromJSON(readLines(con, warn = FALSE), simplifyVector = FALSE)
        close(con)
        existing$created_at
      } else {
        as.character(Sys.time())
      }
    }, error = function(e) as.character(Sys.time()))
    
    session_data <- list(
      session_id = gsub(".*chat_(.*)\\.json", "\\1", chat_context$session_file),
      title = safe_string(chat_context$session_title),
      created_at = created_at,
      updated_at = as.character(Sys.time()),
      model = safe_string(chat_context$current_model),
      system_prompt = safe_string(chat_context$base_system),
      memory = safe_string(chat_context$memory_slot),
      conversations = chat_context$history,
      compressed_summary = safe_string(chat_context$compressed_summary),
      full_history_before_compress = chat_context$full_history
    )
    
    # 保留现有的 PDF 向量数据
    if (file.exists(chat_context$session_file)) {
      tryCatch({
        con <- file(chat_context$session_file, "r", encoding = "UTF-8")
        existing <- jsonlite::fromJSON(readLines(con, warn = FALSE), simplifyVector = FALSE)
        close(con)
        if (!is.null(existing$pdf_vectors)) {
          session_data$pdf_vectors <- existing$pdf_vectors
        }
      }, error = function(e) {
        msg_debug("无法读取现有 PDF 向量数据")
      })
    }
  }
  
  tryCatch({
    json_text <- jsonlite::toJSON(
      session_data,
      pretty = TRUE,
      auto_unbox = TRUE,
      ensure_ascii = FALSE
    )
    
    con <- file(chat_context$session_file, "w", encoding = "UTF-8")
    writeLines(enc2utf8(json_text), con, useBytes = TRUE)
    close(con)
  }, error = function(e) {
    msg_warning(paste("保存会话失败:", e$message))
  })
}

# 添加对话记录
add_conversation <- function(user_input, assistant_reply, images = NULL) {
  user_input <- safe_string(user_input)
  assistant_reply <- safe_string(assistant_reply)
  
  # 构建用户消息内容
  user_content <- user_input
  if (!is.null(images) && length(images) > 0) {
    # 如果有图片,使用多部分内容格式
    user_content <- list(
      list(type = "text", text = user_input)
    )
    # 添加图片信息摘要(不保存完整 Base64)
    for (i in seq_along(images)) {
      img_url <- images[[i]]$image_url$url
      if (grepl("^data:", img_url)) {
        user_content <- append(user_content, list(list(
          type = "image_url",
          image_url = list(url = paste0("[Image ", i, " - Base64 Data ",
                                        nchar(img_url), " chars]"))
        )))
      } else {
        user_content <- append(user_content, list(images[[i]]))
      }
    }
  }
  
  chat_context$history <- append(
    chat_context$history,
    list(
      list(
        role = "user",
        content = user_content,
        timestamp = as.character(Sys.time())
      ),
      list(
        role = "assistant",
        content = assistant_reply,
        timestamp = as.character(Sys.time())
      )
    )
  )
  
  # 自动生成标题
  if (length(chat_context$history) == 2 || length(chat_context$history) %% 20 == 0) {
    new_title <- generate_session_title()
    if (new_title != chat_context$session_title) {
      chat_context$session_title <- new_title
      msg_info(paste("📝 对话标题已更新:", new_title))
    }
  }
  
  save_session()
}

# =========================================================================
# 7. 辅助工具函数
# =========================================================================

read_console <- function(prompt_str) {
  if (interactive()) {
    input <- readline(prompt_str)
  } else {
    cat(prompt_str)
    input <- readLines("stdin", n = 1, warn = FALSE)
    if (length(input) == 0) return(NULL)
  }
  
  if (!is.null(input) && length(input) > 0 && nchar(input) > 0) {
    input <- enc2utf8(input)
  }
  
  return(input)
}

# 构建消息列表（增强版 - 支持 PDF 检索）
build_messages <- function(user_input = NULL, images = NULL) {
  msgs <- list()
  
  # 1. 基础系统提示词
  full_system_text <- paste(
    chat_context$base_system,
    chat_context$memory_slot,
    sep = "\n"
  )
  
  # 2. 添加历史摘要（如果有）
  if (nchar(trimws(chat_context$compressed_summary)) > 0) {
    full_system_text <- paste(
      full_system_text,
      "\n\n=== 历史对话摘要 ===\n",
      chat_context$compressed_summary,
      "\n===================\n",
      sep = ""
    )
  }
  
  # 3. 检索相关 PDF 内容（关键新增）
  if (!is.null(user_input) && nchar(trimws(user_input)) > 0) {
    pdf_context <- retrieve_pdf_context(user_input, top_k = 3, similarity_threshold = 0.3)
    
    if (!is.null(pdf_context) && nchar(pdf_context) > 0) {
      msg_debug("已注入 PDF 检索上下文")
      full_system_text <- paste(
        full_system_text,
        "\n\n=== 相关文档内容 ===\n",
        pdf_context,
        "\n===================\n",
        "请基于上述文档内容回答用户问题。如果文档中没有相关信息，请明确告知用户。",
        sep = ""
      )
    } else {
      msg_debug("未检索到相关 PDF 内容")
    }
  }
  
  # 4. 添加系统消息
  if (nchar(trimws(full_system_text)) > 0) {
    msgs <- append(msgs, list(list(
      role = "system",
      content = safe_string(full_system_text)
    )))
  }
  
  # 5. 历史对话
  if (length(chat_context$history) > 0) {
    msgs <- append(msgs, chat_context$history)
  }
  
  # 6. 当前输入 + 图片
  if (!is.null(user_input) && nchar(user_input) > 0) {
    if (!is.null(images) && length(images) > 0) {
      # 有图片：必须使用多部分内容格式
      msg_debug(paste("构建多部分消息,包含", length(images), "张图片"))
      
      content_parts <- list(
        list(type = "text", text = safe_string(user_input))
      )
      
      # 逐个添加图片
      for (i in seq_along(images)) {
        img <- images[[i]]
        if (!is.null(img) && !is.null(img$image_url) && !is.null(img$image_url$url)) {
          content_parts <- append(content_parts, list(img))
          msg_debug(paste("  已添加图片", i, "到消息内容"))
        } else {
          msg_warning(paste("图片", i, "格式无效,已跳过"))
        }
      }
      
      # 构建多部分消息
      new_msg <- list(
        role = "user",
        content = content_parts
      )
      msgs <- append(msgs, list(new_msg))
    } else {
      # 无图片：使用简单字符串格式
      msg_debug("构建纯文本消息")
      msgs <- append(msgs, list(list(
        role = "user",
        content = safe_string(user_input)
      )))
    }
  }
  
  # 调试输出
  if (chat_context$debug_mode) {
    msg_debug("=== 最终消息结构 ===")
    msg_debug(paste("消息总数:", length(msgs)))
    for (i in seq_along(msgs)) {
      msg <- msgs[[i]]
      msg_debug(paste("消息", i, "- 角色:", msg$role))
      if (is.character(msg$content)) {
        content_preview <- substr(msg$content, 1, 200)
        msg_debug(paste("  内容预览:", content_preview, "..."))
      }
    }
  }
  
  return(msgs)
}

# =========================================================================
# 8. HTTP 请求核心
# =========================================================================

# 获取模型列表
fetch_remote_models <- function(silent_on_error = FALSE) {
  base_url <- chat_context$config$baseurl
  models_url <- gsub("/chat/completions/?$", "/models", base_url)
  if (models_url == base_url) models_url <- paste0(base_url, "/models")
  
  if (!silent_on_error) cli_process_start("正在获取可用模型列表...")
  
  tryCatch({
    resp <- httr::GET(
      models_url,
      add_headers(Authorization = paste("Bearer", chat_context$config$api_key)),
      timeout(10)
    )
    
    if (!silent_on_error) cli_process_done()
    
    if (status_code(resp) == 200) {
      data <- content(resp, as = "parsed")
      if (!is.null(data$data)) {
        model_ids <- sapply(data$data, function(x) x$id)
        
        msg_header("可用模型列表", "📦")
        # 高亮当前模型
        for (mid in model_ids) {
          if (mid == chat_context$current_model) {
            cat(green$bold("  ● ", mid, " (当前)\n"))
          } else {
            cat(silver("  ○ ", mid, "\n"))
          }
        }
        cat("\n")
        return(invisible(model_ids))
      } else {
        if (!silent_on_error) msg_warning("返回格式不标准,无法解析模型列表")
      }
    } else {
      if (!silent_on_error) {
        msg_warning(paste("获取模型失败 HTTP", status_code(resp)))
      }
    }
  }, error = function(e) {
    if (!silent_on_error) {
      cli_process_failed()
      msg_warning(paste("连接错误:", e$message))
    }
  })
}

# 简单请求(用于压缩和标题生成)
simple_chat_request <- function(messages) {
  url <- chat_context$config$baseurl
  
  body <- list(
    model = chat_context$current_model,
    messages = messages,
    stream = FALSE
  )
  
  headers <- add_headers(
    `Content-Type` = "application/json",
    `Authorization` = paste("Bearer", chat_context$config$api_key)
  )
  
  tryCatch({
    resp <- POST(url, headers, body = body, encode = "json", timeout(30))
    
    if (status_code(resp) == 200) {
      result <- content(resp, as = "parsed")$choices[[1]]$message$content
      return(safe_string(result))
    } else {
      msg_warning(paste("请求失败 HTTP", status_code(resp)))
      error_text <- content(resp, as = "text", encoding = "UTF-8")
      msg_debug(paste("错误详情:", error_text))
    }
  }, error = function(e) {
    msg_warning(paste("请求错误:", e$message))
    return(NULL)
  })
  
  return(NULL)
}

# 流式对话
stream_chat <- function(messages, show_reasoning = TRUE) {
  url <- chat_context$config$baseurl
  
  # 调试：输出请求体
  if (chat_context$debug_mode) {
    msg_debug("=== 发送到 API 的请求 ===")
    cat(yellow$bold("Endpoint: "), cyan(url), "\n")
    cat(yellow$bold("Model: "), cyan(chat_context$current_model), "\n")
    cat(yellow$bold("消息数量: "), cyan(length(messages)), "\n\n")
    
    # 显示每条消息的结构
    for (i in seq_along(messages)) {
      msg <- messages[[i]]
      cat(magenta$bold(paste("消息", i, "- 角色:", msg$role)), "\n")
      if (is.list(msg$content)) {
        cat(silver("  内容类型: 多部分 ("), length(msg$content), "个部分)\n")
        for (j in seq_along(msg$content)) {
          part <- msg$content[[j]]
          if (part$type == "text") {
            cat(silver(paste("    [", j, "] 文本:", substr(part$text, 1, 50), "...\n")))
          } else if (part$type == "image_url") {
            url_preview <- substr(part$image_url$url, 1, 60)
            cat(silver(paste("    [", j, "] 图片:", url_preview, "...\n")))
          }
        }
      } else {
        cat(silver(paste("  内容: ", substr(msg$content, 1, 100), "...\n")))
      }
      cat("\n")
    }
  }
  
  body <- list(
    model = chat_context$current_model,
    messages = messages,
    stream = TRUE
  )
  
  headers <- add_headers(
    `Content-Type` = "application/json",
    `Authorization` = paste("Bearer", chat_context$config$api_key)
  )
  
  full_content <- ""
  full_reasoning <- ""
  current_state <- "none"
  is_first <- TRUE
  reasoning_header_shown <- FALSE
  content_header_shown <- FALSE
  
  cli_process_start("🚀 连接中...")
  
  stream_cb <- function(chunk) {
    if (is_first) {
      cli_process_done()
      is_first <<- FALSE
    }
    
    raw_text <- tryCatch({
      txt <- rawToChar(chunk)
      if (validUTF8(txt)) {
        txt
      } else {
        iconv(txt, to = "UTF-8", sub = "byte")
      }
    }, error = function(e) {
      rawToChar(chunk[chunk < 128])
    })
    
    raw_text <- enc2utf8(raw_text)
    
    lines <- tryCatch({
      strsplit(raw_text, "\n", fixed = TRUE)[[1]]
    }, error = function(e) {
      character(0)
    })
    
    for (line in lines) {
      if (!startsWith(line, "data: ")) next
      
      json_str <- sub("^data: ", "", line)
      json_str <- trimws(json_str)
      if (json_str == "" || json_str == "[DONE]") next
      
      tryCatch({
        data <- jsonlite::fromJSON(json_str, simplifyVector = FALSE)
        
        if (!is.null(data$choices) && length(data$choices) > 0) {
          delta <- data$choices[[1]]$delta
          
          # 处理推理内容
          r_c <- delta$reasoning_content
          if (!is.null(r_c) && !is.na(r_c[1]) && nchar(r_c) > 0) {
            r_c <- safe_string(r_c)
            if (!reasoning_header_shown && show_reasoning) {
              if (content_header_shown) cat("\n")
              msg_stream("AI Thinking", "💭")
              reasoning_header_shown <<- TRUE
            }
            current_state <<- "reasoning"
            full_reasoning <<- paste0(full_reasoning, r_c)
            if (show_reasoning) {
              cat(yellow(r_c))
            }
          }
          
          # 处理正文内容
          c_c <- delta$content
          if (!is.null(c_c) && !is.na(c_c[1]) && nchar(c_c) > 0) {
            c_c <- safe_string(c_c)
            if (!content_header_shown) {
              if (reasoning_header_shown && show_reasoning) cat("\n\n")
              msg_stream("AI Response", "🤖")
              content_header_shown <<- TRUE
            }
            current_state <<- "content"
            full_content <<- paste0(full_content, c_c)
            cat(green(c_c))
          }
          
          flush.console()
        }
      }, error = function(e) {
        # 静默忽略单个数据块解析错误
        if (chat_context$debug_mode) {
          msg_debug(paste("数据块解析错误:", e$message))
        }
      })
    }
    
    return(TRUE)
  }
  
  tryCatch({
    resp <- POST(
      url,
      headers,
      body = jsonlite::toJSON(body, auto_unbox = TRUE),
      write_stream(stream_cb),
      timeout(120)
    )
    
    # 检查 HTTP 状态
    if (status_code(resp) != 200) {
      msg_error(paste("API 返回错误状态:", status_code(resp)))
      error_text <- content(resp, as = "text", encoding = "UTF-8")
      cat(red(error_text), "\n")
    }
  }, error = function(e) {
    msg_error(paste("Stream Error:", e$message))
    return(NULL)
  })
  
  cat("\n")
  
  # 检测、下载并渲染图片
  if (nchar(full_content) > 0) {
    image_urls <- extract_image_urls(full_content)
    if (length(image_urls) > 0) {
      cat("\n")
      msg_header("检测到生成的图片", "🖼️")
      
      # 创建保存目录
      gen_dir <- chat_context$image_gen_dir
      if (!dir.exists(gen_dir)) {
        dir.create(gen_dir, recursive = TRUE)
        msg_info(paste("创建图片保存目录:", gen_dir))
      }
      
      # 处理每张图片
      for (i in seq_along(image_urls)) {
        url <- image_urls[i]
        cat(cyan$bold(paste("\n[图片", i, "/", length(image_urls), "]\n")))
        
        # 1. 下载图片
        local_path <- download_image(url, gen_dir)
        if (!is.null(local_path)) {
          # 2. 渲染图片
          render_image(local_path)
          # 3. 显示完整路径
          cat(silver(paste("  保存路径:", normalizePath(local_path))), "\n")
        }
      }
      
      # 汇总信息
      cat("\n")
      msg_success(paste("共下载", length(image_urls), "张图片到", gen_dir, "目录"))
    }
  }
  
  return(full_content)
}

# =========================================================================
# 9. 指令系统
# =========================================================================

handle_command <- function(input) {
  parts <- strsplit(trimws(input), "\\s+")[[1]]
  cmd <- parts[1]
  args <- paste(parts[-1], collapse = " ")
  
  switch(
    cmd,
    
    # === 帮助信息 ===
    "/help" = {
      msg_header("可用指令列表", "📖")
      cli_ul(c(
        "=== 会话管理 ===",
        "/newsession       - 创建新会话",
        "/switch           - 切换到其他会话",
        "/sessions         - 列出所有会话",
        "/delete [file]    - 删除指定会话",
        "/title [text]     - 手动设置会话标题",
        "",
        "=== 对话控制 ===",
        "/history          - 查看对话历史",
        "/clean            - 清空当前对话",
        "/compress         - 压缩历史为摘要",
        "",
        "=== 文档处理 (RAG) ===",
        "/addpdf [path]    - 导入 PDF（支持向量化检索）",
        "/unloadpdf [n]    - 卸载指定的 PDF（n=编号，all=全部）",
        "/addtext [path]   - 载入文本文件",
        "",
        "=== 图像功能 ===",
        "/image [paths]    - 添加图片 (本地路径或URL)",
        "/imageinfo        - 查看待发送图片",
        "/clearimages      - 清除待发送图片",
        "/imagedir [path]  - 设置图片保存目录",
        "",
        "=== 系统配置 ===",
        "/init             - 重新配置 API",
        "/setmodel [m]     - 切换模型",
        "/lsmodel          - 列出可用模型",
        "/setmemory [t]    - 追加长期记忆",
        "/delmemory        - 删除指定记忆",
        "/systemprompt     - 修改系统提示词",
        "/debug            - 切换调试模式",
        "",
        "=== 其他 ===",
        "/help             - 显示此帮助",
        "/quit, /exit      - 退出程序"
      ))
    },
    
    # === 调试模式 ===
    "/debug" = {
      chat_context$debug_mode <- !chat_context$debug_mode
      if (chat_context$debug_mode) {
        msg_success("调试模式已开启")
      } else {
        msg_info("调试模式已关闭")
      }
    },
    
    # === 设置图片保存目录 ===
    "/imagedir" = {
      if (nchar(args) == 0) {
        msg_info(paste("当前图片保存目录:", chat_context$image_gen_dir))
        new_dir <- read_console("输入新目录 (回车取消): ")
        if (!is.null(new_dir) && nchar(trimws(new_dir)) > 0) {
          chat_context$image_gen_dir <- trimws(new_dir)
          msg_success(paste("图片保存目录已设置为:", chat_context$image_gen_dir))
        }
      } else {
        chat_context$image_gen_dir <- args
        msg_success(paste("图片保存目录已设置为:", args))
      }
    },
    
    # === 图片命令 ===
    "/image" = {
      if (nchar(args) == 0) {
        msg_info("用法: /image <文件路径1> [文件路径2] ...")
        msg_info("示例: /image photo.jpg https://example.com/image.png")
        if (!is.null(chat_context$pending_images) && length(chat_context$pending_images) > 0) {
          msg_info(paste("当前已准备", length(chat_context$pending_images), "张图片"))
        }
        return()
      }
      
      # 解析路径
      paths <- strsplit(args, "\\s+")[[1]]
      images <- list()
      
      for (path in paths) {
        path <- trimws(path)
        if (startsWith(path, "http://") || startsWith(path, "https://")) {
          # 网络图片
          img <- build_image_url(path)
          images <- append(images, list(img))
          msg_info(paste("✓ 已添加网络图片:", path))
        } else {
          # 本地图片
          img <- encode_image(path)
          if (!is.null(img)) {
            images <- append(images, list(img))
            msg_success(paste("✓ 已编码本地图片:", basename(path)))
          }
        }
      }
      
      if (length(images) > 0) {
        # 追加到待发送列表
        if (is.null(chat_context$pending_images)) {
          chat_context$pending_images <- images
        } else {
          chat_context$pending_images <- append(chat_context$pending_images, images)
        }
        msg_success(paste("已准备", length(chat_context$pending_images), "张图片,请输入问题"))
        
        # 调试输出
        if (chat_context$debug_mode) {
          msg_debug("待发送图片列表:")
          for (i in seq_along(chat_context$pending_images)) {
            img <- chat_context$pending_images[[i]]
            url_preview <- substr(img$image_url$url, 1, 50)
            cat(silver(paste("  [", i, "]", url_preview, "...\n")))
          }
        }
      }
    },
    
    "/imageinfo" = {
      if (is.null(chat_context$pending_images) ||
          length(chat_context$pending_images) == 0) {
        msg_info("当前无待发送图片")
      } else {
        msg_header("待发送图片列表", "🖼️")
        for (i in seq_along(chat_context$pending_images)) {
          img <- chat_context$pending_images[[i]]
          url <- img$image_url$url
          if (grepl("^data:", url)) {
            size_kb <- round(nchar(url) * 0.75 / 1024, 2)
            cat(cyan(sprintf("  [%d] Base64图片 (~%s KB)\n", i, size_kb)))
          } else {
            cat(cyan(sprintf("  [%d] 网络图片: %s\n", i, url)))
          }
        }
      }
    },
    
    "/clearimages" = {
      if (!is.null(chat_context$pending_images) && length(chat_context$pending_images) > 0) {
        count <- length(chat_context$pending_images)
        chat_context$pending_images <- NULL
        msg_success(paste("已清除", count, "张待发送图片"))
      } else {
        msg_info("当前无待发送图片")
      }
    },
    
    # === PDF 处理 ===
    "/addpdf" = {
      # 1. 检查依赖
      if (!requireNamespace("pdftools", quietly = TRUE)) {
        msg_error("缺少 pdftools 包")
        cat(silver("安装命令: install.packages('pdftools')\n"))
        return()
      }
      
      # 2. 检查 embedding 配置
      if (is.null(chat_context$embedding_config)) {
        msg_error("未配置 Embedding")
        cat(silver("\n请在 .env 中添加:\n"))
        cat(silver("embedding:\n"))
        cat(silver("  url: \"https://api.openai.com/v1/embeddings\"\n"))
        cat(silver("  model: \"text-embedding-3-small\"\n"))
        cat(silver("  api_key: \"sk-xxxxx\"  # 可选\n\n"))
        return()
      }
      
      # 3. 获取文件路径
      if (nchar(args) == 0) {
        filepath <- read_console("输入 PDF 文件路径: ")
        if (is.null(filepath) || nchar(trimws(filepath)) == 0) {
          msg_info("已取消")
          return()
        }
      } else {
        filepath <- args
      }
      
      filepath <- trimws(filepath)
      
      # 4. 验证文件
      if (!file.exists(filepath)) {
        msg_error("文件不存在")
        return()
      }
      
      if (!grepl("\\.pdf$", filepath, ignore.case = TRUE)) {
        msg_error("只支持 PDF 格式")
        return()
      }
      
      # 5. 提取文本
      cli_process_start("📄 提取 PDF 文本...")
      tryCatch({
        pdf_text <- pdftools::pdf_text(filepath)
        full_text <- paste(pdf_text, collapse = "\n\n")
        full_text <- safe_string(full_text)
        
        # 清理文本
        full_text <- gsub("\\s+", " ", full_text)  # 合并空格
        full_text <- trimws(full_text)
        
        cli_process_done()
        
        total_chars <- nchar(full_text)
        total_pages <- length(pdf_text)
        msg_success(paste("✓ 提取", total_pages, "页，", total_chars, "字符"))
        
        # 6. 询问处理方式
        cat(cyan("\n选择处理方式:\n"))
        cat("  1. 直接添加（适合 <5000 字）\n")
        cat("  2. 生成摘要\n")
        cat("  3. 向量化存储（推荐 - 支持智能检索）\n")
        cat("  4. 取消\n\n")
        
        choice <- read_console("请选择 (1-4): ")
        
        switch(
          trimws(choice),
          
          # ===== 选项 1: 直接添加 =====
          "1" = {
            if (total_chars > 10000) {
              msg_warning("文档较长，建议使用向量化")
              confirm <- read_console("继续? (y/N): ")
              if (tolower(trimws(confirm)) != "y") {
                return()
              }
            }
            
            chat_context$history <- append(
              chat_context$history,
              list(
                list(
                  role = "user",
                  content = paste0("【PDF - ", basename(filepath), "】\n\n", full_text)
                ),
                list(
                  role = "assistant",
                  content = "已接收 PDF 内容，请问需要我做什么？"
                )
              )
            )
            save_session()
            msg_success("已添加到对话")
          },
          
          # ===== 选项 2: 生成摘要 =====
          "2" = {
            cli_process_start("🤖 生成摘要...")
            
            # 分块
            chunk_size <- 4000
            chunks <- list()
            for (i in seq(1, total_chars, by = chunk_size)) {
              chunk <- substr(full_text, i, min(i + chunk_size - 1, total_chars))
              chunks <- append(chunks, chunk)
            }
            
            # 逐块总结
            summaries <- list()
            for (i in seq_along(chunks)) {
              msg <- list(
                list(role = "system", content = "你是文档摘要助手，用简洁语言总结核心内容。"),
                list(role = "user", content = paste0("总结（", i, "/", length(chunks), "）：\n\n", chunks[[i]]))
              )
              
              summary <- simple_chat_request(msg)
              if (!is.null(summary) && nchar(summary) > 0) {
                summaries <- append(summaries, summary)
              }
            }
            
            cli_process_done()
            
            if (length(summaries) == 0) {
              msg_error("摘要生成失败")
              return()
            }
            
            final_summary <- paste(summaries, collapse = "\n\n")
            
            chat_context$history <- append(
              chat_context$history,
              list(
                list(
                  role = "user",
                  content = paste0("【PDF 摘要 - ", basename(filepath), "】\n\n", final_summary)
                ),
                list(
                  role = "assistant",
                  content = "已阅读文档摘要，有什么需要分析的吗？"
                )
              )
            )
            save_session()
            
            msg_success("摘要已添加")
            cat(cyan("\n【摘要】\n"))
            cat(silver(final_summary), "\n\n")
          },
          
          # ===== 选项 3: 向量化 =====
          "3" = {
            msg_header("PDF 向量化（RAG 模式）", "🧮")
            
            # 获取模型的 token 限制
            model_name <- chat_context$embedding_config$model
            max_tokens <- 8000  # 默认值
            
            # 根据模型设置限制
            if (grepl("bge-m3", model_name, ignore.case = TRUE)) {
              max_tokens <- 6000  # BAAI/bge-m3 限制较低
            } else if (grepl("text-embedding-3", model_name, ignore.case = TRUE)) {
              max_tokens <- 8000  # OpenAI embedding-3
            } else if (grepl("embedding-2", model_name, ignore.case = TRUE)) {
              max_tokens <- 8000
            }
            
            msg_debug(paste("模型:", model_name, "- Token 限制:", max_tokens))
            
            # 步骤 1: 文本分块（使用 token 限制）
            cli_process_start("1️⃣ 智能分块处理...")
            chunks <- chunk_text(full_text, chunk_size = 400, overlap = 40, max_tokens = max_tokens)
            cli_process_done()
            
            msg_info(paste("分块数:", length(chunks)))
            
            # 显示分块统计
            if (chat_context$debug_mode) {
              total_chars <- sum(sapply(chunks, nchar))
              avg_chars <- round(total_chars / length(chunks))
              msg_debug(paste("总字符数:", total_chars))
              msg_debug(paste("平均每块:", avg_chars, "字符"))
            }
            
            # 步骤 2: 批量向量化（减小批次大小）
            cli_process_start("2️⃣ 调用 Embedding API...")
            
            # 根据模型调整批次大小
            batch_size <- if (grepl("bge", model_name, ignore.case = TRUE)) {
              10  # BGE 模型批次更小
            } else {
              50  # OpenAI 等可以大一些
            }
            
            msg_debug(paste("批次大小:", batch_size))
            
            all_embeddings <- list()
            
            for (i in seq(1, length(chunks), by = batch_size)) {
              end_idx <- min(i + batch_size - 1, length(chunks))
              batch_chunks <- chunks[i:end_idx]
              
              msg_debug(paste("处理批次:", i, "-", end_idx))
              
              batch_embeddings <- call_embedding_api(batch_chunks)
              
              if (is.null(batch_embeddings)) {
                cli_process_failed()
                msg_error(paste("向量化失败于批次", i, "-", end_idx))
                
                # 提供降级选项
                cat(yellow("\n建议操作:\n"))
                cat("  1. 减小分块大小（当前可能单块过大）\n")
                cat("  2. 改用摘要模式（选项 2）\n")
                cat("  3. 检查 embedding 模型配置\n\n")
                
                return()
              }
              
              all_embeddings <- append(all_embeddings, batch_embeddings)
              
              # 显示进度
              progress_pct <- round((end_idx / length(chunks)) * 100)
              msg_debug(paste("进度:", progress_pct, "% -", length(all_embeddings), "/", length(chunks), "完成"))
              
              # 避免频率限制
              if (end_idx < length(chunks)) {
                Sys.sleep(0.5)
              }
            }
            
            cli_process_done()
            msg_success(paste("✓ 生成", length(all_embeddings), "个向量"))
            
            # 步骤 3: 保存到会话
            cli_process_start("3️⃣ 保存向量...")
            success <- save_pdf_vectors(filepath, chunks, all_embeddings)
            cli_process_done()
            
            if (success) {
              msg_success("✓ PDF 向量化完成")
              cat(silver("\n向量已保存到当前会话，现在可以直接提问了！\n"))
              cat(silver("示例:\n"))
              cat(silver("  • 这篇文章的主要观点是什么？\n"))
              cat(silver("  • 文中提到的关键数据有哪些？\n"))
              cat(silver("  • 总结文档的核心内容\n\n"))
              
              # 添加更详细的系统提示
              chat_context$history <- append(
                chat_context$history,
                list(
                  list(
                    role = "system",
                    content = paste0(
                      "已加载 PDF 文档《", basename(filepath), "》的向量化数据。\n",
                      "文档已分为 ", length(chunks), " 个文本块，每个用户问题都会自动检索最相关的 3 个片段。\n",
                      "回答时请:\n",
                      "1. 优先基于检索到的文档片段内容\n",
                      "2. 如果片段中没有答案，明确告知用户\n",
                      "3. 可以引用具体的片段编号和相关度"
                    )
                  )
                )
              )
              save_session()
            }
          },
          
          "4" = {
            msg_info("已取消")
          },
          
          {
            msg_warning("无效选择")
          }
        )
        
      }, error = function(e) {
        cli_process_failed()
        msg_error(paste("处理失败:", e$message))
      })
    },
    
    "/unloadpdf" = {
      if (is.null(chat_context$session_file) || !file.exists(chat_context$session_file)) {
        msg_warning("无会话文件")
        return()
      }
      
      tryCatch({
        # 读取会话数据
        con <- file(chat_context$session_file, "r", encoding = "UTF-8")
        session_data <- jsonlite::fromJSON(readLines(con, warn = FALSE), simplifyVector = FALSE)
        close(con)
        
        if (is.null(session_data$pdf_vectors) || length(session_data$pdf_vectors) == 0) {
          msg_info("当前会话无已向量化的 PDF")
          return()
        }
        
        # 如果没有提供参数，显示列表并询问
        if (nchar(args) == 0) {
          msg_header("卸载向量化 PDF", "🗑️")
          
          # 显示列表
          pdf_ids <- names(session_data$pdf_vectors)
          for (i in seq_along(pdf_ids)) {
            pdf_data <- session_data$pdf_vectors[[pdf_ids[i]]]
            cat(cyan(sprintf("  [%d]", i)),
                yellow$bold(pdf_data$filename),
                silver(paste("(", pdf_data$chunk_count, "个分块)")),
                "\n")
          }
          
          cat("\n")
          cat(magenta("选项:\n"))
          cat(silver("  输入编号 - 卸载指定 PDF\n"))
          cat(silver("  all      - 卸载所有 PDF\n"))
          cat(silver("  回车     - 取消操作\n\n"))
          
          choice <- read_console("请选择: ")
          if (is.null(choice) || nchar(trimws(choice)) == 0) {
            msg_info("已取消")
            return()
          }
          args <- trimws(choice)
        }
        
        # 处理 "all" 选项
        if (tolower(args) == "all") {
          confirm <- read_console(paste("确认卸载所有", length(session_data$pdf_vectors), "个 PDF? (y/N): "))
          if (tolower(trimws(confirm)) != "y") {
            msg_info("已取消")
            return()
          }
          
          # 清空所有 PDF 向量
          session_data$pdf_vectors <- list()
          
          # 保存会话
          json_text <- jsonlite::toJSON(
            session_data,
            pretty = TRUE,
            auto_unbox = TRUE,
            ensure_ascii = FALSE
          )
          con <- file(chat_context$session_file, "w", encoding = "UTF-8")
          writeLines(enc2utf8(json_text), con, useBytes = TRUE)
          close(con)
          
          msg_success("已卸载所有 PDF 向量数据")
          return()
        }
        
        # 处理数字选项
        idx <- as.integer(args)
        pdf_ids <- names(session_data$pdf_vectors)
        
        if (is.na(idx) || idx < 1 || idx > length(pdf_ids)) {
          msg_warning("无效的编号")
          return()
        }
        
        # 获取要删除的 PDF 信息
        target_id <- pdf_ids[idx]
        target_pdf <- session_data$pdf_vectors[[target_id]]
        
        # 确认删除
        confirm <- read_console(paste("确认卸载", target_pdf$filename, "? (y/N): "))
        if (tolower(trimws(confirm)) != "y") {
          msg_info("已取消")
          return()
        }
        
        # 删除指定 PDF
        session_data$pdf_vectors[[target_id]] <- NULL
        
        # 保存会话
        json_text <- jsonlite::toJSON(
          session_data,
          pretty = TRUE,
          auto_unbox = TRUE,
          ensure_ascii = FALSE
        )
        con <- file(chat_context$session_file, "w", encoding = "UTF-8")
        writeLines(enc2utf8(json_text), con, useBytes = TRUE)
        close(con)
        
        msg_success(paste("已卸载:", target_pdf$filename))
        
        # 显示剩余 PDF
        if (length(session_data$pdf_vectors) > 0) {
          msg_info(paste("剩余", length(session_data$pdf_vectors), "个 PDF"))
        } else {
          msg_info("所有 PDF 已清空")
        }
        
      }, error = function(e) {
        msg_error(paste("卸载失败:", e$message))
      })
    },
    
    # === 新建会话 ===
    "/newsession" = {
      msg_header("创建新会话", "🆕")
      confirm <- read_console("确认创建新会话? 当前会话将保存 (y/N): ")
      if (tolower(trimws(confirm)) == "y") {
        save_session()
        chat_context$history <- list()
        chat_context$compressed_summary <- ""
        chat_context$full_history <- list()
        chat_context$pending_images <- NULL
        init_session_file(force_new = TRUE)
        msg_success("新会话已创建")
      } else {
        msg_info("已取消")
      }
    },
    
    # === 切换会话 ===
    "/switch" = {
      session_dir <- file.path(getwd(), "chat_logs")
      if (!dir.exists(session_dir)) {
        msg_warning("暂无会话记录")
        return()
      }
      
      files <- list.files(session_dir, pattern = "^chat_.*\\.json$", full.names = TRUE)
      if (length(files) == 0) {
        msg_warning("暂无会话记录")
        return()
      }
      
      msg_header("可切换的会话", "🔄")
      for (i in seq_along(files)) {
        title <- tryCatch({
          con <- file(files[i], "r", encoding = "UTF-8")
          data <- jsonlite::fromJSON(readLines(con, warn = FALSE), simplifyVector = FALSE)
          close(con)
          data$title %||% "未命名对话"
        }, error = function(e) "未命名对话")
        
        info <- file.info(files[i])
        current_marker <- if (files[i] == chat_context$session_file) green(" ← 当前") else ""
        
        cat(cyan(sprintf("  [%d]", i)),
            yellow$bold(title),
            current_marker,
            "\n",
            silver(sprintf("      最后修改: %s", format(info$mtime, "%Y-%m-%d %H:%M"))),
            "\n")
      }
      
      choice <- read_console("\n选择会话编号 (回车取消): ")
      if (nchar(trimws(choice)) > 0) {
        idx <- as.integer(choice)
        if (!is.na(idx) && idx >= 1 && idx <= length(files)) {
          if (files[idx] == chat_context$session_file) {
            msg_info("已经在当前会话中")
          } else {
            save_session()
            chat_context$session_file <- files[idx]
            chat_context$pending_images <- NULL
            init_session_file(force_new = FALSE, json = files[idx])
          }
        } else {
          msg_warning("无效的选择")
        }
      }
    },
    
    # === 删除会话 ===
    "/delete" = {
      if (nchar(args) == 0) {
        msg_warning("用法: /delete <会话文件名>")
        return()
      }
      
      session_dir <- file.path(getwd(), "chat_logs")
      target_file <- file.path(session_dir, args)
      
      if (!file.exists(target_file)) {
        msg_error("会话文件不存在")
        return()
      }
      
      if (target_file == chat_context$session_file) {
        msg_error("不能删除当前活动会话")
        return()
      }
      
      confirm <- read_console(paste("确认删除", args, "? (y/N): "))
      if (tolower(trimws(confirm)) == "y") {
        file.remove(target_file)
        msg_success("会话已删除")
      }
    },
    
    # === 手动设置标题 ===
    "/title" = {
      if (nchar(args) == 0) {
        msg_info(paste("当前标题:", chat_context$session_title))
        new_title <- read_console("输入新标题 (回车取消): ")
        if (nchar(trimws(new_title)) > 0) {
          chat_context$session_title <- trimws(new_title)
          save_session()
          msg_success(paste("标题已更新:", chat_context$session_title))
        }
      } else {
        chat_context$session_title <- args
        save_session()
        msg_success(paste("标题已更新:", args))
      }
    },
    
    # === 清空历史 ===
    "/clean" = {
      has_images <- !is.null(chat_context$pending_images) &&
        length(chat_context$pending_images) > 0
      
      if (has_images) {
        msg_warning(paste("检测到", length(chat_context$pending_images), "张待发送图片"))
        cat(cyan("选择清空模式:\n"))
        cat(silver("  1. 只清空历史对话（保留图片）\n"))
        cat(silver("  2. 清空所有内容（包括图片）\n"))
        cat(silver("  3. 取消操作\n\n"))
        
        choice <- read_console("请选择 (1-3): ")
        switch(
          trimws(choice),
          "1" = {
            chat_context$history <- list()
            chat_context$compressed_summary <- ""
            chat_context$full_history <- list()
            save_session()
            msg_success("历史已清空")
            msg_info(paste("保留了", length(chat_context$pending_images), "张图片"))
          },
          "2" = {
            chat_context$history <- list()
            chat_context$compressed_summary <- ""
            chat_context$full_history <- list()
            chat_context$pending_images <- NULL
            save_session()
            msg_success("所有数据已清空")
          },
          "3" = {
            msg_info("已取消")
          },
          {
            msg_warning("无效选择，已取消操作")
          }
        )
      } else {
        # 无图片，直接清空
        chat_context$history <- list()
        chat_context$compressed_summary <- ""
        chat_context$full_history <- list()
        save_session()
        msg_success("对话历史已清空")
      }
    },
    
    # === 初始化配置 ===
    "/init" = {
      msg_header("初始化配置", "⚙️")
      u <- read_console(paste0("Endpoint [", chat_context$config$baseurl, "]: "))
      if (nchar(u) > 0) chat_context$config$baseurl <- u
      
      k <- read_console(paste0("API Key [***]: "))
      if (nchar(k) > 0) chat_context$config$api_key <- k
      
      m <- read_console(paste0("Model [", chat_context$current_model, "]: "))
      if (nchar(m) > 0) chat_context$current_model <- m
      
      msg_success("配置已更新,正在验证模型列表...")
      fetch_remote_models()
    },
    
    # === 切换模型 ===
    "/setmodel" = {
      if (nchar(args) == 0) {
        msg_info(paste("当前模型:", chat_context$current_model))
      } else {
        old_model <- chat_context$current_model
        chat_context$current_model <- args
        msg_success(paste("已从", old_model, "切换至:", args))
        save_session()
      }
    },
    
    # === 列出模型 ===
    "/lsmodel" = {
      fetch_remote_models()
    },
    
    # === 设置记忆 ===
    "/setmemory" = {
      if (nchar(args) == 0) {
        msg_info("当前长期记忆:")
        if (nchar(chat_context$memory_slot) > 0) {
          cat(silver(chat_context$memory_slot), "\n")
        } else {
          cat(silver("(空)\n"))
        }
      } else {
        chat_context$memory_slot <- paste(chat_context$memory_slot, args, sep = "\n")
        save_session()
        msg_success("长期记忆已追加")
      }
    },
    
    # === 删除记忆 ===
    "/delmemory" = {
      if (nchar(trimws(chat_context$memory_slot)) == 0) {
        msg_warning("当前无长期记忆")
        return()
      }
      
      msg_header("删除记忆", "🗑️")
      memory_lines <- strsplit(chat_context$memory_slot, "\n")[[1]]
      memory_lines <- memory_lines[nchar(trimws(memory_lines)) > 0]
      
      if (length(memory_lines) == 0) {
        msg_warning("当前无有效记忆")
        return()
      }
      
      cat(magenta$bold("【当前记忆列表】\n"))
      for (i in seq_along(memory_lines)) {
        cat(cyan(sprintf("  [%d]", i)), silver(memory_lines[i]), "\n")
      }
      cat("\n")
      
      choice <- read_console("输入要删除的记忆编号 (回车取消): ")
      if (is.null(choice) || nchar(trimws(choice)) == 0) {
        msg_info("已取消")
        return()
      }
      
      idx <- as.integer(choice)
      if (is.na(idx) || idx < 1 || idx > length(memory_lines)) {
        msg_warning("无效的编号")
        return()
      }
      
      deleted_item <- memory_lines[idx]
      memory_lines <- memory_lines[-idx]
      chat_context$memory_slot <- paste(memory_lines, collapse = "\n")
      save_session()
      
      msg_success(paste("已删除:", deleted_item))
      if (length(memory_lines) > 0) {
        cat(silver(paste("\n剩余记忆:\n", chat_context$memory_slot, "\n\n")))
      } else {
        msg_info("所有记忆已清空")
      }
    },
    
    # === 修改系统提示词 ===
    "/systemprompt" = {
      msg_header("修改系统提示词", "⚙️")
      cat(magenta$bold("【当前系统提示词】\n"))
      cat(silver(chat_context$base_system), "\n\n")
      
      cat(cyan("选择输入方式:\n"))
      cat("  1. 从文件导入\n")
      cat("  2. 终端输入 (多行)\n")
      cat("  3. 取消\n\n")
      
      choice <- read_console("请选择 (1-3): ")
      switch(
        trimws(choice),
        "1" = {
          filepath <- read_console("输入文件路径: ")
          if (is.null(filepath) || nchar(trimws(filepath)) == 0) {
            msg_info("已取消")
            return()
          }
          
          filepath <- trimws(filepath)
          if (!file.exists(filepath)) {
            msg_error("文件不存在")
            return()
          }
          
          tryCatch({
            content <- paste(
              readLines(filepath, warn = FALSE, encoding = "UTF-8"),
              collapse = "\n"
            )
            content <- safe_string(content)
            
            if (nchar(trimws(content)) > 0) {
              chat_context$base_system <- content
              save_session()
              msg_success(paste("已从文件导入:", filepath))
              cat(silver(paste("\n新提示词:\n", chat_context$base_system, "\n\n")))
            } else {
              msg_warning("文件内容为空")
            }
          }, error = function(e) {
            msg_error(paste("读取文件失败:", e$message))
          })
        },
        "2" = {
          cat(cyan("\n请输入新的系统提示词 (输入空行结束):\n"))
          new_prompt <- read_console("> ")
          if (is.null(new_prompt)) {
            msg_info("已取消")
            return()
          }
          
          lines <- c(new_prompt)
          repeat {
            line <- read_console("> ")
            if (is.null(line) || nchar(trimws(line)) == 0) break
            lines <- c(lines, line)
          }
          
          final_prompt <- paste(lines, collapse = "\n")
          if (nchar(trimws(final_prompt)) > 0) {
            chat_context$base_system <- safe_string(final_prompt)
            save_session()
            msg_success("系统提示词已更新")
            cat(silver(paste("\n新提示词:\n", chat_context$base_system, "\n\n")))
          } else {
            msg_warning("输入为空,已取消")
          }
        },
        "3" = {
          msg_info("已取消操作")
        },
        {
          msg_warning("无效选择")
        }
      )
    },
    
    # === 载入文件 ===
    "/addtext" = {
      if (!file.exists(args)) {
        msg_error("文件不存在")
      } else {
        content <- paste(readLines(args, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
        content <- safe_string(content)
        
        chat_context$history <- append(
          chat_context$history,
          list(
            list(role = "user", content = paste("【文件内容】\n", content)),
            list(role = "assistant", content = "已收到并理解文件内容")
          )
        )
        save_session()
        msg_success(paste("文件已载入:", args))
      }
    },
    
    # === 查看历史 ===
    "/history" = {
      msg_header("对话历史记录", "📜")
      
      if (nchar(chat_context$compressed_summary) > 0) {
        cat(cyan$bold("【压缩摘要】\n"))
        cat(silver(chat_context$compressed_summary), "\n\n")
        
        if (length(chat_context$full_history) > 0) {
          cat(magenta$bold("【压缩前完整历史】\n\n"))
          for (i in seq_along(chat_context$full_history)) {
            msg <- chat_context$full_history[[i]]
            role_label <- switch(
              msg$role,
              "user" = blue$bold("👤 User"),
              "assistant" = green$bold("🤖 Assistant"),
              "system" = magenta$bold("⚙️ System"),
              cyan$bold(paste("📝", msg$role))
            )
            
            cat(role_label)
            if (!is.null(msg$timestamp)) {
              cat(silver(paste(" [", msg$timestamp, "]")))
            }
            cat("\n")
            
            # 处理内容
            if (is.list(msg$content)) {
              for (part in msg$content) {
                if (!is.null(part$type)) {
                  if (part$type == "text") {
                    cat(silver(safe_string(part$text)), "\n")
                  } else if (part$type == "image_url") {
                    cat(yellow("[图片]"), "\n")
                  }
                }
              }
            } else {
              cat(silver(safe_string(msg$content)), "\n")
            }
            cat("\n")
          }
        }
        
        if (length(chat_context$history) > 0) {
          cat(yellow$bold("【压缩后新对话】\n\n"))
          for (i in seq_along(chat_context$history)) {
            msg <- chat_context$history[[i]]
            role_label <- switch(
              msg$role,
              "user" = blue$bold("👤 User"),
              "assistant" = green$bold("🤖 Assistant"),
              cyan$bold(paste("📝", msg$role))
            )
            
            cat(role_label)
            if (!is.null(msg$timestamp)) {
              cat(silver(paste(" [", msg$timestamp, "]")))
            }
            cat("\n")
            
            if (is.list(msg$content)) {
              for (part in msg$content) {
                if (!is.null(part$type)) {
                  if (part$type == "text") {
                    cat(silver(safe_string(part$text)), "\n")
                  } else if (part$type == "image_url") {
                    cat(yellow("[图片]"), "\n")
                  }
                }
              }
            } else {
              cat(silver(safe_string(msg$content)), "\n")
            }
            cat("\n")
          }
        }
      } else {
        if (length(chat_context$history) == 0) {
          msg_info("历史记录为空")
        } else {
          for (i in seq_along(chat_context$history)) {
            msg <- chat_context$history[[i]]
            role_label <- switch(
              msg$role,
              "user" = blue$bold("👤 User"),
              "assistant" = green$bold("🤖 Assistant"),
              "system" = magenta$bold("⚙️ System"),
              cyan$bold(paste("📝", msg$role))
            )
            
            cat(role_label)
            if (!is.null(msg$timestamp)) {
              cat(silver(paste(" [", msg$timestamp, "]")))
            }
            cat("\n")
            
            if (is.list(msg$content)) {
              for (part in msg$content) {
                if (!is.null(part$type)) {
                  if (part$type == "text") {
                    cat(silver(safe_string(part$text)), "\n")
                  } else if (part$type == "image_url") {
                    cat(yellow("[图片]"), "\n")
                  }
                }
              }
            } else {
              cat(silver(safe_string(msg$content)), "\n")
            }
            cat("\n")
          }
        }
      }
    },
    
    # === 压缩历史 ===
    "/compress" = {
      if (length(chat_context$history) == 0) {
        msg_warning("历史为空,无需压缩")
        return()
      }
      
      cli_process_start("正在压缩历史对话...")
      summary <- simple_chat_request(append(
        chat_context$history,
        list(list(
          role = "user",
          content = "请用300字以内简要总结上述对话的核心内容和关键信息,保留重要细节。用中文回答。"
        ))
      ))
      cli_process_done()
      
      if (!is.null(summary) && nchar(summary) > 0) {
        chat_context$full_history <- chat_context$history
        chat_context$compressed_summary <- summary
        chat_context$history <- list()
        save_session()
        
        msg_success("历史已压缩为摘要,后续对话将基于摘要进行")
        cat(cyan("\n【摘要内容】\n"))
        cat(silver(summary), "\n\n")
        msg_info("使用 /history 可查看完整压缩前后的记录")
      } else {
        msg_error("压缩失败,请检查网络连接")
      }
    },
    
    # === 列出所有会话 ===
    "/sessions" = {
      session_dir <- file.path(getwd(), "chat_logs")
      if (!dir.exists(session_dir)) {
        msg_warning("暂无会话记录")
        return()
      }
      
      files <- list.files(session_dir, pattern = "^chat_.*\\.json$", full.names = TRUE)
      if (length(files) == 0) {
        msg_warning("暂无会话记录")
      } else {
        msg_header("历史会话列表", "📁")
        for (f in files) {
          title <- tryCatch({
            con <- file(f, "r", encoding = "UTF-8")
            data <- jsonlite::fromJSON(readLines(con, warn = FALSE), simplifyVector = FALSE)
            close(con)
            data$title %||% "未命名对话"
          }, error = function(e) "未命名对话")
          
          info <- file.info(f)
          current_marker <- if (f == chat_context$session_file) green(" ← 当前") else ""
          
          cat(cyan("  •"),
              yellow$bold(title),
              current_marker,
              "\n",
              silver(sprintf("    文件: %s", basename(f))),
              "\n",
              silver(sprintf("    修改: %s", format(info$mtime, "%Y-%m-%d %H:%M"))),
              "\n\n")
        }
      }
    },
    
    # === 退出 ===
    "/quit" = {
      save_session()
      msg_success("会话已保存,再见!")
      quit(save = "no")
    },
    
    "/exit" = {
      save_session()
      msg_success("会话已保存,再见!")
      quit(save = "no")
    },
    
    # === 未知指令 ===
    msg_warning("未知指令,输入 /help 查看帮助")
  )
}

# =========================================================================
# 10. 主程序
# =========================================================================

main <- function() {
  option_list <- list(
    make_option(c("-p", "--provider"), type = "character"),
    make_option(c("-m", "--model"), type = "character"),
    make_option(c("-S", "--system"), type = "character", default = "你是一个智能助手。"),
    make_option(c("-s", "--show_reasoning"), action = "store_true", default = TRUE),
    make_option(c("-q", "--question"), type = "character"),
    make_option(c("-r", "--resume"), action = "store_true", default = FALSE),
    make_option(c("-i", "--image"), type = "character"),
    make_option(c("-d", "--debug"), action = "store_true", default = FALSE),
    make_option(c("-o", "--output_dir"), type = "character", default = "image_gen")
  )
  
  args <- parse_args(OptionParser(option_list = option_list))
  
  # 设置调试模式
  chat_context$debug_mode <- args$debug
  
  # 设置图片输出目录
  chat_context$image_gen_dir <- args$output_dir
  
  # 启动标题
  cli_rule(left = cyan$bold("🤖 Starlight CLI v2.4.0"), right = "RAG Full Edition")
  
  # 加载配置
  if (!file.exists(".env")) {
    msg_warning(".env 配置文件不存在")
    msg_info("请使用 /init 进行初始配置")
    chat_context$config <- list(baseurl = "", api_key = "")
    chat_context$embedding_config <- NULL
  } else {
    full_config <- yaml::read_yaml(".env")
    
    # 1. 加载全局 embedding 配置
    if (!is.null(full_config$embedding)) {
      chat_context$embedding_config <- full_config$embedding
      msg_debug("已加载 Embedding 配置")
      msg_debug(paste("  模型:", chat_context$embedding_config$model))
      msg_debug(paste("  地址:", chat_context$embedding_config$url))
    } else {
      chat_context$embedding_config <- NULL
      msg_debug("未配置 Embedding")
    }
    
    # 2. 选择聊天 Provider
    available_providers <- setdiff(names(full_config), "embedding")
    prov <- if (!is.null(args$provider)) {
      args$provider
    } else {
      sample(available_providers, 1)
    }
    
    if (!prov %in% available_providers) {
      msg_error(paste("Provider", prov, "未在 .env 中配置"))
      return()
    }
    
    chat_context$config <- full_config[[prov]]
    chat_context$current_provider <- prov
    
    # 3. 选择聊天模型
    chat_context$current_model <- if (!is.null(args$model)) {
      args$model
    } else {
      sample(chat_context$config$model, 1)
    }
    
    msg_info(paste("Provider:", prov))
    msg_info(paste("Model:", chat_context$current_model))
    
    # 4. 显示标题模型配置
    if (!is.null(chat_context$config$title_model)) {
      msg_debug(paste("标题模型:", chat_context$config$title_model))
    } else {
      msg_debug("标题模型: 未配置（将使用当前模型）")
    }
    
    msg_info(paste("图片保存目录:", chat_context$image_gen_dir))
    fetch_remote_models(silent_on_error = TRUE)
  }
  
  chat_context$base_system <- args$system
  
  # 初始化会话文件
  init_session_file(force_new = !args$resume)
  
  # 处理命令行图片参数
  if (!is.null(args$image)) {
    image_paths <- strsplit(args$image, ",")[[1]]
    images <- list()
    
    for (path in image_paths) {
      path <- trimws(path)
      if (startsWith(path, "http://") || startsWith(path, "https://")) {
        images <- append(images, list(build_image_url(path)))
      } else {
        img <- encode_image(path)
        if (!is.null(img)) {
          images <- append(images, list(img))
        }
      }
    }
    
    if (length(images) > 0) {
      chat_context$pending_images <- images
      msg_success(paste("已加载", length(images), "张图片"))
    }
  }
  
  # 单次问答模式
  if (!is.null(args$question)) {
    reply <- stream_chat(
      build_messages(args$question, chat_context$pending_images),
      args$show_reasoning
    )
    
    if (!is.null(reply) && nchar(reply) > 0) {
      add_conversation(args$question, reply, chat_context$pending_images)
    }
    return()
  }
  
  # 交互模式提示
  msg_success("系统就绪,输入 /help 查看可用指令")
  if (chat_context$debug_mode) {
    msg_warning("调试模式已启用")
  }
  
  # 主循环
  while (TRUE) {
    # 显示待发送图片提示
    prompt_text <- "\n💬 You > "
    if (!is.null(chat_context$pending_images) && length(chat_context$pending_images) > 0) {
      prompt_text <- paste0("\n🖼️  [", length(chat_context$pending_images), " 张图片] You > ")
    }
    
    input <- read_console(crayon::blue$bold(prompt_text))
    
    if (is.null(input)) break
    if (length(input) == 0 || nchar(trimws(input)) == 0) next
    
    if (startsWith(input, "/")) {
      handle_command(input)
    } else {
      reply <- stream_chat(
        build_messages(input, chat_context$pending_images),
        args$show_reasoning
      )
      
      if (!is.null(reply) && nchar(reply) > 0) {
        add_conversation(input, reply, chat_context$pending_images)
        # 发送后清除图片
        chat_context$pending_images <- NULL
      }
    }
  }
}

# 程序入口
if (sys.nframe() == 0) main()