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
        
        # Install requirements for each custom node
        echo "Installing custom node dependencies..."
        for node_dir in /workspace/ComfyUI/custom_nodes/*/; do
            if [ -d "$node_dir" ]; then
                node_name=$(basename "$node_dir")
                echo "Checking dependencies for: $node_name"
                
                # Check for requirements.txt
                if [ -f "$node_dir/requirements.txt" ]; then
                    echo "Installing requirements for $node_name..."
                    cd /workspace/ComfyUI
                    . /workspace/ComfyUI/venv/bin/activate
                    pip install -r "$node_dir/requirements.txt" --no-cache-dir || echo "Failed to install some requirements for $node_name"
                fi
                
                # Check for install.py
                if [ -f "$node_dir/install.py" ]; then
                    echo "Running install.py for $node_name..."
                    cd "$node_dir"
                    . /workspace/ComfyUI/venv/bin/activate
                    python install.py || echo "Failed to run install.py for $node_name"
                fi
            fi
        done
        
        # Install common missing dependencies that custom nodes often need
        echo "Installing common dependencies for custom nodes..."
        cd /workspace/ComfyUI
        . /workspace/ComfyUI/venv/bin/activate
        pip install --no-cache-dir \
            google-generativeai \
            ollama \
            opencv-python \
            opencv-contrib-python \
            mediapipe \
            insightface \
            onnxruntime \
            segment-anything \
            groundingdino-py \
            sam2 \
            ultralytics \
        || echo "Some common dependencies failed to install"
        
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