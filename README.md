# AI Empire · Krea 2 NSFW pod

RunPod image: **`ghcr.io/justlinuxnoob/krea2-nsfw:latest`**

ComfyUI + JupyterLab with Krea 2 Turbo. Models download on first boot (to `/workspace` if a volume is attached).

## LoRAs (and the strength to use in the workflow)

| LoRA | Strength |
|---|---|
| `skindetails_krea2_loraholic` | 0.5 |
| `RawGirlV2_epoch_10` | 0.7–0.8 |
| `Krea2_TextFusion_Refusal_Reduction` | 1.0 |

No Civitai or Hugging Face token needed.

## Changing what downloads

Edit `start.sh` → push to `main` → GitHub Actions rebuilds the image in about 2 minutes
(it stacks `start.sh` on top of the base image, nothing heavy gets rebuilt).
