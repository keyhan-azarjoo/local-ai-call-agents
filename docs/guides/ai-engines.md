# AI engines and models

**Settings → AI engine** chooses where the language model runs. Calls, chat and the app builder all use it.

![AI engines](../screenshots/app-ai-engines.png)

| Engine | When to choose it |
|---|---|
| **Built into LocalAILine** (recommended) | Nothing else to install or run. The app runs llama.cpp's server itself, downloads the model you pick from Hugging Face, sizes it for your computer, restarts it if it stops, and shuts it down when you quit. |
| **Ollama** | You already use Ollama. LocalAILine sets it up for your number of calls at once (parallel slots, 8-bit memory, a capped prompt store). |
| **Your AI server** | vLLM, LM Studio, a llama.cpp server, MLX, LocalAI, Jan, or anything that speaks the OpenAI API, on this computer or another machine on your network. Enter its address and **Test**. |
| **Cloud AI** | OpenAI, Azure OpenAI, Google Gemini or Anthropic, with your own key. Call audio still stays on your computer; only the text of the conversation goes to the provider. |

## Choosing a model

The receptionist needs a model that calls tools reliably (check, book, look up) and answers quickly, because the caller is waiting. The built-in list:

| Model | Download | Notes |
|---|---:|---|
| Qwen3 4B Instruct (2507) | 2.5 GB | Suggested for most computers: reliable tool use, fast |
| Qwen3 8B | 5 GB | More careful; needs 24 GB+ of memory to run alongside the voice |
| Qwen2.5 7B Instruct | 4.7 GB | |
| Llama 3.2 3B Instruct | 2 GB | |
| Phi-4 mini | 2.5 GB | |
| Gemma 3 4B | 3.3 GB | |
| Granite 4.0 micro | 2 GB | |

You can also paste any Hugging Face `.gguf` link, or reuse a model you already downloaded with Ollama.

We compare models on the same spoken test calls: same callers, same businesses, same checks. See the [model comparison](../evaluations/MODELS.md).

## Other languages

Callers can speak their own language. Hearing detects it, and the assistant answers in it. Persian and Arabic use a larger hearing model and a multilingual model (Aya Expanse) when it's installed.

## Memory

On a 16–18 GB Mac the model, the voice engine and your other apps share memory. LocalAILine keeps the model's working memory small (8-bit) and caps its store of earlier prompts, so the computer doesn't start swapping, which would slow every answer. More memory allows a bigger model and more calls at the same time.
