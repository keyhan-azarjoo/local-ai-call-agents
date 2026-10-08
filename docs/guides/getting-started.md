# Getting started

## What you need

- A Mac. Apple silicon is recommended, with 16 GB of memory or more. More memory means bigger models and more calls at once.
- [Flutter](https://docs.flutter.dev/get-started/install) 3.44 or newer, to build the app.
- [Homebrew](https://brew.sh), for the voice and AI engines:

```bash
brew install livekit whisper-cpp llama.cpp uv
# for real phone calls (the app builds LiveKit's SIP service once):
brew install go redis opus libsoxr pkg-config
```

Ollama is optional: the app can run the AI model itself.

## Run it

```bash
git clone https://github.com/keyhan-azarjoo/local-ai-call-agents.git
cd local-ai-call-agents/app
flutter run -d macos          # or: flutter build macos --release
```

## First run

1. **Create the owner account.** This is the account that approves what the AI may do. Later you can add more people, each with a role: owner, admin, operator or viewer.
2. **Set up the voice engine.** The app installs the Python voice engine into its own folder and downloads a speech-recognition model. With **Install** it takes a few minutes.
3. **Choose the AI model.** Go to **Settings → AI engine**. *Built into LocalAILine* downloads a model sized for your computer and runs it inside the app. You can also choose Ollama, your own AI server, or a cloud provider. See [AI engines](ai-engines.md).
4. **Set up your business.**
   - **Build an app** gives you a ready-made business app (restaurant, barber, clinic…) with its own website.
   - **My assistant → Call flow → Set up a team** adds a receptionist, specialists and a person to pass calls to. Call flow, Skills and Knowledge appear as tabs once **Show all features** is on.
5. **Connect a phone line** in **Phone line**. See [Phone lines](phone-lines.md).

## The main pages

| Page | What it's for |
|---|---|
| **Home** | Today at a glance, calls on the line now, quick actions |
| **Chat** | Talk to your assistant in writing: ask about bookings, draft messages, use your tools |
| **Talk to Ava** | Speak to your assistant through the computer's microphone, exactly as a caller would hear it |
| **Calls** | Live calls word by word, recent conversations, every call with its transcript and recording, the test-call results |
| **Make a call** | Ask the assistant to ring someone for you, with a goal (e.g. "book a table for four on Friday") |
| **My assistant** | Its name, voice, greeting and languages, plus the **Call flow** (the team: who answers, who calls can be passed to, what each agent may use), skills and knowledge |
| **Build an app** | Your business apps: websites, manager pages and the tools the AI uses |
| **Phone line** | Phone numbers and landlines, and phones paired as companions |
| **Settings** | AI engine and models, voices and hearing, this computer, users and roles, activity log |

## Your data

Everything lives in one folder on your computer: `~/Library/Application Support/com.localailine.localailine`. That covers the database, recordings, business apps, models and logs. Nothing is sent anywhere unless you connect a cloud AI provider or a phone line.
