# Phone lines: Twilio and landlines

LocalAILine answers real phone calls through a Twilio number. You need no server, port forwarding or router change: the call bridge on your computer keeps a secure connection to your own Twilio account open, and calls come in through it.

![Phone line](../screenshots/app-phone-line.png)

## Connect a Twilio number

1. In [Twilio](https://www.twilio.com/console), buy a phone number with voice. Note your **Account SID** (starts with `AC`) and **Auth token**. An API key (`SK…`) with its secret works too.
2. In LocalAILine, open **Phone line → Add phone line → Twilio** and enter the SID, token and number. The app checks the account straight away.
3. Turn on **Answer calls here**. LocalAILine then sets everything up in your Twilio account:
   - an Elastic SIP trunk named *LocalAILine*, with its own login (a credential list) that only this computer knows;
   - your number pointed at that trunk;
   - the call bridge on this computer registered to it.
4. Ring the number. The agent that answers (see [the call flow](agents-and-call-flow.md)) greets the caller.

The assistant can also **make** calls from the same number (**Make a call**). It says who it is calling for, works toward the goal you gave it, and writes up what happened.

## Keep your landline

You don't have to change numbers. Most phone companies let you **forward** your landline to another number: always, when busy, or when there's no answer. Forward it to your Twilio number and LocalAILine answers your landline calls. *When busy* or *no answer* forwarding is a gentle start: the assistant only picks up when you can't.

A direct connection for landlines, through an FXO gateway box on your network, and for Telnyx and other SIP providers is on the roadmap. You can save those lines now.

## Several calls at once

**Calls → Calls at the same time** sets how many calls this computer handles side by side. It starts from the computer's memory, from 1 up to 10 on a large machine. That one setting sizes everything:

- **The AI model** works on that many answers together (parallel slots).
- **Hearing:** a pool of whisper servers, so callers never queue to be heard.
- **The voice:** a ready process per call, with the voice already loaded, so the first words come at once.

More calls than that are still answered, just more slowly. To check that every part really runs in parallel on a given computer:

```bash
python3 app/test/scenarios/parallel_check.py 3
```

On a 2023 MacBook Pro (M3 Pro, 18 GB), three requests at once take about 1.8 s for answers, 0.3 s for hearing and 2.6 s for the voice, against 0.9 s, 0.1 s and 1.5 s for one. That's 2.2–2.8× the work in the same time.

## While a call is on

- **Calls** shows every call on the line. As the caller speaks you see their words, then what was actually heard; the AI's answer streams in as it's written. Hand-overs ("♪ on hold — passed to Mia") and the end of the call appear in the same view.
- **Ending a call:** the assistant checks the caller has nothing else ("Is there anything else I can help you with?") and says goodbye before hanging up. A plain "thank you" never ends the call.
- **Recording** (Calls → Record calls) keeps both sides of each call on this computer. Callers hear "This call may be recorded." at the start.

## Safety

- Calls are accepted only through the call bridge on this computer, never from elsewhere on your network.
- Test calls are simulated inside the app. They never place a real call, and the app refuses outbound calls while tests run.
