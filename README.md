# LlamaQuest
Small test of integrating an LLM with Godot

## Part 1 - Early Prototype Setup
We use ollama for this because it's fast and easy to get working.

### Model Notes
Currently using Qwen3.5:2b, this gives good results and can in < 4GB (more like 2 with draconian context settings).
* We choose a small version because we want to be as compatible as possible with modest systems.
* This version of Qwen did better than Gemma4:e5b and several other models. 
* The 2b version of Gemma did not give good results for dialogue.
* Qwen3.5:2b is generally responding in about 1 second, though it varies.  Need to test more thoroughly.  If you are struggling with performance, there are probably several optimization steps you've missed.

* Hint 1: /set nothink false
* Hint 2: 4096 or less context memory
* Hint 3: make sure you're using a reasonably quantized file


## Part 2 - Middle Prototype Setup
Switch from ollama to llama-server and llama.cpp.

### Notes
Vulkan is surprisingly becoming competitive with CUDA, and is easier to install and just have it work (for most users).
CUDA is still faster in some areas, so there's an argument to using it for dev.
