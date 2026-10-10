#!/usr/bin/env bash
# AI Empire · Krea 2 NSFW pod — boot script (downloads models, starts JupyterLab + ComfyUI)

# Use libtcmalloc for better memory management
TCMALLOC="$(ldconfig -p | grep -Po "libtcmalloc.so.\d" | head -n 1)"
export LD_PRELOAD="${TCMALLOC}"


if ! which aria2 > /dev/null 2>&1; then
    echo "Installing aria2..."
    apt-get update && apt-get install -y aria2
else
    echo "aria2 is already installed"
fi

if ! which curl > /dev/null 2>&1; then
    echo "Installing curl..."
    apt-get update && apt-get install -y curl
else
    echo "curl is already installed"
fi

# Set the network volume path
NETWORK_VOLUME="/workspace"
URL="http://127.0.0.1:8188"

# Check if NETWORK_VOLUME exists; if not, use root directory instead
if [ ! -d "$NETWORK_VOLUME" ]; then
    echo "NETWORK_VOLUME directory '$NETWORK_VOLUME' does not exist. You are NOT using a network volume. Setting NETWORK_VOLUME to '/' (root directory)."
    NETWORK_VOLUME="/"
    echo "NETWORK_VOLUME directory doesn't exist. Starting JupyterLab on root directory..."
    jupyter-lab --ip=0.0.0.0 --allow-root --no-browser --NotebookApp.token='' --NotebookApp.password='' --ServerApp.allow_origin='*' --ServerApp.allow_credentials=True --notebook-dir=/ &
else
    echo "NETWORK_VOLUME directory exists. Starting JupyterLab..."
    jupyter-lab --ip=0.0.0.0 --allow-root --no-browser --NotebookApp.token='' --NotebookApp.password='' --ServerApp.allow_origin='*' --ServerApp.allow_credentials=True --notebook-dir=/workspace &
fi

COMFYUI_DIR="$NETWORK_VOLUME/ComfyUI"
WORKFLOW_DIR="$NETWORK_VOLUME/ComfyUI/user/default/workflows"

# Set the target directory
CUSTOM_NODES_DIR="$NETWORK_VOLUME/ComfyUI/custom_nodes"

if [ ! -d "$COMFYUI_DIR" ]; then
    mv /ComfyUI "$COMFYUI_DIR"
else
    echo "Directory already exists, skipping move."
fi

pip install onnxruntime-gpu &


export change_preview_method="true"


# Change to the directory
cd "$CUSTOM_NODES_DIR" || exit 1

# Function to download a model using aria2
# A .safetensors file is complete when its header's last tensor ends exactly at the end of the file.
# Catches half-finished downloads/uploads that the size check misses (they break the LoRA loader with
# "incomplete metadata, file not fully covered").
safetensors_ok() {
    python3 - "$1" <<'PY'
import json, os, struct, sys
p = sys.argv[1]
try:
    with open(p, "rb") as f:
        n = struct.unpack("<Q", f.read(8))[0]
        header = json.loads(f.read(n))
    end = max([v["data_offsets"][1] for k, v in header.items() if k != "__metadata__"] or [0])
    sys.exit(0 if os.path.getsize(p) == 8 + n + end else 1)
except Exception:
    sys.exit(1)
PY
}

download_model() {
    local url="$1"
    local full_path="$2"

    local destination_dir=$(dirname "$full_path")
    local destination_file=$(basename "$full_path")

    mkdir -p "$destination_dir"

    # Half-downloaded .safetensors (e.g. pod stopped mid-download on a network volume) -> fetch again
    if [ -f "$full_path" ] && [ ! -f "${full_path}.aria2" ] && [[ "$full_path" == *.safetensors ]] && ! safetensors_ok "$full_path"; then
        echo "🗑️  Incomplete file, downloading again: $full_path"
        rm -f "$full_path"
    fi

    # Simple corruption check: file < 10MB or .aria2 files
    if [ -f "$full_path" ]; then
        local size_bytes=$(stat -f%z "$full_path" 2>/dev/null || stat -c%s "$full_path" 2>/dev/null || echo 0)
        local size_mb=$((size_bytes / 1024 / 1024))

        if [ "$size_bytes" -lt 10485760 ]; then  # Less than 10MB
            echo "🗑️  Deleting corrupted file (${size_mb}MB < 10MB): $full_path"
            rm -f "$full_path"
        else
            echo "✅ $destination_file already exists (${size_mb}MB), skipping download."
            return 0
        fi
    fi

    # Check for and remove .aria2 control files
    if [ -f "${full_path}.aria2" ]; then
        echo "🗑️  Deleting .aria2 control file: ${full_path}.aria2"
        rm -f "${full_path}.aria2"
        rm -f "$full_path"  # Also remove any partial file
    fi

    echo "📥 Downloading $destination_file to $destination_dir..."

    # Download without falloc (since it's not supported in your environment)
    aria2c -x 16 -s 16 -k 1M --continue=true -d "$destination_dir" -o "$destination_file" "$url" &

    echo "Download started in background for $destination_file"
}

# Define base paths (Ensure $NETWORK_VOLUME is set in your environment)
DIFFUSION_MODELS_DIR="$NETWORK_VOLUME/ComfyUI/models/diffusion_models"
UNET_DIR="$NETWORK_VOLUME/ComfyUI/models/unet"
TEXT_ENCODERS_DIR="$NETWORK_VOLUME/ComfyUI/models/text_encoders"
CLIP_DIR="$NETWORK_VOLUME/ComfyUI/models/clip"
VAE_DIR="$NETWORK_VOLUME/ComfyUI/models/vae"
LORAS_DIR="$NETWORK_VOLUME/ComfyUI/models/loras"
CHECKPOINTS_DIR="$NETWORK_VOLUME/ComfyUI/models/checkpoints"
UPSCALE_DIR="$NETWORK_VOLUME/ComfyUI/models/upscale_models"
LATENT_UPSCALE_DIR="$NETWORK_VOLUME/ComfyUI/models/latent_upscale_models"
SAMS_DIR="$NETWORK_VOLUME/ComfyUI/models/sams"
ULTRALYTICS_BBOX_DIR="$NETWORK_VOLUME/ComfyUI/models/ultralytics/bbox"
HUMANPARTS_DIR="$NETWORK_VOLUME/ComfyUI/models/onnx/human-parts"

echo "📦 Starting model downloads..."

# ------------------------------------------------------------
# Core models — Krea 2 Turbo diffusion model + encoders
# ------------------------------------------------------------
# Main diffusion model (UNETLoader)
download_model "https://huggingface.co/Comfy-Org/Krea-2/resolve/main/diffusion_models/krea2_turbo_fp8_scaled.safetensors" "$DIFFUSION_MODELS_DIR/krea2_turbo_fp8_scaled.safetensors"

# INT8 ConvRot build of the same Turbo model, for OTUNetLoaderW8A8 (ComfyUI-INT8-Fast).
# That node lists from folder_paths "diffusion_models", so it sits next to the fp8 file.
# Renamed on download: the "Beyond Reality V2.1 fix" workflow hardcodes the lowercase
# krea2_turbo_int8_convrot.safetensors, and ComfyUI matches the widget string literally.
# 14.1GB — roughly 1.4x the fp8 file, both are kept so either loader path works.
download_model "https://huggingface.co/lilcheaty/Krea2-INT8-ConvRot/resolve/main/Krea2-Turbo-int8-ConvRot.safetensors" "$DIFFUSION_MODELS_DIR/krea2_turbo_int8_convrot.safetensors"

# Qwen3-VL text encoder (CLIPLoader, krea2 type) — not in dci05049/krea2
download_model "https://huggingface.co/Comfy-Org/Qwen3-VL/resolve/b58e627c376915e49cb6bba978416085aa31767f/text_encoders/qwen3vl_4b_bf16.safetensors" "$CLIP_DIR/qwen3vl_4b_bf16.safetensors"

# fp8_scaled variant of the same encoder (5.2GB vs 8.9GB). Kept alongside bf16
# rather than replacing it: the LoRA-comparison workflows reference the fp8 name
# explicitly, while existing saved workflows on the network volume still point at
# bf16, and ComfyUI matches the CLIPLoader widget string literally.
download_model "https://huggingface.co/Comfy-Org/Qwen3-VL/resolve/b58e627c376915e49cb6bba978416085aa31767f/text_encoders/qwen3vl_4b_fp8_scaled.safetensors" "$CLIP_DIR/qwen3vl_4b_fp8_scaled.safetensors"

# Wan 2.1 VAE (VAELoader) — not in dci05049/krea2
download_model "https://huggingface.co/dci05049/wan-animate/resolve/main/wan_2.1_vae.safetensors" "$VAE_DIR/wan_2.1_vae.safetensors"

# ------------------------------------------------------------
# Detailer / detector / post-process models
# ------------------------------------------------------------
# Eye bbox detector (AiorbustEyeBBoxDetectorProvider -> "bbox/...")
download_model "https://huggingface.co/dci05049/krea2/resolve/main/Eyeful_v2-Individual.pt" "$ULTRALYTICS_BBOX_DIR/Eyeful_v2-Individual.pt"
download_model "https://huggingface.co/dci05049/krea2/resolve/main/Eyeful_v2-Paired.pt" "$ULTRALYTICS_BBOX_DIR/Eyeful_v2-Paired.pt"

# Human parts segmentation (LayerMask: HumanPartsUltra)
download_model "https://huggingface.co/dci05049/krea2/resolve/main/deeplabv3p-resnet50-human.onnx" "$HUMANPARTS_DIR/deeplabv3p-resnet50-human.onnx"

# Skin-detail upscale model (CRT Post-Process Suite)
download_model "https://huggingface.co/dci05049/krea2/resolve/main/1x-ITF-SkinDiffDetail-Lite-v1.pth" "$UPSCALE_DIR/1x-ITF-SkinDiffDetail-Lite-v1.pth"

# SAM model (SAMLoader, eye detailer) — public Meta weights, not in dci05049/krea2
download_model "https://dl.fbaipublicfiles.com/segment_anything/sam_vit_b_01ec64.pth" "$SAMS_DIR/sam_vit_b_01ec64.pth"

# ------------------------------------------------------------
# LoRAs — only these three (strengths are set in the workflow):
#   skindetails_krea2_loraholic          -> 0.5
#   RawGirlV2_epoch_10                    -> 0.7-0.8
#   Krea2_TextFusion_Refusal_Reduction    -> 1.0
# To add one: copy a download_model line below. No Civitai/Hugging Face token needed.
# ------------------------------------------------------------
download_model "https://huggingface.co/dci05049/krea2/resolve/main/skindetails_krea2_loraholic.safetensors" "$LORAS_DIR/skindetails_krea2_loraholic.safetensors"
download_model "https://huggingface.co/dci05049/krea2/resolve/main/RawGirlV2_epoch_10.safetensors" "$LORAS_DIR/RawGirlV2_epoch_10.safetensors"
download_model "https://huggingface.co/dci05049/krea2/resolve/main/Krea2_TextFusion_Refusal_Reduction.safetensors" "$LORAS_DIR/Krea2_TextFusion_Refusal_Reduction.safetensors"


# Keep checking until no aria2c processes are running
while pgrep -x "aria2c" > /dev/null; do
    echo "Models are downloading (In Progress)"
    sleep 5  # Check every 5 seconds
done

echo "All models downloaded successfully"

# Any incomplete LoRA left (your own uploads too)? Say so loudly instead of failing later in ComfyUI.
for f in "$LORAS_DIR"/*.safetensors; do
    [ -f "$f" ] || continue
    if ! safetensors_ok "$f"; then
        echo "⚠️  INCOMPLETE LoRA: $f  -> delete it and upload/download it again (it will fail in the LoRA loader)"
    fi
done

# Ensure the file exists in the current directory before moving it
cd /

if [ "$change_preview_method" == "true" ]; then
    echo "Updating default preview method..."
    CONFIG_PATH="/ComfyUI/user/default/ComfyUI-Manager"
    CONFIG_FILE="$CONFIG_PATH/config.ini"

# Ensure the directory exists
mkdir -p "$CONFIG_PATH"

# Create the config file if it doesn't exist
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Creating config.ini..."
    cat <<EOL > "$CONFIG_FILE"
[default]
preview_method = auto
git_exe =
use_uv = False
channel_url = https://raw.githubusercontent.com/ltdrdata/ComfyUI-Manager/main
share_option = all
bypass_ssl = False
file_logging = True
component_policy = workflow
update_policy = stable-comfyui
windows_selector_event_loop_policy = False
model_download_by_agent = False
downgrade_blacklist =
security_level = normal
skip_migration_check = False
always_lazy_install = False
network_mode = public
db_mode = cache
EOL
else
    echo "config.ini already exists. Updating preview_method..."
    sed -i 's/^preview_method = .*/preview_method = auto/' "$CONFIG_FILE"
fi
echo "Config file setup complete!"
    echo "Default preview method updated to 'auto'"
else
    echo "Skipping preview method update (change_preview_method is not 'true')."
fi

# Workspace as main working directory
echo "cd $NETWORK_VOLUME" >> ~/.bashrc

echo "Renaming loras downloaded as zip files to safetensors files"
mkdir -p "$LORAS_DIR"
cd "$LORAS_DIR"
for file in *.zip; do
    [ -f "$file" ] || continue
    mv "$file" "${file%.zip}.safetensors"
done

# Start ComfyUI
echo "Starting ComfyUI"

# Reduce VRAM fragmentation OOMs: use PyTorch's native allocator with
# expandable segments (defrags on the fly) instead of ComfyUI's default
# cudaMallocAsync backend, which strands reserved-but-unusable VRAM under
# the SPEED HD sampler's progressive-resolution passes.
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True

nohup python3 "$NETWORK_VOLUME/ComfyUI/main.py" --listen --disable-smart-memory --disable-cuda-malloc > "$NETWORK_VOLUME/comfyui_${RUNPOD_POD_ID}_nohup.log" 2>&1 &

    # Counter for timeout
    counter=0
    max_wait=45

    until curl --silent --fail "$URL" --output /dev/null; do
        if [ $counter -ge $max_wait ]; then
            echo "ComfyUI should be running if not check the log at $NETWORK_VOLUME/comfyui_${RUNPOD_POD_ID}_nohup.log"
            break
        fi

        echo "🔄  ComfyUI Starting Up... You can view the startup logs here: $NETWORK_VOLUME/comfyui_${RUNPOD_POD_ID}_nohup.log"
        sleep 2
        counter=$((counter + 2))
    done

    # Only show success message if curl succeeded
    if curl --silent --fail "$URL" --output /dev/null; then
        echo "🚀 ComfyUI is UP"
    fi

    sleep infinity
