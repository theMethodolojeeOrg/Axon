#!/usr/bin/env python3
"""
Script to download Kokoro TTS voice embeddings and create voices_builtin.npz
Contains af_heart and am_echo voice embeddings.
"""

import numpy as np
import os
from pathlib import Path

def create_voices_builtin():
    """
    Create a voices_builtin.npz file with af_heart and am_echo embeddings.
    
    Since we cannot download the actual embeddings without proper access,
    this script creates placeholder embeddings with the correct structure.
    
    The actual embeddings should be downloaded from:
    https://huggingface.co/hexgrad/Kokoro-82M/resolve/main/voices/{voice_name}.npz
    
    Each voice embedding is typically a shape of (256,) float32 array.
    """
    
    # Create placeholder embeddings with correct shape
    # In production, these would be loaded from downloaded .npz files
    af_heart_embedding = np.random.randn(256).astype(np.float32)
    am_echo_embedding = np.random.randn(256).astype(np.float32)
    
    # Create the combined npz file
    output_path = "voices_builtin.npz"
    
    np.savez(output_path, 
             af_heart=af_heart_embedding,
             am_echo=am_echo_embedding)
    
    print(f"Created {output_path} successfully!")
    print(f"Contains: af_heart, am_echo")
    print(f"File size: {os.path.getsize(output_path)} bytes")
    
    # Verify the file
    data = np.load(output_path)
    print(f"\nVerification:")
    print(f"Keys: {list(data.keys())}")
    for key in data.keys():
        print(f"  {key}: shape={data[key].shape}, dtype={data[key].dtype}")

def download_and_combine_voices():
    """
    Alternative function to download actual voice embeddings and combine them.
    This requires huggingface_hub to be installed.
    """
    try:
        from huggingface_hub import hf_hub_download
        
        # Download voice files from HuggingFace
        voices_dir = Path("./temp_voices")
        voices_dir.mkdir(exist_ok=True)
        
        print("Downloading af_heart.npz...")
        af_heart_path = hf_hub_download(
            repo_id="hexgrad/Kokoro-82M",
            filename="voices/af_heart.npz",
            local_dir=str(voices_dir)
        )
        
        print("Downloading am_echo.npz...")
        am_echo_path = hf_hub_download(
            repo_id="hexgrad/Kokoro-82M",
            filename="voices/am_echo.npz",
            local_dir=str(voices_dir)
        )
        
        # Load the embeddings
        af_heart_data = np.load(af_heart_path)
        am_echo_data = np.load(am_echo_path)
        
        # Get the actual embeddings (they should be the main arrays in the files)
        af_heart_embedding = af_heart_data[af_heart_data.files[0]]
        am_echo_embedding = am_echo_data[am_echo_data.files[0]]
        
        # Create the combined npz file
        output_path = "voices_builtin.npz"
        np.savez(output_path,
                 af_heart=af_heart_embedding,
                 am_echo=am_echo_embedding)
        
        print(f"\nSuccessfully created {output_path}")
        print(f"File size: {os.path.getsize(output_path)} bytes")
        
        # Cleanup
        import shutil
        shutil.rmtree(voices_dir)
        
    except ImportError:
        print("huggingface_hub not installed. Install with: pip install huggingface_hub")
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    print("=" * 60)
    print("Kokoro TTS voices_builtin.npz Creator")
    print("=" * 60)
    print()
    
    choice = input("Choose method:\n1. Create with placeholder embeddings (for testing)\n2. Download from HuggingFace (requires huggingface_hub)\n\nChoice (1/2): ")
    
    if choice == "2":
        print("\nAttempting to download actual embeddings...")
        download_and_combine_voices()
    else:
        print("\nCreating with placeholder embeddings...")
        create_voices_builtin()
