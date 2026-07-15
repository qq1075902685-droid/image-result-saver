# Image Result Saver

Codex skill that saves generated image results from the current Codex rollout JSONL.

It is designed as a companion workflow for tasks that use `image_gen` or the system `imagegen` skill. After image generation or image editing completes, it extracts the latest `image_generation_call.result`, decodes Base64 PNG data, saves the image into the current project's `outputs` directory, and verifies:

- PNG signature
- IHDR width and height
- local PNG readability
- file size
- SHA256

## Quick Install

### Windows PowerShell

```powershell
$skills = if ($env:CODEX_HOME) { Join-Path $env:CODEX_HOME "skills" } else { Join-Path $HOME ".codex\skills" }
New-Item -ItemType Directory -Force -Path $skills | Out-Null
git clone https://github.com/qq1075902685-droid/image-result-saver.git (Join-Path $skills "image-result-saver")
```

### macOS / Linux

```bash
skills="${CODEX_HOME:-$HOME/.codex}/skills"
mkdir -p "$skills"
git clone https://github.com/qq1075902685-droid/image-result-saver.git "$skills/image-result-saver"
```

Restart Codex or open a new task after installing so the skill metadata is loaded.

## When It Triggers

The skill is meant to trigger for text-to-image, image-to-image, uploaded-image edits, reference-image edits, product images, ecommerce visuals, posters, lifestyle scenes, background replacement, object removal or addition, style transfer, retouching, upscaling, redraws, and variations.

It also tells Codex to treat this skill as the required post-processing step whenever `image_gen` or `imagegen` is used.

## Usage

Normally, just ask Codex for an image or image edit. You do not need to mention the skill explicitly after it is installed.

If you want to force it manually:

```text
Use $image-result-saver after generating this image.
```

Expected final response format:

```markdown
Saved path: C:\path\to\project\outputs\generated-image.png

![generated image](C:\path\to\project\outputs\generated-image.png)
```

## Manual Script Run

From a Codex project directory:

```bash
python <skill_dir>/scripts/save_latest_image_result.py --cwd . --prefix generated-image
```

The script prints JSON with the saved file path and validation metadata.

## Notes

- This only works when the Codex environment exposes a current rollout JSONL containing `image_generation_call.result`.
- It does not use old generated files, screenshots, downloaded images, or placeholders.
- If no recoverable current-turn image result is found, Codex should say so instead of inventing a path.
