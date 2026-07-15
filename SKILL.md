---
name: image-result-saver
description: Companion delivery workflow for any task that uses, may use, or has just used the built-in image_gen tool or system imagegen skill. Use whenever Codex generates, edits, transforms, or outputs an image, including text-to-image, image-to-image, reference-image edits, uploaded-image edits, product main images, ecommerce visuals, posters, lifestyle scenes, redraws, variations, background replacement, object removal/addition, style transfer, retouching, upscaling, or requests phrased as "change this image", "make it look like", "keep the product but", "replace the background", or similar. After image_gen/imagegen completes, extract the latest current-turn image_generation_call.result from the Codex rollout JSONL, decode Base64 PNG data, save it to the current project's outputs directory, verify PNG signature, IHDR dimensions, local readability, file size, and SHA256, and reply only with the saved path and Markdown image preview.
---

# Image Result Saver

## Required Behavior

When the user asks for image generation or image editing output, or when the task triggers `image_gen` / `imagegen` for any reason, produce a real saved file, not only a chat preview.

1. Use the built-in `image_gen` tool or the system `imagegen` skill first when available.
2. After image generation completes, run `scripts/save_latest_image_result.py` from this skill.
3. Save decoded PNG files into the current project's `outputs` directory unless the user explicitly requested another output directory.
4. Verify every saved file:
   - PNG signature
   - IHDR width and height
   - local PNG chunk readability
   - file size
   - SHA256
5. Final reply must contain only:
   - the saved path for each image
   - a Markdown image preview for each image

Do not use old images, screenshots, downloaded images, placeholders, cache guesses, or any file that is not decoded from this turn's latest `image_generation_call.result`.

Treat this skill as the required post-processing step for `image_gen` and `imagegen`. If another image skill is selected first, still run this skill's script after the image tool finishes whenever a local saved PNG is expected or useful.

## Script Usage

From the current project directory, run:

```bash
python <skill_dir>/scripts/save_latest_image_result.py --cwd . --prefix generated-image
```

Use a descriptive `--prefix` when the user requested a specific subject, for example:

```bash
python <skill_dir>/scripts/save_latest_image_result.py --cwd . --prefix tv-stand-scene
```

The script prints JSON containing saved paths and validation metadata. Use only paths reported by the script.

If the script reports that it cannot find the rollout JSONL or cannot find a PNG result, say plainly that the current environment did not expose a recoverable image result. Do not invent a path.

## Final Response Format

For one image:

```markdown
Saved path: C:\path\to\project\outputs\generated-image-1.png

![generated image](C:\path\to\project\outputs\generated-image-1.png)
```

For multiple images, repeat the two lines for each file. Do not include validation logs in the final response unless the user asks for them.
