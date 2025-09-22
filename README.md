# 🤖 AutoCommit

AutoCommit is a command-line tool that uses the power of AI to automatically generate clear, conventional, and descriptive `git` commit messages for you. It analyzes your staged changes, understands the context, and proposes a commit message that follows the **Conventional Commits** specification.

---
## ## Features

* **🧠 AI-Generated Messages**: Leverages powerful AI models to understand your code changes and write meaningful commit messages.
* **✅ Conventional Commits**: Enforces the Conventional Commits standard out of the box for a clean and readable git history.
* **🔌 Multi-Provider Support**: Works with a wide range of AI providers, including:
    * Cloud-based services like **OpenAI**, **Mistral**, **Groq**, and **Google AI**.
    * Local inference using **Ollama**, allowing you to run powerful open-source models like Llama 3 and Gemma 2 for free.
* **👆 Interactive Menu**: Provides a simple menu to commit, regenerate, copy the message to the clipboard, or exit.
* ** smart Diff Analysis**: Automatically ignores noisy files like `package-lock.json` to improve the quality of the AI's analysis.
* **🔧 Customizable**: Power users can override the default AI instructions to tailor the commit message style to their needs.

---
## ## Prerequisites

Before you begin, ensure you have the following tools installed on your system:

* **Git**: For version control.
* **curl** or **wget**: For downloading the script.
* **jq**: For processing JSON.
* **Ollama** (Optional): Required if you want to run local AI models. You can download it from [ollama.com](https://ollama.com).

---
## ## Installation

You can install `autocommit` with a single command. Just paste this into your terminal:

### One-Line Install (Recommended)

```bash
curl -fsSL [https://raw.githubusercontent.com/Skediaio/autocommit/main/install.sh](https://raw.githubusercontent.com/Skediaio/autocommit/main/install.sh) | bash
```

### Manual Install (for inspection)

If you'd prefer to inspect the script before running it:
```bash
# 1. Download the script
curl -L -o install.sh [https://raw.githubusercontent.com/Skediaio/autocommit/main/install.sh](https://raw.githubusercontent.com/Skediaio/autocommit/main/install.sh)

# 2. Review the script (optional)
cat install.sh

# 3. Run the installer
bash install.sh
```
The installer will place the `autocommit` script in `$HOME/.local/bin` and make it executable. If this directory is not in your `PATH`, the script will provide instructions on how to add it.

---
## ## Configuration

The first time you run the tool, you'll need to configure it.

```bash
autocommit configure
```
This will launch an interactive setup guide where you can:
1.  **Choose an AI provider**: Select **Ollama** for a fast, free, and private local experience.
2.  **Select a model**: The recommended default for local use is `gemma2:9b-instruct-q4_K_M`.
3.  **Enter API Keys** (if using a cloud provider).

Your settings will be saved to `~/.autocommit/config.json`.

---
## ## Usage

Using `autocommit` is simple and fits right into your existing workflow.

1.  **Stage your files** as you normally would:
    ```bash
    git add .
    ```

2.  **Run the tool**:
    ```bash
    autocommit
    ```

3.  The AI will generate a commit message. Use the **interactive menu** to commit the changes, regenerate the message, or copy it to your clipboard.

---
## ## Commands

| Command                 | Description                                                  |
| ----------------------- | ------------------------------------------------------------ |
| `autocommit`            | (Default) Analyzes staged changes and generates a commit message. |
| `autocommit configure`    | Starts the interactive setup guide to configure providers and models. |
| `autocommit config`       | Shows the current configuration from `~/.autocommit/config.json`. |
| `autocommit --help`       | Displays the help message with all commands and options.     |
| `autocommit --version`    | Shows the current version of the script.                     |

---
## ## Advanced Usage

### Environment Variables

You can override your saved configuration at runtime using environment variables. This is useful for temporary changes or for use in CI/CD pipelines.

| Variable                    | Description                                       |
| --------------------------- | ------------------------------------------------- |
| `AUTOCOMMIT_PROVIDER`       | Set the AI provider (e.g., `ollama`, `openai`).   |
| `AUTOCOMMIT_MODEL`          | Set the specific model name (e.g., `llama3:8b`).    |
| `AUTOCOMMIT_API_KEY`        | Provide an API key.                               |
| `AUTOCOMMIT_BASE_URL`       | Set a custom API endpoint.                        |
| `AUTOCOMMIT_MAX_DIFF_CHARS` | Set the max characters of the diff sent to the AI. |
| `AUTOCOMMIT_DEBUG=1`        | Enable debug mode to see API requests/responses.  |

### Customizing the AI Prompt

You can completely override the default system prompt and instructions sent to the AI. To do this, create a file at `~/.autocommit/instructions.txt`.

If this file exists, `autocommit` will use its contents as the instructions for the AI, giving you full control over the tone, style, and format of the generated messages.

---
## License

This project is licensed under the MIT License.
