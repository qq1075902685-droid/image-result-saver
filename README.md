# Image Result Saver

这是一个 Codex skill，用来把 `image_gen` / `imagegen` 生成或编辑出来的图片，从当前 Codex 会话的 rollout JSONL 里提取出来，保存成真实的本地 PNG 文件。

它解决的核心问题是：图片已经在聊天里生成了，但用户还需要明确可用的本地文件路径，而不是只有聊天预览。

## 它会做什么

当 Codex 使用 `image_gen` 或系统 `imagegen` skill 生成、改图、图生图、换背景、做产品图、做主图、做海报、做生活方式场景图等图片任务后，本 skill 会要求 Codex 执行后处理：

- 从当前会话 rollout JSONL 中找到最新的 `image_generation_call.result`
- 提取本轮结果里的 Base64 PNG 数据
- 解码并保存到当前项目的 `outputs` 目录
- 校验 PNG 文件头
- 校验 IHDR 宽高
- 校验本地 PNG 可读性
- 输出文件大小和 SHA256
- 最终只回复保存路径和 Markdown 图片预览

它禁止把旧图、截图、下载图、缓存猜测图、占位图当成本轮结果交付。

## 快速安装

推荐方式：在 Codex 新任务里直接发送下面这段话，让 Codex 内置的 skill 安装器处理安装。

```text
Use $skill-installer to install this skill:
https://github.com/qq1075902685-droid/image-result-saver
```

安装完成后，重启 Codex 或打开一个新任务，让 skill 元数据重新加载。

## 为什么推荐用 skill-installer

`$skill-installer` 会把仓库安装到 Codex 的 skills 目录，并自动处理不同电脑上的环境差异。

有些电脑没有 `git` 命令，这时安装器可能会改用 GitHub 压缩包下载。这样安装出来的 skill 目录里没有 `.git` 元数据，这是正常现象，不影响 skill 使用。

区别只是：

- 有 `.git`：以后可以在目录里执行 `git pull` 更新
- 没有 `.git`：skill 仍然能正常使用，但更新时需要重新下载安装或让 Codex 帮你覆盖安装

## 更新到最新版

在 Codex 里发送：

```text
Use $skill-installer to update or reinstall this skill:
https://github.com/qq1075902685-droid/image-result-saver

如果本地已经安装 image-result-saver：
1. 如果目录里有 .git，请进入该目录执行 git pull。
2. 如果目录里没有 .git，说明之前可能是压缩包安装，请重新下载最新版并覆盖安装。
3. 更新后检查 SKILL.md、agents/openai.yaml、scripts/save_latest_image_result.py 是否存在。
4. 提醒我重启 Codex 或打开新任务。
```

## 触发范围

这个 skill 设计成 `image_gen` / `imagegen` 的伴随交付流程。以下任务都应该触发：

- 文生图
- 图生图
- 改图、修图、重绘、变体
- 上传图片编辑
- 参考图编辑
- 产品主图、电商图、海报图
- 生活方式场景图
- 换背景
- 去除或添加物体
- 风格迁移
- 精修、放大
- “把这张改成……”
- “保持产品不变，但是……”
- “参考这张做成……”

安装后，通常不需要手动提到 skill。你只要正常让 Codex 生成图片或修改图片即可。

如果想强制提醒 Codex 使用它，可以这样说：

```text
生成图片后，请使用 $image-result-saver 保存本轮结果到 outputs，并只回复保存路径和 Markdown 预览。
```

## 预期最终回复

单张图片：

```markdown
保存路径：C:\path\to\project\outputs\generated-image.png

![generated image](C:\path\to\project\outputs\generated-image.png)
```

多张图片时，重复输出每张图的保存路径和预览即可。

## 手动运行脚本

一般不需要手动运行。只有在调试时，才需要从当前 Codex 项目目录运行：

```bash
python <skill_dir>/scripts/save_latest_image_result.py --cwd . --prefix generated-image
```

脚本会输出 JSON，里面包含保存路径、PNG 校验结果、宽高、文件大小和 SHA256。

## 注意事项

- 这个 skill 依赖 Codex 当前会话的 rollout JSONL。
- 如果当前环境没有暴露 `image_generation_call.result`，就无法恢复本轮图片文件。
- 如果找不到本轮 Base64 PNG 结果，Codex 应该明确说明无法保存，而不是编造路径。
- 安装或更新后，建议重启 Codex 或打开一个新任务，让 skill 元数据重新加载。
