#!/usr/bin/env Rscript
# =========================================================================
#           🤖 星光通用大模型聊天客户端 (Starlight CLI)
#          Version: 1.5.0 (单会话+自动标题生成)
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
chat_context$current_model <- ""            # 当前模型
chat_context$compressed_summary <- ""       # 压缩后的摘要
chat_context$full_history <- list()         # 完整历史记录(压缩前保留)
chat_context$session_file <- ""             # 当前会话文件路径
chat_context$session_title <- ""            # 会话标题

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
    stream  = list(color = cyan, emoji = "💬", prefix = "")
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

# =========================================================================
# 4. 会话文件管理 (单会话+标题生成)
# =========================================================================

# 生成对话标题
generate_session_title <- function() {
  # 如果历史为空，返回默认标题
  if (length(chat_context$history) == 0) {
    return("新对话")
  }
  
  # 取前3轮对话作为上下文
  sample_history <- head(chat_context$history, 6)
  
  # 构建标题生成请求
  title_messages <- c(
    list(list(
      role = "system",
      content = "你是一个专业的对话标题生成助手。根据用户对话内容，生成一个简洁精准的中文标题（8-15字），直接输出标题，不要有任何其他内容。"
    )),
    sample_history,
    list(list(
      role = "user",
      content = "请为上述对话生成一个简洁的标题（8-15字）"
    ))
  )
  
  cli_process_start("🏷️  生成对话标题中...")
  
  title <- simple_chat_request(title_messages)
  
  cli_process_done()
  
  if (!is.null(title) && nchar(title) > 0) {
    # 清理标题：移除引号、空格、换行
    title <- gsub("[\"'『』【】\n\r]", "", title)
    title <- trimws(title)
    
    # 限制长度
    if (nchar(title, type = "width") > 20) {
      title <- substr(title, 1, 20)
    }
    
    return(title)
  }
  
  # 生成失败，使用首句作为标题
  first_user_msg <- NULL
  for (msg in chat_context$history) {
    if (msg$role == "user") {
      first_user_msg <- msg$content
      break
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
init_session_file <- function(force_new = FALSE,json = NULL) {
  session_dir <- file.path(getwd(), "chat_logs")
  if (!dir.exists(session_dir)) {
    dir.create(session_dir, recursive = TRUE)
  }
  
  # 1. 如果不强制创建新会话，尝试找到最新的会话文件
  if (!force_new) {
    existing_files <- list.files(
      session_dir, 
      pattern = "^chat_.*\\.json$", 
      full.names = TRUE
    )
    
    if (length(existing_files) > 0) {
      # 按修改时间排序，取最新的
      if (!is.null(json) && file.exists(json)){
        latest_file <- json
      }else{
        latest_file <- existing_files[order(file.mtime(existing_files), decreasing = TRUE)[1]]
      }
      
      # 尝试加载现有会话
      tryCatch({
        con <- file(latest_file, "r", encoding = "UTF-8")
        session_data <- jsonlite::fromJSON(readLines(con, warn = FALSE), simplifyVector = FALSE)
        close(con)
        
        # 恢复会话状态
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
        
        return(latest_file)
      }, error = function(e) {
        msg_warning(paste("加载会话失败，将创建新会话:", e$message))
      })
    }
  }
  
  # 2. 创建新会话文件
  timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  session_file <- file.path(session_dir, paste0("chat_", timestamp, ".json"))
  chat_context$session_file <- session_file
  chat_context$session_title <- "新对话"
  
  # 初始化会话数据
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
    full_history_before_compress = list()
  )
  
  save_session(session_data)
  msg_info(paste("新会话:", basename(session_file)))
  
  return(session_file)
}

# 保存会话数据（增加更新时间戳）
save_session <- function(session_data = NULL) {
  if (is.null(session_data)) {
    # 读取原有的创建时间
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

# 添加对话记录（编码安全版本）
add_conversation <- function(user_input, assistant_reply) {
  # 确保输入输出都是 UTF-8
  user_input <- safe_string(user_input)
  assistant_reply <- safe_string(assistant_reply)
  
  chat_context$history <- c(
    chat_context$history,
    list(
      list(
        role = "user",
        content = user_input,
        timestamp = as.character(Sys.time())
      ),
      list(
        role = "assistant",
        content = assistant_reply,
        timestamp = as.character(Sys.time())
      )
    )
  )
  
  # 每5轮对话或首次对话后自动生成标题
  if (length(chat_context$history) == 2 || length(chat_context$history) %% 10 == 0) {
    new_title <- generate_session_title()
    if (new_title != chat_context$session_title) {
      chat_context$session_title <- new_title
      msg_info(paste("📝 对话标题已更新:", new_title))
    }
  }
  
  save_session()
}

# =========================================================================
# 5. 辅助工具函数
# =========================================================================

read_console <- function(prompt_str) {
  if (interactive()) {
    input <- readline(prompt_str)
  } else {
    cat(prompt_str)
    input <- readLines("stdin", n = 1, warn = FALSE)
    if (length(input) == 0) return(NULL)
  }
  
  # 确保输入为 UTF-8
  if (!is.null(input) && length(input) > 0 && nchar(input) > 0) {
    input <- enc2utf8(input)
  }
  return(input)
}

# 构建消息列表（改进版：根据是否压缩选择不同策略）
build_messages <- function(user_input = NULL) {
  msgs <- list()
  
  # 1. 基础系统提示词 + 长期记忆
  full_system_text <- paste(
    chat_context$base_system,
    chat_context$memory_slot,
    sep = "\n"
  )
  
  # 2. 如果已压缩，使用摘要模式
  if (nchar(trimws(chat_context$compressed_summary)) > 0) {
    full_system_text <- paste(
      full_system_text,
      "\n\n=== 历史对话摘要 ===\n",
      chat_context$compressed_summary,
      "\n===================\n",
      sep = ""
    )
  }
  
  if (nchar(trimws(full_system_text)) > 0) {
    msgs[[1]] <- list(role = "system", content = safe_string(full_system_text))
  }
  
  # 3. 当前对话历史（压缩后为空或新对话）
  msgs <- c(msgs, chat_context$history)
  
  # 4. 当前用户输入
  if (!is.null(user_input) && nchar(user_input) > 0) {
    msgs <- c(msgs, list(list(role = "user", content = safe_string(user_input))))
  }
  
  return(msgs)
}

# =========================================================================
# 6. HTTP 请求核心
# =========================================================================

# --- A. 获取模型列表 ---
fetch_remote_models <- function(silent_on_error = FALSE) {
  base_url <- chat_context$config$baseurl
  models_url <- gsub("/chat/completions/?$", "/models", base_url)
  if (models_url == base_url) models_url <- paste0(base_url, "/models")
  
  if (!silent_on_error) cli_process_start("正在获取可用模型列表...")
  
  tryCatch({
    resp <- httr::GET(
      models_url,
      add_headers(Authorization = paste("Bearer", chat_context$config$api_key))
    )
    
    if (!silent_on_error) cli_process_done()
    
    if (status_code(resp) == 200) {
      data <- content(resp, as = "parsed")
      if (!is.null(data$data)) {
        model_ids <- sapply(data$data, function(x) x$id)
        msg_header("可用模型列表", "📦")
        print(model_ids)
        cat("\n")
        return(invisible(model_ids))
      } else {
        if (!silent_on_error) msg_warning("返回格式不标准，无法解析模型列表")
      }
    } else {
      if (!silent_on_error) {
        msg_warning(paste("获取模型失败 HTTP", status_code(resp)))
      }
    }
  }, error = function(e) {
    if (!silent_on_error) {
      cli_process_failed()
      msg_warning("连接错误，跳过模型列表获取")
    }
  })
}

# --- B. 简单请求（用于压缩和标题生成） ---
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
    resp <- POST(url, headers, body = body, encode = "json")
    if (status_code(resp) == 200) {
      result <- content(resp, as = "parsed")$choices[[1]]$message$content
      return(safe_string(result))
    }
  }, error = function(e) return(NULL))
  
  return(NULL)
}

# --- C. 流式对话（修复版） ---
stream_chat <- function(messages, show_reasoning = TRUE) {
  url <- chat_context$config$baseurl
  
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
  
  # 标题已显示标志
  reasoning_header_shown <- FALSE
  content_header_shown <- FALSE
  
  cli_process_start("🚀 连接中...")
  
  stream_cb <- function(chunk) {
    if (is_first) {
      cli_process_done()
      is_first <<- FALSE
    }
    
    # 多重编码安全转换
    raw_text <- tryCatch({
      txt <- rawToChar(chunk)
      # 验证 UTF-8 合法性
      if (validUTF8(txt)) {
        txt
      } else {
        # 强制转换为 UTF-8
        iconv(txt, to = "UTF-8", sub = "byte")
      }
    }, error = function(e) {
      # 降级方案：只保留 ASCII 字符
      rawToChar(chunk[chunk < 128])
    })
    
    # 确保为 UTF-8
    raw_text <- enc2utf8(raw_text)
    
    # 安全分割行
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
          
          # ===== 处理推理内容 =====
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
          
          # ===== 处理正文内容 =====
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
        # 静默忽略单个数据块的解析错误
      })
    }
    return(TRUE)
  }
  
  tryCatch({
    POST(
      url,
      headers,
      body = jsonlite::toJSON(body, auto_unbox = TRUE),
      write_stream(stream_cb)
    )
  }, error = function(e) {
    msg_error(paste("Stream Error:", e$message))
    return(NULL)
  })
  
  cat("\n")
  return(full_content)
}

# =========================================================================
# 7. 指令系统（增强版）
# =========================================================================

handle_command <- function(input) {
  parts <- strsplit(trimws(input), "\\s+")[[1]]
  cmd <- parts[1]
  args <- paste(parts[-1], collapse = " ")
  
  switch(
    cmd,
    
    # --- 帮助信息 ---
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
        "=== 系统配置 ===",
        "/init             - 重新配置 API",
        "/setmodel [m]     - 切换模型",
        "/lsmodel          - 列出可用模型",
        "/setmemory [t]    - 追加长期记忆",
        "/delmemory        - 删除指定记忆",  # ← 新增
        "/addtext [f]      - 载入文件到上下文",
        "/execute [cmd]    - 执行系统命令",
        "/systemprompt     - 修改系统提示词",
        "",
        "=== 其他 ===",
        "/help             - 显示此帮助",
        "/quit, /exit      - 退出程序"
      ))
    },
    
    # --- 新建会话 ---
    "/newsession" = {
      msg_header("创建新会话", "🆕")
      confirm <- read_console("确认创建新会话? 当前会话将保存 (y/N): ")
      if (tolower(trimws(confirm)) == "y") {
        save_session()
        
        # 重置上下文
        chat_context$history <- list()
        chat_context$compressed_summary <- ""
        chat_context$full_history <- list()
        
        # 创建新会话文件
        init_session_file(force_new = TRUE)
        msg_success("新会话已创建")
      } else {
        msg_info("已取消")
      }
    },
    
    # --- 切换会话 ---
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
      
      # 读取每个文件的标题
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
            init_session_file(force_new = FALSE,json = files[idx])
          }
        } else {
          msg_warning("无效的选择")
        }
      }
    },
    
    # --- 删除会话 ---
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
    
    # --- 手动设置标题 ---
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
    
    # --- 清空历史 ---
    "/clean" = {
      chat_context$history <- list()
      chat_context$compressed_summary <- ""
      chat_context$full_history <- list()
      save_session()
      msg_success("对话历史已清空")
    },
    
    # --- 初始化配置 ---
    "/init" = {
      msg_header("初始化配置", "⚙️")
      u <- read_console(paste0("Endpoint [", chat_context$config$baseurl, "]: "))
      if (nchar(u) > 0) chat_context$config$baseurl <- u
      
      k <- read_console(paste0("API Key [***]: "))
      if (nchar(k) > 0) chat_context$config$api_key <- k
      
      m <- read_console(paste0("Model [", chat_context$current_model, "]: "))
      if (nchar(m) > 0) chat_context$current_model <- m
      
      msg_success("配置已更新，正在验证模型列表...")
      fetch_remote_models()
    },
    
    # --- 切换模型 ---
    "/setmodel" = {
      if (nchar(args) == 0) {
        msg_info(paste("当前模型:", chat_context$current_model))
      } else {
        chat_context$current_model <- args
        msg_success(paste("已切换至:", args))
        save_session()
      }
    },
    
    # --- 列出模型 ---
    "/lsmodel" = {
      fetch_remote_models()
    },
    
    # --- 设置记忆 ---
    "/setmemory" = {
      chat_context$memory_slot <- paste(chat_context$memory_slot, args, sep = "\n")
      save_session()
      msg_success("长期记忆已追加")
    },
    "/delmemory" = {
      if (nchar(trimws(chat_context$memory_slot)) == 0) {
        msg_warning("当前无长期记忆")
        return()
      }
      
      msg_header("删除记忆", "🗑️")
      
      # 按行分割记忆
      memory_lines <- strsplit(chat_context$memory_slot, "\n")[[1]]
      memory_lines <- memory_lines[nchar(trimws(memory_lines)) > 0]  # 过滤空行
      
      if (length(memory_lines) == 0) {
        msg_warning("当前无有效记忆")
        return()
      }
      
      # 显示所有记忆条目
      cat(magenta$bold("【当前记忆列表】\n"))
      for (i in seq_along(memory_lines)) {
        cat(cyan(sprintf("  [%d]", i)), silver(memory_lines[i]), "\n")
      }
      cat("\n")
      
      # 选择要删除的记忆
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
      
      # 删除指定记忆
      deleted_item <- memory_lines[idx]
      memory_lines <- memory_lines[-idx]
      
      # 更新记忆槽
      chat_context$memory_slot <- paste(memory_lines, collapse = "\n")
      save_session()
      
      msg_success(paste("已删除:", deleted_item))
      
      # 显示剩余记忆
      if (length(memory_lines) > 0) {
        cat(silver(paste("\n剩余记忆:\n", chat_context$memory_slot, "\n\n")))
      } else {
        msg_info("所有记忆已清空")
      }
    },
    
    # --- 修改系统提示词 ---
    "/systemprompt" = {
      msg_header("修改系统提示词", "⚙️")
      
      # 显示当前系统提示词
      cat(magenta$bold("【当前系统提示词】\n"))
      cat(silver(chat_context$base_system), "\n\n")
      
      # 输入新提示词
      cat(cyan("请输入新的系统提示词 (支持多行，输入空行结束):\n"))
      new_prompt <- read_console("> ")  # ← 修复：添加空字符串参数
      lines <- c(new_prompt)
      
      # 支持多行输入
      repeat {
        line <- read_console("> ")  # ← 修复：添加空字符串参数
        if (is.null(line) || nchar(trimws(line)) == 0) break
        lines <- c(lines, line)
      }
      
      # 更新系统提示词
      final_prompt <- paste(lines, collapse = "\n")
      if (nchar(trimws(final_prompt)) > 0) {
        chat_context$base_system <- safe_string(final_prompt)
        save_session()
        msg_success("系统提示词已更新")
        cat(silver(paste("\n新提示词:\n", chat_context$base_system, "\n\n")))
      } else {
        msg_warning("输入为空，已取消")
      }
    },
    
    # --- 载入文件 ---
    "/addtext" = {
      if (!file.exists(args)) {
        msg_error("文件不存在")
      } else {
        content <- paste(readLines(args, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
        content <- safe_string(content)
        chat_context$history <- c(
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
    
    # --- 查看历史（增强版：区分压缩前后） ---
    "/history" = {
      msg_header("对话历史记录", "📜")
      
      # 1. 显示压缩摘要（如果存在）
      if (nchar(chat_context$compressed_summary) > 0) {
        cat(cyan$bold("【压缩摘要】\n"))
        cat(silver(chat_context$compressed_summary), "\n\n")
        
        # 2. 显示压缩前的完整历史
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
            cat(silver(safe_string(msg$content)), "\n\n")
          }
        }
        
        # 3. 显示压缩后的新对话
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
            cat(silver(safe_string(msg$content)), "\n\n")
          }
        }
      } else {
        # 未压缩：显示当前历史
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
            cat(silver(safe_string(msg$content)), "\n\n")
          }
        }
      }
    },
    
    # --- 压缩历史（增强版：保留完整记录） ---
    "/compress" = {
      if (length(chat_context$history) == 0) {
        msg_warning("历史为空，无需压缩")
        return()
      }
      
      cli_process_start("正在压缩历史对话...")
      
      # 生成摘要
      summary <- simple_chat_request(c(
        chat_context$history,
        list(list(
          role = "user",
          content = "请用300字以内简要总结上述对话的核心内容和关键信息，保留重要细节。用中文回答。"
        ))
      ))
      
      cli_process_done()
      
      if (!is.null(summary) && nchar(summary) > 0) {
        # 保存压缩前的完整历史
        chat_context$full_history <- chat_context$history
        
        # 保存摘要
        chat_context$compressed_summary <- summary
        
        # 清空当前历史（准备新对话）
        chat_context$history <- list()
        
        # 保存到文件
        save_session()
        
        msg_success("历史已压缩为摘要，后续对话将基于摘要进行")
        cat(cyan("\n【摘要内容】\n"))
        cat(silver(summary), "\n\n")
        msg_info("使用 /history 可查看完整压缩前后的记录")
      } else {
        msg_error("压缩失败，请检查网络连接")
      }
    },
    
    # --- 列出所有会话 ---
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
          # 读取标题
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
    
    # --- 执行系统命令 ---
    "/execute" = {
      tryCatch({
        system(args)
        msg_success("命令执行完成")
      }, error = function(e) {
        msg_error(paste("执行失败:", e$message))
      })
    },
    
    # --- 退出 ---
    "/quit" = {
      msg_success("会话已保存，再见!")
      quit(save = "no")
    },
    
    "/exit" = {
      msg_success("会话已保存，再见!")
      quit(save = "no")
    },
    
    # --- 未知指令 ---
    msg_warning("未知指令，输入 /help 查看帮助")
  )
}

# =========================================================================
# 8. 主程序
# =========================================================================

main <- function() {
  option_list <- list(
    make_option(c("-p", "--provider"), type = "character"),
    make_option(c("-m", "--model"), type = "character"),
    make_option(c("-S", "--system"), type = "character", default = "你是一个智能助手。"),
    make_option(c("-s", "--show_reasoning"), action = "store_true", default = TRUE),
    make_option(c("-q", "--question"), type = "character"),
    make_option(c("-r", "--resume"), action = "store_true", default = TRUE)  # 新增：是否恢复会话
  )
  
  args <- parse_args(OptionParser(option_list = option_list))
  
  # 启动标题
  cli_rule(left = cyan$bold("🤖 Starlight CLI v1.5.0"), right = "Smart Session Manager")
  
  # 加载配置
  if (!file.exists(".env")) {
    msg_warning(".env 配置文件不存在")
    msg_info("请使用 /init 进行初始配置")
    chat_context$config <- list(baseurl = "", api_key = "")
  } else {
    full_config <- yaml::read_yaml(".env")
    prov <- if (!is.null(args$provider)) args$provider else sample(names(full_config), 1)
    chat_context$config <- full_config[[prov]]
    chat_context$current_model <- if (!is.null(args$model)) {
      args$model
    } else {
      sample(chat_context$config$model, 1)
    }
    
    msg_info(paste("Provider:", prov))
    msg_info(paste("Model:", chat_context$current_model))
    
    # 启动时自动列出模型
    fetch_remote_models(silent_on_error = TRUE)
  }
  
  chat_context$base_system <- args$system
  
  # 初始化会话文件（默认新建会话）
  init_session_file(force_new = args$resume)
  
  # 单次问答模式
  if (!is.null(args$question)) {
    reply <- stream_chat(build_messages(args$question), args$show_reasoning)
    if (!is.null(reply) && nchar(reply) > 0) {
      add_conversation(args$question, reply)
    }
    return()
  }
  
  # 交互模式提示
  msg_success("系统就绪，输入 /help 查看可用指令")
  
  # 主循环
  while (TRUE) {
    input <- read_console(crayon::blue$bold("\n💬 You > "))
    
    if (is.null(input)) break
    if (length(input) == 0 || nchar(trimws(input)) == 0) next
    
    if (startsWith(input, "/")) {
      handle_command(input)
    } else {
      reply <- stream_chat(build_messages(input), args$show_reasoning)
      if (!is.null(reply) && nchar(reply) > 0) {
        add_conversation(input, reply)
      }
    }
  }
}

# 程序入口
if (sys.nframe() == 0) main()