# =========================================================================
#
#           🤖 星光通用大模型聊天客户端 (Starlight LLM Chat Client in R)
#
# 描述:
#   本脚本是一个通用的命令行客户端,用于与兼容OpenAI API的大语言模型进行交互。
#   支持多服务商、多模型配置,系统提示词(System Prompt),并具备流式输出能力。
#
# 作者: fallingstar,developed under the help of Gemini 2.5 pro/Gemini 3 pro/claude 4.5
# 日期: 2024-01-01
#
# =========================================================================


# --- 1. 加载依赖包 ---
suppressPackageStartupMessages({
  library(optparse)
  library(httr)
  library(jsonlite)
  library(yaml)
  library(cli)
  library(crayon)
})

# --- 2. 定义命令行参数 ---
option_list <- list(
  make_option(c("-t","--use_text"), type = "character", default = NULL,
              help = "是否加载文本文件作为上下文信息"),
  make_option(c("-m", "--model"), type = "character", default = NULL,
              help = "指定要使用的模型名称。如果留空,则从服务商的模型列表中随机选择一个"),
  make_option(c("-p", "--provider"), type = "character", default = NULL,
              help = "指定 .env 文件中配置的服务商。如果留空,则随机选择一个"),
  make_option(c("-q", "--question"), type = "character", default = "我是小白,告诉我怎么使用这个操作手册",
              help = "向大语言模型提出的问题"),
  make_option(c("-S", "--system"), type = "character", default = "你是一个乐于助人的AI助手。",
              help = "系统提示词 (System Prompt),用于设定模型的人设"),
  make_option(c("-s", "--show_reasoning"), type = "logical", default = TRUE,
              help = "在流式输出中,是否显示模型的思考过程")
)

args <- parse_args(OptionParser(option_list = option_list))


# --- 3. 辅助函数：美化输出 ---

#' 打印带边框的文本块
print_box <- function(text, title = NULL, border_color = "cyan", width = 80) {
  border_char <- "─"
  corner_tl <- "╭"
  corner_tr <- "╮"
  corner_bl <- "╰"
  corner_br <- "╯"
  vertical <- "│"
  
  color_fn <- switch(border_color,
                     "cyan" = cyan,
                     "green" = green,
                     "yellow" = yellow,
                     "blue" = blue,
                     "magenta" = magenta,
                     "red" = red,
                     cyan)
  
  # 顶部边框
  if (!is.null(title)) {
    title_text <- paste0(" ", title, " ")
    title_len <- nchar(title_text, type = "width")
    left_len <- floor((width - title_len - 2) / 2)
    right_len <- max(0, width - title_len - left_len - 2)
    top_line <- paste0(
      corner_tl,
      strrep(border_char, left_len),
      title_text,
      strrep(border_char, right_len),
      corner_tr
    )
  } else {
    top_line <- paste0(corner_tl, strrep(border_char, width - 2), corner_tr)
  }
  
  cat(color_fn(top_line), "\n")
  
  # 内容行
  lines <- strsplit(text, "\n")[[1]]
  for (line in lines) {
    if (nchar(line, type = "width") > width - 4) {
      line <- paste0(substr(line, 1, width - 7), "...")
    }
    padding <- max(0, width - nchar(line, type = "width") - 4)
    cat(color_fn(vertical), " ", line, strrep(" ", padding), " ", color_fn(vertical), "\n", sep = "")
  }
  
  # 底部边框
  bottom_line <- paste0(corner_bl, strrep(border_char, width - 2), corner_br)
  cat(color_fn(bottom_line), "\n")
}

#' 打印美化的标题
print_header <- function(text, emoji = "🎯", color = "cyan") {
  color_fn <- switch(color,
                     "cyan" = cyan$bold,
                     "green" = green$bold,
                     "yellow" = yellow$bold,
                     "blue" = blue$bold,
                     "magenta" = magenta$bold,
                     cyan$bold)
  
  cat("\n")
  tryCatch({
    cli_rule(left = paste(emoji, color_fn(text)), col = color)
  }, error = function(e) {
    cli_rule(left = paste(emoji, color_fn(text)))
  })
  cat("\n")
}

#' 打印流式内容的标题
print_stream_title <- function(text, emoji = "💬", width = 70) {
  cat("\n")
  cat(cyan(paste0("┌", strrep("─", width - 2), "┐")), "\n")
  title_text <- paste(emoji, bold(text))
  text_len <- nchar(text, type = "width") + 4 
  padding <- max(0, width - text_len - 2)
  cat(cyan("│"), title_text, strrep(" ", padding), cyan("│"), "\n", sep = " ")
  cat(cyan(paste0("└", strrep("─", width - 2), "┘")), "\n")
  cat("\n")
}


# --- 4. 核心函数：与模型进行交互 ---

chat_openai_compatible <- function(base_url,
                                   user_content,
                                   system_prompt = NULL, # 新增 system_prompt 参数
                                   api_key = "sk-x",
                                   model_name,
                                   echo = c("stream", "all", "output", "none"),
                                   stream = TRUE,
                                   show_reasoning = TRUE) {
  
  echo <- match.arg(echo)
  if (echo == "stream") stream <- TRUE
  
  headers <- add_headers(
    `Content-Type` = "application/json",
    `Authorization` = paste("Bearer", api_key)
  )
  
  # --- 构建消息列表 (新增逻辑) ---
  messages_list <- list()
  
  # 1. 如果有 System Prompt，先添加
  if (!is.null(system_prompt) && nchar(system_prompt) > 0) {
    messages_list[[length(messages_list) + 1]] <- list(role = "system", content = system_prompt)
  }
  
  # 2. 添加用户消息
  messages_list[[length(messages_list) + 1]] <- list(role = "user", content = user_content)
  
  body_list <- list(
    model = model_name,
    messages = messages_list,
    stream = stream
  )
  
  # 非流式模式
  if (!stream) {
    cli_process_start("正在发送请求到 {.url {base_url}}")
    response <- httr::POST(
      url = base_url,
      config = headers,
      body = body_list,
      encode = "json"
    )
    stop_for_status(response, task = "查询 API")
    cli_process_done()
    cli_alert_success("请求成功！")
    
    parsed_response <- content(response, as = "parsed")
    
    if (echo == "output") {
      cat(parsed_response$choices[[1]]$message$content, "\n")
    } else if (echo == "all") {
      print_header("用户问题", "❓", "blue")
      cat(user_content, "\n")
      
      if (!is.null(parsed_response$choices[[1]]$message$reasoning_content)) {
        print_header("推理过程", "💭", "yellow")
        cat(parsed_response$choices[[1]]$message$reasoning_content, "\n")
      }
      
      print_header("AI 回答", "💬", "green")
      cat(parsed_response$choices[[1]]$message$content, "\n")
    }
    return(invisible(parsed_response))
  }
  
  # --- 流式处理 ---
  cli_process_start("正在建立流式连接到 {.url {base_url}}")
  
  full_reasoning <- ""
  full_content <- ""
  in_reasoning_phase <- FALSE
  in_content_phase <- FALSE
  
  if (echo == "stream") {
    print_header("用户问题", "❓", "blue")
    print_box(user_content, border_color = "blue", width = 75)
  }
  
  stream_callback <- function(chunk) {
    text <- rawToChar(chunk)
    lines <- strsplit(text, "\n")[[1]]
    
    for (line in lines) {
      if (!startsWith(line, "data: ")) next
      json_str <- sub("^data: ", "", line)
      if (json_str == "[DONE]") {
        if (echo == "stream") cat("\n")
        return(TRUE)
      }
      
      tryCatch({
        delta <- fromJSON(json_str, simplifyVector = FALSE)
        if (!is.null(delta$choices) && length(delta$choices) > 0) {
          choice <- delta$choices[[1]]
          
          # 推理内容
          if (show_reasoning && !is.null(choice$delta$reasoning_content)) {
            reasoning_chunk <- choice$delta$reasoning_content
            full_reasoning <<- paste0(full_reasoning, reasoning_chunk)
            
            if (!in_reasoning_phase && echo == "stream") {
              cli_process_done() 
              print_stream_title("推理过程", "💭", 70)
              in_reasoning_phase <<- TRUE
            }
            if (echo == "stream") cat(yellow(reasoning_chunk))
          }
          
          # 回答内容
          if (!is.null(choice$delta$content)) {
            content_chunk <- choice$delta$content
            full_content <<- paste0(full_content, content_chunk)
            
            if (!in_content_phase && echo == "stream") {
              if (!in_reasoning_phase) cli_process_done()
              if (in_reasoning_phase) cat("\n\n")
              print_stream_title("AI 回答", "🤖", 70)
              in_content_phase <<- TRUE
            }
            if (echo == "stream") cat(green(content_chunk))
          }
          flush.console()
        }
      }, error = function(e) {})
    }
    return(TRUE)
  }
  
  response <- httr::POST(
    url = base_url,
    config = headers,
    body = body_list,
    encode = "json",
    httr::write_stream(stream_callback)
  )
  
  stop_for_status(response, task = "查询流式 API")
  
  result <- list(
    choices = list(list(message = list(
      reasoning_content = full_reasoning,
      content = full_content
    )))
  )
  
  if (echo == "output") {
    print_header("AI 回答", "💬", "green")
    cat(full_content, "\n")
  } else if (echo == "all") {
    print_header("用户问题", "❓", "blue")
    cat(user_content, "\n")
    if (nchar(full_reasoning) > 0) {
      print_header("推理过程", "💭", "yellow")
      cat(full_reasoning, "\n")
    }
    print_header("AI 回答", "💬", "green")
    cat(full_content, "\n")
  }
  
  cat("\n")
  cli_alert_success("{green('✓')} 响应完成！")
  return(invisible(result))
}


# --- 5. 主程序执行逻辑 ---

main <- function() {
  # 欢迎横幅
  cat("\n")
  cat(cyan$bold(strrep("═", 80)), "\n")
  cat(cyan$bold("    🤖 Starlight LLM 聊天客户端"), yellow$bold(" v1.1"), "\n")
  cat(cyan$bold(strrep("═", 80)), "\n")
  cat("\n")
  
  # 加载配置
  cli_process_start("📁 加载配置文件 {.file .env}")
  if (!file.exists(".env")) {
    cli_process_failed()
    cli_abort(c(
      "x" = "配置文件 {.file .env} 未找到",
      "i" = "请创建 {.file .env} 文件来配置 API 提供商"
    ))
  }
  config <- yaml::read_yaml(".env")
  cli_process_done()
  
  # 确定服务商
  if (is.null(args$provider)) {
    provider <- sample(names(config), 1)
    cli_alert_info("🎲 随机选择服务商: {.strong {cyan(provider)}}")
  } else if (args$provider %in% names(config)) {
    provider <- args$provider
    cli_alert_info("🎯 使用指定服务商: {.strong {cyan(provider)}}")
  } else {
    cli_abort("❌ 提供商 {.strong {args$provider}} 在配置中未定义")
  }
  
  provider_config <- config[[provider]]
  
  # 确定模型
  if (is.null(args$model)) {
    model <- sample(provider_config$model, 1)
    cli_alert_info("🎲 随机选择模型: {.strong {magenta(model)}}")
  } else {
    model <- args$model
    cli_alert_info("🎯 使用指定模型: {.strong {magenta(model)}}")
  }
  
  # 处理 System Prompt 显示文本 (防止过长)
  sys_prompt_display <- args$system
  if (nchar(sys_prompt_display) > 50) {
    sys_prompt_display <- paste0(substr(sys_prompt_display, 1, 47), "...")
  }
  
  # 配置摘要
  cat("\n")
  cli_h2("📋 配置摘要")
  cat(blue("  ├─ 服务商: "), cyan$bold(provider), "\n", sep = "")
  cat(blue("  ├─ 模型:   "), magenta$bold(model), "\n", sep = "")
  cat(blue("  ├─ API:    "), silver(provider_config$baseurl), "\n", sep = "")
  cat(blue("  ├─ System: "), silver$italic(sys_prompt_display), "\n", sep = "") # 显示 System Prompt
  cat(blue("  └─ 推理:   "), 
      if(args$show_reasoning) green("✓ 显示") else red("✗ 隐藏"), 
      "\n", sep = "")
  
  # 准备问题
  user_content <- args$question
  
  # 检查是否指定了文本文件参数 (!is.null)
  if (!is.null(args$use_text)) {
    cli_process_start(paste0("📖 正在加载上下文文件 {.file ", basename(args$use_text), "}"))
    
    if (file.exists(args$use_text)) {
      # 1. 读取文件
      # warn=FALSE 防止文件最后一行没有换行符时报警告
      readme_content <- paste(readLines(args$use_text, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
      
      # 2. 拼接 Prompt
      user_content <- paste(
        "# 参考文档/上下文\n",
        readme_content,
        "\n\n# 用户问题\n",
        args$question,
        sep = ""
      )
      cli_process_done()
      cli_alert_success("已成功加载上下文文件！")
      
    } else {
      # 3. 文件不存在时的处理
      cli_process_failed()
      cli_alert_warning(paste0("⚠️  文件 {.file ", basename(args$use_text), "} 未找到，将忽略上下文，仅提交问题。"))
    }
  }
  
  # 开始对话
  cat("\n")
  tryCatch({
    cli_rule(left = cyan$bold("🚀 开始对话"), col = "cyan")
  }, error = function(e){
    cli_rule(left = cyan$bold("🚀 开始对话"))
  })
  cat("\n")
  
  tryCatch({
    chat_openai_compatible(
      base_url = provider_config$baseurl,
      user_content = user_content,
      system_prompt = args$system,    # 传入 System Prompt
      api_key = provider_config$api_key,
      model_name = model,
      echo = "stream",
      stream = TRUE,
      show_reasoning = args$show_reasoning
    )
  }, error = function(e) {
    cat("\n")
    tryCatch({
      cli_rule(left = red$bold("❌ 发生错误"), col = "red")
    }, error = function(e){
      cli_rule(left = red$bold("❌ 发生错误"))
    })
    cat("\n")
    cat(red("  ✖ 错误信息: "), conditionMessage(e), "\n", sep = "")
    cat(silver("  ℹ 请检查网络连接和API配置\n"))
  })
  
  # 结束
  cat("\n")
  tryCatch({
    cli_rule(left = cyan$bold("✨ 对话结束"), col = "cyan")
  }, error = function(e){
    cli_rule(left = cyan$bold("✨ 对话结束"))
  })
  cat(silver("  感谢使用 Starlight LLM 聊天客户端！\n"))
  cat("\n")
}

# --- 6. 运行主函数 ---
if (sys.nframe() == 0) {
  main()
}