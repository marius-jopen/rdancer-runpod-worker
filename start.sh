#!/usr/bin/env bash

set -x

ensure_network_volume_mounted() {
    ln -s /runpod-volume /workspace

    while [ ! -d "/workspace/ComfyUI" ]; do
        echo "Waiting for /workspace/ComfyUI to be mounted..."
        sleep 1
    done

    echo "/workspace/ComfyUI is now available."
    ls -l /workspace
}
ensure_network_volume_mounted

# Ensure custom_nodes are available and linked properly
setup_custom_nodes() {
    echo "Setting up custom_nodes..."
    
    # Ensure the custom_nodes folder exists in workspace
    if [ ! -d "/workspace/ComfyUI/custom_nodes" ]; then
        echo "Creating custom_nodes folder..."
        mkdir -p /workspace/ComfyUI/custom_nodes
    fi
    
    # For API mode, ensure custom_nodes are available in /comfyui/
    if [ ! -L "/comfyui/custom_nodes" ] && [ ! -d "/comfyui/custom_nodes" ]; then
        echo "Linking custom_nodes to /comfyui/ for API mode..."
        ln -sf /workspace/ComfyUI/custom_nodes /comfyui/custom_nodes
    fi
    
    # Debug: Show what's in custom_nodes
    echo "Custom nodes folder contents:"
    ls -la /workspace/ComfyUI/custom_nodes/
    
    # If there are custom nodes, list them and install requirements
    if [ "$(ls -A /workspace/ComfyUI/custom_nodes/)" ]; then
        echo "Found custom nodes:"
        ls -1 /workspace/ComfyUI/custom_nodes/
        
        # Use system Python/pip directly (not virtual environment)
        echo "Installing essential dependencies for custom nodes..."
        python3 -m pip install --no-cache-dir --upgrade pip setuptools wheel
        
        # Install common missing dependencies that custom nodes often need
        echo "Installing comprehensive dependencies for custom nodes..."
        python3 -m pip install --no-cache-dir \
            google-generativeai \
            ollama \
            opencv-python \
            opencv-contrib-python \
            mediapipe \
            insightface \
            onnxruntime \
            onnxruntime-gpu \
            segment-anything \
            groundingdino-py \
            sam2 \
            ultralytics \
            controlnet-aux \
            facexlib \
            gfpgan \
            realesrgan \
            basicsr \
            scipy \
            scikit-image \
            albumentations \
            transformers \
            diffusers \
            accelerate \
            xformers \
            triton \
            kornia \
            timm \
            open-clip-torch \
            clip-by-openai \
            ftfy \
            regex \
            tqdm \
            requests \
            pillow \
            numpy \
            matplotlib \
            seaborn \
            plotly \
            gradio \
            streamlit \
            fastapi \
            uvicorn \
            websockets \
            aiohttp \
            httpx \
            beautifulsoup4 \
            lxml \
            jsonschema \
            pyyaml \
            toml \
            configparser \
            python-dotenv \
            psutil \
            gpustat \
            pynvml \
            wandb \
            tensorboard \
            mlflow \
            deepdiff \
        || echo "Some essential dependencies failed to install"
        
        # Install requirements for each custom node
        echo "Installing custom node specific dependencies..."
        for node_dir in /workspace/ComfyUI/custom_nodes/*/; do
            if [ -d "$node_dir" ]; then
                node_name=$(basename "$node_dir")
                echo "Checking dependencies for: $node_name"
                
                # Check for requirements.txt
                if [ -f "$node_dir/requirements.txt" ]; then
                    echo "Installing requirements.txt for $node_name..."
                    python3 -m pip install -r "$node_dir/requirements.txt" --no-cache-dir || echo "Failed to install some requirements for $node_name"
                fi
                
                # Check for install.py
                if [ -f "$node_dir/install.py" ]; then
                    echo "Running install.py for $node_name..."
                    cd "$node_dir"
                    python3 install.py || echo "Failed to run install.py for $node_name"
                    cd /workspace/ComfyUI
                fi
                
                # Check for pyproject.toml
                if [ -f "$node_dir/pyproject.toml" ]; then
                    echo "Installing pyproject.toml for $node_name..."
                    cd "$node_dir"
                    python3 -m pip install -e . --no-cache-dir || echo "Failed to install pyproject.toml for $node_name"
                    cd /workspace/ComfyUI
                fi
            fi
        done
        
        # Install specific packages for known problematic nodes
        echo "Installing specific fixes for common custom nodes..."
        
        # Fix for ComfyUI-Crystools
        python3 -m pip install --no-cache-dir crystools || echo "Failed to install crystools"
        
        # Fix for Impact Pack
        python3 -m pip install --no-cache-dir segment-anything-hq || echo "Failed to install segment-anything-hq"
        
        # Fix for Advanced ControlNet
        python3 -m pip install --no-cache-dir controlnet-aux || echo "Failed to install controlnet-aux"
        
        # Fix for various nodes requiring specific versions
        python3 -m pip install --no-cache-dir \
            "numpy>=1.21.0" \
            "opencv-python>=4.5.0" \
            "pillow>=8.0.0" \
        || echo "Failed to install specific version requirements"
        
        echo "Custom node dependency installation complete!"
        
    else
        echo "No custom nodes found in /workspace/ComfyUI/custom_nodes/"
    fi
}
setup_custom_nodes

# Use libtcmalloc for better memory management
TCMALLOC="$(ldconfig -p | grep -Po "libtcmalloc.so.\d" | head -n 1)"
export LD_PRELOAD="${TCMALLOC}"

# Serve the API and don't shutdown the container
if [ "$SERVE_API_LOCALLY" == "true" ]; then
    echo "runpod-worker-comfy: Starting ComfyUI in API mode"
    echo "Custom nodes will be loaded from: /comfyui/custom_nodes -> /workspace/ComfyUI/custom_nodes"
    python3 /comfyui/main.py --disable-auto-launch --disable-metadata --listen &

    echo "runpod-worker-comfy: Starting RunPod Handler"
    python3 -u /rp_handler.py --rp_serve_api --rp_api_host=0.0.0.0
else
    echo "runpod-worker-comfy: Starting ComfyUI in normal mode"
    echo "Custom nodes will be loaded from: /workspace/ComfyUI/custom_nodes"
    (
        cd /workspace/ComfyUI
        . /workspace/ComfyUI/venv/bin/activate
        python3 main.py --disable-auto-launch --disable-metadata 2>&1 | tee -a /workspace/ComfyUI/logs/sls-comfyui.log &
    )

    echo "runpod-worker-comfy: Starting RunPod Handler"
    python3 -u /rp_handler.py
fi