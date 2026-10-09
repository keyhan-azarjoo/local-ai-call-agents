# Phone lines: your own number, Twilio and landlines

LocalAILine answers real phone calls on your own number (through your phone provider), on a Twilio number, or on a landline. You need no server, port forwarding or router change: this computer signs in to your provider and keeps that connection open, and calls come in through it.

![Phone line](../screenshots/app-phone-line.png)

## Your own number, through your provider

Keep the number you already have. If your phone provider offers a **SIP login** (often called "SIP device", "SIP phone", "BYOD" or "SIP credentials"), LocalAILine signs in with it, just like a desk phone would. Nothing to buy, no hardware, and your number doesn't move.

1. **From your provider**, get the SIP details for your number: the **SIP server** (also called registrar or domain), the **username** and the **password**. Some providers also give a separate **authentication username**, a **port**, or an **outbound proxy**.
2. **In LocalAILine:** **Phone line → Add phone line → My number, through my provider**.
3. **Pick your provider** if it's in the list (sipgate, Telnyx, Vonage Business, BT Cloud Voice, Zen…). That fills in the usual server, port and connection, but **check them with your provider**: products differ and change. Otherwise choose **Any SIP provider**.
4. Enter your **number** (with its country code, e.g. +44 7700 900123), the **username** and the **password**.
5. Choose the **connection**: **TLS** (secure, the default) if your provider offers it, else **TCP**, else **UDP**. Over TLS and TCP your provider sends calls back over the connection this computer opened, so nothing needs opening on your router.
6. Press **Test connection**. LocalAILine signs in once and tells you, in plain words, whether it worked: for example "wrong username or password", "the provider's address could not be found", or "refused the connection: check the port and transport".
7. **Save line.** The line shows its state: **Connected**, **Signing in…**, **Sign-in failed** (with the reason), or **Off**.

The assistant can also **make calls** from your number (**Make a call**): they go out through your provider and show your own number.

How it works: a small **phone gateway** runs on this computer (`packages/localailine_sipgw`). The first time you test or connect a line, LocalAILine builds it with Go (`brew install go`; it takes a minute). The gateway signs in to your provider and keeps that sign-in alive. When your number rings, your provider sends the call to the gateway, which passes it to the assistant. Only the call set-up goes through the gateway: the audio goes straight between your provider and this computer.

While LocalAILine is closed (or the line is **Off**), the gateway signs out, and your provider rings your other phones as before.

**Needs a real provider to check:** the sign-in and test work with any provider that offers SIP registration. Whether the call's audio gets through your home router depends on the router, just as with the Twilio line.

## Who takes the calls

Each line has its own choice, under **Who takes calls** on the line (and in the add/edit dialog):

- **AI answers** (the default): the assistant answers every call at once.
- **Ring me:** your phones paired with LocalAILine (those with ringing on) and the **Calls** page on this computer ring. Answer on a phone, or press **Answer** on the computer, and you talk to the caller yourself; the AI never joins. If nobody answers within the line's ring time, the AI answers and takes a message.
- **Ring me, then the AI:** the same, but after the ring time (you choose the seconds, 20 by default) the AI answers as usual.
- **Off:** calls on this line aren't answered here. For your own number, LocalAILine signs the line out, so your provider rings your other phones. For a Twilio number or a landline it's the same as turning off **Answer calls here**.

While a call is ringing you, the Calls page shows it with **Answer** and **Let the AI answer**. The caller hears a ringing tone until someone picks up. If they hang up first, the call is saved as missed.

## Connect a Twilio number

1. In [Twilio](https://www.twilio.com/console), buy a phone number with voice. Note your **Account SID** (starts with `AC`) and **Auth token**. An API key (`SK…`) with its secret works too.
2. In LocalAILine, open **Phone line → Add phone line → Twilio** and enter the SID, token and number. The app checks the account straight away.
3. Turn on **Answer calls here**. LocalAILine then sets everything up in your Twilio account:
   - an Elastic SIP trunk named *LocalAILine*, with its own login (a credential list) that only this computer knows;
   - your number pointed at that trunk;
   - the call bridge on this computer registered to it.
4. Ring the number. The agent that answers (see [the call flow](agents-and-call-flow.md)) greets the caller.

The assistant can also **make** calls from the same number (**Make a call**). It says who it is calling for, works toward the goal you gave it, and writes up what happened.

## Connect your landline

Your landline can plug straight into LocalAILine through a small **gateway box with an FXO port**, such as a Grandstream HT813 (about £50). The phone line goes into the box, and the box sits on the same network as the computer. Calls on the landline then come to your assistant, and the assistant can also call out on the line.

1. **Plug in:** connect the landline (from the wall socket) to the box's **FXO / Line** port, and the box to your router. In your router, give the box a fixed address (e.g. 192.168.1.40).
2. **In LocalAILine:** **Phone line → Add phone line → Landline (gateway box)**. Enter the box's address and your landline number.
3. **Turn on "Answer calls here"** on the new line. LocalAILine updates its phone service if needed, creates a login for the box, and shows the exact settings to enter.
4. **In the box's web page** (FXO port settings), enter what LocalAILine shows:
   - **SIP server:** this computer's address, port 5080;
   - **user ID and password:** the login LocalAILine generated;
   - **incoming calls (PSTN → VoIP):** forward each call to the SIP server, answering after one ring;
   - **caller ID detection:** turn it on, so the assistant knows who's calling.
5. **Ring your landline.** The assistant answers.

Only that box, from its address and with its login, can send calls in. A call from anywhere else on the network is refused. The call's audio stays on your local network.

**Tested:** [`app/test/landline_live_test.dart`](../../app/test/landline_live_test.dart) runs a simulated gateway box (SIPp) on the network. It confirms that:

- a wrong password and a different device are refused;
- the audio uses the computer's local address;
- the assistant answers and hears the caller (with caller ID);
- the call is saved with its transcript.

It does this without placing any real phone call.

**No box?** Most phone companies let you **forward** your landline (always, when busy, or when there's no answer) to your Twilio number instead.

For Telnyx and most other SIP providers, use **My number, through my provider** (above).

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

- Calls are accepted only through the call bridge or the phone gateway on this computer, never from elsewhere on your network. The gateway accepts a call from your provider only on the secret address it signed in with, and places outgoing calls only for the assistant, always with your line's own number.
- Test calls are simulated inside the app. They never place a real call, and the app refuses outbound calls while tests run.
