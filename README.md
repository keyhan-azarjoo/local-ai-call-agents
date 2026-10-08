<!-- myotgo-master-index -->
> **Part of the MyOTGO project.** The project was mothballed on 2026-10-08.
> **[📍 MASTER_INDEX — every MyOTGO repository, what it does, and where it ran](https://github.com/keyhan-azarjoo/MyOTGO-Project-Docs/blob/development/MASTER_INDEX.md)**
> Read that first: it is the only complete list, and it records what to do before restarting.

# LocalAILine: local AI call agents

[![CI](https://github.com/keyhan-azarjoo/local-ai-call-agents/actions/workflows/ci.yml/badge.svg)](https://github.com/keyhan-azarjoo/local-ai-call-agents/actions/workflows/ci.yml) [![License: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE) ![Flutter](https://img.shields.io/badge/Flutter-3.44-02569B?logo=flutter) ![macOS](https://img.shields.io/badge/host-macOS-black?logo=apple)

**An AI receptionist that runs on your own computer.** LocalAILine answers your business phone with a team of AI agents, takes bookings and orders in websites it builds for you, and keeps every word of every call on your machine. There's no LocalAILine cloud, no account to sign up for, and no per-minute AI bill.

![Live calls: each conversation streams word by word as it happens](docs/screenshots/app-calls-live.png)

<table>
<tr>
<td width="50%"><img src="docs/screenshots/app-call-flow.png" alt="Call flow: agents, hand-overs and people"><br><sub><b>Call flow.</b> A receptionist, specialists and real people, linked by who can pass a call to whom.</sub></td>
<td width="50%"><img src="docs/screenshots/manage-dashboard.png" alt="Business app manager dashboard"><br><sub><b>Your business app.</b> The manager page of a restaurant LocalAILine built: today's bookings, takings, busiest hours.</sub></td>
</tr>
<tr>
<td><img src="docs/screenshots/site-restaurant-home.png" alt="Generated restaurant website"><br><sub><b>Your website.</b> Customers book and order here; the AI books into the same place on the phone.</sub></td>
<td><img src="docs/screenshots/app-builder.png" alt="Build an app"><br><sub><b>Build an app.</b> Eleven professional templates, or describe your business and the builder designs one.</sub></td>
</tr>
</table>

## What it does

- **Answers real phone calls.** Connect a Twilio number in a few clicks; LocalAILine sets up the SIP trunk, registers this computer and answers.
- **Answers your landline too.** Plug your landline into a small gateway box (an FXO adapter such as a Grandstream HT813) on your network. LocalAILine answers the calls and can call out on the line. The box gets its own login and only it can ring in.
- **Works as a team.** A receptionist answers and passes calls to specialists (bookings, sales, customer service) or rings a real person. The hold music plays, then the next agent speaks in their own voice, with a short brief so the caller never repeats themselves.
- **Builds your business from a description.** Tell it what your business is, in your own words ("a dog-grooming salon with three groomers; customers book a wash or a full groom, and we sell shampoo"), and the local AI model designs and builds it: the tables for your bookings, orders and customers, a public website, a management website, and the MCP tools your call agents use to check, book, order, change and cancel by phone. You keep changing it in plain words ("add gift vouchers", "make the menu darker").
- **Or start from a template.** Restaurant, barber, salon, dental clinic, hotel, garage, gym, shop, tutoring, events or estate agent: each comes with a public website (booking, ordering with delivery, room finder, timetable…) and a manager page (dashboard, sortable tables, order board, calendars, customers). The AI uses the same app through MCP tools, so a phone booking and a website booking land in one place.
- **Knows your business.** Add documents and skills (a PDF of your menu, your policies); agents answer from them, each limited to what you give it.
- **Shows everything live.** See how many lines are busy, who is speaking, and each conversation word by word, as the caller is heard and as the AI answers. Calls can be recorded (callers are told).
- **Handles several calls at once.** The AI model, speech recognition and the voice all run in parallel, sized by one "Calls at the same time" setting for the computer it runs on.
- **Runs the AI where you choose.** Built into the app (llama.cpp, models downloaded for you), Ollama, any OpenAI-compatible server (vLLM, LM Studio, MLX, LocalAI, Jan), or a cloud provider.
- **Keeps people's data private.** A caller only ever reaches their own booking, checked by the number they call from *and* the name it's under; nothing about anyone else is ever read out. [Security model →](docs/SECURITY.md)

## Describe your business, get your system

```mermaid
flowchart LR
  you((You)) -->|"We're a dog-grooming salon…"| builder[Local AI model<br/>the app builder]
  builder --> spec[Your business, described:<br/>tables · fields · rules · pages · look]
  spec --> site[Public website<br/>book · order · see prices]
  spec --> manage[Management website<br/>dashboard · tables · board · calendar · customers]
  spec --> mcp[MCP tools<br/>check · book · order · change · cancel]
  mcp --> agents[Your call agents<br/>answer the phone]
```

1. In **Build an app → Describe my own**, describe your business. The local model asks a few questions (what customers book or order, opening hours, who works there) and proposes a plan.
2. When you agree, it builds the app. The same description becomes three things that always agree:
   - **a public website** where customers book and order;
   - **a management website** where you run the day;
   - **MCP tools** your call agents use on the phone.
3. Your agents start using it straight away. A caller who books by phone and a customer who books on the website land in the same calendar, under the same rules: no double-booking, opening hours, stock and capacity. Callers can only ever reach their own booking.

All of it runs on your computer, with your local model. Nothing about your business is sent anywhere.

## How it works

```mermaid
flowchart LR
  caller((Caller)) -->|phone call| twilio[Twilio number]
  landline((Landline)) --> fxo[Gateway box · FXO<br/>on your network]
  fxo -->|SIP on the local network| sip
  twilio -->|SIP trunk| bridge[Call bridge<br/>on this computer]
  bridge --> sip[LiveKit SIP]
  sip --> lk[LiveKit server]
  lk <--> voice[Voice engine<br/>Whisper · Kokoro · turn detection]
  voice <-->|streamed text| app[LocalAILine app<br/>agents · call flow · guards]
  app <-->|tools over MCP| biz[Business apps<br/>website · manager page · data]
  app <--> llm[AI model<br/>built-in llama.cpp · Ollama · vLLM · cloud]
  customer((Website visitor)) --> biz
```

1. A call reaches your Twilio number (or your landline, forwarded to it) and comes through the call bridge, a small program that keeps this computer registered with Twilio, so no router changes are needed.
2. The voice engine hears the caller with Whisper (a pool of servers so calls never queue), detects when they've finished speaking, and sends the words to the app.
3. The app picks the agent on the call, gives the model only that business's tools, and streams the answer back. The first words are spoken while the rest is still being written.
4. Bookings, orders and look-ups go through the business app's MCP tools, where the rules live: no double-booking, closed days, stock, capacity, and whose booking is whose.
5. When the caller is done ("No, that's all, thanks"), the assistant says goodbye and hangs up.

More in [ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Install and run

### 1. What you need

| | |
|---|---|
| Computer | A Mac with Apple silicon (M1 or newer); 16 GB memory or more (more memory = bigger models, more calls at once) |
| Disk | About 10 GB free for the voice engine, speech and AI models |
| Tools | [Homebrew](https://brew.sh), [Flutter](https://docs.flutter.dev/get-started/install/macos) 3.44 or newer, Xcode (from the App Store; Flutter needs it to build Mac apps) |
| For real calls | A [Twilio](https://www.twilio.com) account and phone number (optional: everything else works without it) |

### 2. Install the engines

```bash
# voice server, speech recognition, the built-in AI engine, Python packaging
brew install livekit whisper-cpp llama.cpp uv
# for real phone calls (LiveKit's SIP service is built once by the app)
brew install go redis opus libsoxr pkg-config
```

[Ollama](https://ollama.com) is optional: the app can run the AI model itself.

### 3. Get the code and run it

```bash
git clone https://github.com/keyhan-azarjoo/local-ai-call-agents.git
cd local-ai-call-agents/app
flutter pub get
flutter run -d macos
```

To build a standalone app instead, run `flutter build macos --release`. The app is created at `app/build/macos/Build/Products/Release/LocalAILine.app`; drag it into your Applications folder.

### 4. First launch

1. **Create the owner account**: your name, a username and a password.
2. **Voice engine:** press **Install**. The app sets up its Python voice engine and downloads the speech-recognition and voice models (a few minutes).
3. **AI model:** in **Settings → AI engine**, choose *Built into LocalAILine* and download the suggested model (Qwen3 4B, 2.5 GB). You can also use Ollama, your own AI server or a cloud provider.
4. **Try it without a phone line:** open **Talk to Ava** and speak, exactly as a caller would.
5. **Set up your business:** **Build an app** → pick a template (restaurant, barber, clinic…) → enter your business name. You get a website and a manager page.
6. **Your team:** **My assistant → Call flow → Set up a team** adds a receptionist, specialists and a person. Turn on **Show all features** to see the Call flow tab.
7. **Real calls:** **Phone line → Add phone line → Twilio**, enter your Account SID, Auth token and number, then turn on **Answer calls here**. Ring your number. Details: [Phone lines](docs/guides/phone-lines.md).

### 5. Run the tests

```bash
cd app
flutter analyze
flutter test $(ls test/*_test.dart test/scenarios/*_test.dart | grep -v live_test)
```

The spoken test calls run inside the app: **Calls → Tests → Run test scenarios** ([how they work](docs/TESTING.md)).

## Screenshots

| | |
|---|---|
| ![Home](docs/screenshots/app-home.png) **Home:** lines, calls today, latest calls | ![Calls](docs/screenshots/app-calls-live.png) **Calls:** live conversations word by word |
| ![Call flow](docs/screenshots/app-call-flow.png) **Call flow:** the team and who passes calls to whom | ![My assistant](docs/screenshots/app-assistant.png) **My assistant:** greeting, instructions, voice, skills |
| ![Agent editor](docs/screenshots/app-agent-editor.png) **One specialist:** what it may do and use on calls | ![Skills](docs/screenshots/app-skills.png) **Skills:** switch-on behaviours, some made from documents |
| ![Knowledge](docs/screenshots/app-knowledge.png) **Knowledge:** documents and folders indexed on this computer | ![Tools](docs/screenshots/app-tools.png) **Tools:** your apps' MCP servers and connectors |
| ![MCP tools](docs/screenshots/app-mcp-tools.png) **MCP tools:** what callers can do in the restaurant app | |
| ![Build an app](docs/screenshots/app-builder.png) **Build an app:** your apps and the template gallery | ![Phone line](docs/screenshots/app-phone-line.png) **Phone line:** Twilio, landline box, paired phones |
| ![AI engines](docs/screenshots/app-ai-engines.png) **Settings:** built-in AI engine and models | ![Test runs](docs/screenshots/app-test-runs.png) **Tests:** spoken test calls and their results |
| ![Restaurant website](docs/screenshots/site-restaurant-home.png) **Website:** a restaurant LocalAILine built | ![Menu](docs/screenshots/site-restaurant-menu.png) **Menu** with dietary labels and prices |
| ![Booking](docs/screenshots/site-restaurant-booking.png) **Booking:** find a free table | ![Hotel](docs/screenshots/site-hotel-rooms.png) **Hotel:** room finder with the price of the stay |
| ![Barber](docs/screenshots/site-barber-home.png) **Barber** website | ![Shop](docs/screenshots/site-shop-catalogue.png) **Shop** catalogue |
| ![Dashboard](docs/screenshots/manage-dashboard.png) **Manager dashboard:** takings, charts, today | ![Board](docs/screenshots/manage-board.png) **Order board:** drag from New to Done |
| ![Tables](docs/screenshots/manage-table.png) **Reservations:** day plan by table | ![Calendar](docs/screenshots/manage-calendar.png) **Calendar:** a garage's month |
| ![Customers](docs/screenshots/manage-customers.png) **Customers:** visits, spend, regulars | ![Mobile](docs/screenshots/site-mobile.png) **On a phone** |

## Guides

| Guide | |
|---|---|
| [Getting started](docs/guides/getting-started.md) | Install, first run, the main pages |
| [Phone lines: Twilio and landlines](docs/guides/phone-lines.md) | Connect a number, answer calls, forward a landline, several calls at once, recording |
| [Business apps and websites](docs/guides/business-apps.md) | Templates, the app builder, your website, the manager page, how the AI uses them |
| [Agents and the call flow](docs/guides/agents-and-call-flow.md) | Receptionist, specialists, people, hand-overs, skills and knowledge |
| [AI engines and models](docs/guides/ai-engines.md) | Built-in llama.cpp, Ollama, vLLM and other servers, cloud; which model to choose |
| [Security and privacy](docs/SECURITY.md) | What callers, website visitors and the network can and can't reach |
| [Testing and evaluation](docs/TESTING.md) | The 2,143 spoken test calls, how to run them, and the results |

## Tested with spoken phone calls

The app is tested with **spoken** calls. Simulated callers (personas, accents, other languages, nosy or hostile callers) talk through text-to-speech, are heard through the app's own speech recognition, and are answered by the AI. Every call is then checked against the business app's data: was the table booked, at the right time, under the right name? Was nothing said about anyone else?

| Test set | Scenarios | What it covers |
|---|---:|---|
| Single calls | 1,150 | At least 100 per business: bookings, orders (collection, delivery with address, dine-in), questions, changes, cancellations, full days, closed days, out of stock |
| Journeys | 338 | Book → call back to change → someone else tries to cancel → cancel; teams and hand-overs; switching business; skills; website + phone together |
| Hard calls | 479 | Five-minute calls with detours and small talk, changing their mind, rude callers, spelling names, prompt-injection attempts, eight other languages |
| Security | 176 | Callers trying to get other people's details, cancel their bookings, pose as the manager, or break the AI's rules, across all 11 businesses |

Plus 275 automated unit, widget and security tests, run on every push: website and MCP rules for every template, attacks on the business apps' servers, call-ending logic, live-view rendering, and the model engines.

**Results so far** (1,800+ spoken calls run while developing):

| Set | Run | Passed at least once | Best full round |
|---|---:|---:|---:|
| Single calls | 537 | 499 | 87% (214 of 246) |
| Security | 176 | 175: no data leaked in any run | 88% (44 of 50) |
| Journeys | 338 | 99 | 46% (22 of 48) |
| Hard calls | 10 | 0 | not yet run in full |

Journeys (multi-call, multi-agent) are the open problem, and the failures are published: mostly the small local model not using a tool when it said it would. Every run's full conversations, tool calls, timings and failures are in [docs/evaluations](docs/evaluations/), with the [model comparison](docs/evaluations/MODELS.md). See [Testing and evaluation](docs/TESTING.md).

## Tech stack

| Part | Built with |
|---|---|
| Desktop app | Flutter (Dart), Provider, SQLite, Argon2id password hashing, roles and approvals for AI actions |
| Voice | LiveKit server + SIP, LiveKit Agents (Python), whisper.cpp, Kokoro and Piper voices, Silero VAD, multilingual turn detection |
| AI | llama.cpp (built in), Ollama, OpenAI-compatible servers, OpenAI / Azure / Gemini / Anthropic; local embeddings for search |
| Business apps | Generated from a JSON spec: Dart HTTP server, HTML/CSS/JS website and manager page, MCP server per app |
| Phone | Twilio Elastic SIP trunking, a Go call bridge (SIP registration), LiveKit SIP |
| Tests | flutter_test, a Python scenario generator, a spoken-call scenario runner, headless Chrome |

## Project layout

```
app/                 the Flutter app (desktop + phone companion)
  lib/state/         app state, call handling, scenario runner, test businesses
  lib/services/      voice engine, phone, AI engines, MCP, knowledge, business apps
  lib/ui/            pages (calls, call flow, builder, phone line, settings…)
  assets/engine/     the Python voice engine, speech lab, call bridge source
  assets/scenarios/  the 2,143 test calls
  test/              unit, widget, security and live tests; scenario tools
  tools/             latency probe for the voice agent
docs/                guides, security, testing, evaluations, screenshots
skills/              an example business skill (restaurant)
```

## Status and roadmap

LocalAILine runs end to end on macOS: real Twilio calls, teams, business apps, websites, parallel calls, the live view and the built-in AI engine. Next:

- Telnyx and other SIP providers connected directly (they can be saved now; Twilio and landline gateways work today).
- Windows and Linux hosts.
- The phone companion serving an on-device model (Gemma 4 E2B/E4B) for the owner's chat and as an offline fallback.

## License

[Apache-2.0](LICENSE)
