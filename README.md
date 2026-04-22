# LlamaQuest
Small test of integrating an LLM with Godot

## Part 1 - Early Prototype Setup
We use ollama for this because it's fast and easy to get working.

### Model Notes
Currently using Qwen3.5:2b, this gives good results and can in < 4GB (more like 2 with draconian context settings).
* We choose a small version because we want to be as compatible as possible with modest systems.
* This version of Qwen did better than Gemma4:e5b and several other models. 
* The 2b version of Gemma did not give good results for dialogue.
* The 2b version of Qwen sometimes gets stuck in an endless cycle of thinking.  Set nothink to false.  This vastly speeds up responses, appears to completely remove the endless loops, and the model still produces good results.
* Qwen3.5:2b is generally responding in about 1 second, though it varies.  Need to test more thoroughly.  If you are struggling with performance, there are probably several optimization steps you've missed.

* Hint 1: /set nothink false
* Hint 2: 4096 or less context memory
* Hint 3: make sure you're using a reasonably quantized file


## Part 2 - Middle Prototype Setup
Switch from ollama to llama-server and llama.cpp.

### Notes
Vulkan is surprisingly becoming competitive with CUDA, and is easier to install and just have it work (for most users).
CUDA is still faster in some areas, so there's an argument to using it for dev.

Step 1: Directory Setup & Asset Placement
1. Before writing any code, organize files.
2. Create a bin/ directory in the Godot project directory. This is where the llama-server executable goes.
3. Put the qwen3.5-2b-q4_k_m.gguf model file the models/ directory.

Step 2: Procuring the Executable
1. Download the pre-compiled llama-server binary for your target operating system (e.g., Windows, macOS, or Linux).
2. Place this executable into the bin/ directory. No installation process required.

Step 3: Updating LlmManager.gd Lifecycle Methods
1. The LlmManager autoload acts as the transport pipe, but it now also needs to manage the background server's lifecycle.

Booting: 
1. Update the _ready() function to use Godot's built-in OS.create_process() to silently launch the llama-server executable in the background when the game starts. 
2. Pass arguments to this process pointing it to the .gguf file and setting the 4096 context window.
3. Shutting Down: Update the _exit_tree() function to use OS.kill() so the server properly shuts down when the player quits.

Step 4: Adjusting the API Payload
1. llama-server wraps the core engine in a standard REST API compatible with OpenAI's format, we need to tweak how Godot talks to it.
2. Update the HTTPRequest target URL from Ollama's default http://localhost:11434/api/generate endpoint to the port llama-server uses.
3. Make minor adjustments to the JSON payload inside the query_llm() function to match the OpenAI-style format expected by the new server.

Step 5: The Final Smoke Test
1. With everything setup, run the existing test scene. If the Chat and Work buttons successfully generate dialogue and quests without Ollama running in the background, the migration is complete!


