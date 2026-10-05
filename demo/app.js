/* LocalAILine — clickable design demo. Static mock data, no backend. */

const I = {
  dash: '<path d="M3 13h8V3H3zM13 21h8V11h-8zM3 21h8v-6H3zM13 3v6h8V3z"/>',
  phone: '<path d="M22 16.9v3a2 2 0 0 1-2.2 2 19.8 19.8 0 0 1-8.6-3.1 19.5 19.5 0 0 1-6-6A19.8 19.8 0 0 1 2.1 4.2 2 2 0 0 1 4.1 2h3a2 2 0 0 1 2 1.7c.1.9.4 1.8.7 2.7a2 2 0 0 1-.5 2.1L8 9.8a16 16 0 0 0 6 6l1.3-1.3a2 2 0 0 1 2.1-.4c.9.3 1.8.6 2.7.7a2 2 0 0 1 1.7 2z"/>',
  live: '<circle cx="12" cy="12" r="2"/><path d="M16.2 7.8a6 6 0 0 1 0 8.4M7.8 16.2a6 6 0 0 1 0-8.4M19.1 4.9a10 10 0 0 1 0 14.2M4.9 19.1a10 10 0 0 1 0-14.2"/>',
  bot: '<rect x="3" y="8" width="18" height="12" rx="3"/><path d="M12 8V4M8 14h.01M16 14h.01"/>',
  book: '<path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20V3H6.5A2.5 2.5 0 0 0 4 5.5z"/><path d="M4 19.5A2.5 2.5 0 0 0 6.5 22H20v-5"/>',
  plug: '<path d="M9 2v6M15 2v6M6 8h12v4a6 6 0 0 1-12 0zM12 18v4"/>',
  spark: '<path d="M12 3l1.9 5.8L20 10l-5 3.6L16.5 20 12 16.6 7.5 20 9 13.6 4 10l6.1-1.2z"/>',
  chip: '<rect x="6" y="6" width="12" height="12" rx="2"/><path d="M9 2v4M15 2v4M9 18v4M15 18v4M2 9h4M2 15h4M18 9h4M18 15h4"/>',
  mic: '<rect x="9" y="2" width="6" height="12" rx="3"/><path d="M5 10a7 7 0 0 0 14 0M12 17v5"/>',
  cpu: '<rect x="2" y="4" width="20" height="14" rx="2"/><path d="M8 22h8M12 18v4"/>',
  line: '<path d="M4 4h16v6H4zM4 14h16v6H4zM8 7h.01M8 17h.01"/>',
  server: '<circle cx="6" cy="12" r="3"/><circle cx="18" cy="6" r="3"/><circle cx="18" cy="18" r="3"/><path d="M8.6 10.5l6.8-3M8.6 13.5l6.8 3"/>',
  users: '<circle cx="9" cy="8" r="4"/><path d="M2 21a7 7 0 0 1 14 0M17 4a4 4 0 0 1 0 8M22 21a7 7 0 0 0-4-6.3"/>',
  contact: '<rect x="4" y="2" width="16" height="20" rx="2"/><circle cx="12" cy="10" r="3"/><path d="M8 17a4 4 0 0 1 8 0"/>',
  device: '<rect x="7" y="2" width="10" height="20" rx="2"/><path d="M11 18h2"/>',
  gear: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-2.9 1.2V21a2 2 0 0 1-4 0v-.1A1.7 1.7 0 0 0 7 19.4a1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1A1.7 1.7 0 0 0 1.2 14H1a2 2 0 0 1 0-4h.1A1.7 1.7 0 0 0 2.6 7a1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1A1.7 1.7 0 0 0 7 2.6 1.7 1.7 0 0 0 8 1.1V1a2 2 0 0 1 4 0v.1a1.7 1.7 0 0 0 2.9 1.2l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1A1.7 1.7 0 0 0 19.4 7c.2.6.8 1 1.5 1H21a2 2 0 0 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/>',
  log: '<path d="M4 6h16M4 12h16M4 18h10"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  play: '<path d="M6 4l14 8-14 8z"/>',
  stop: '<rect x="6" y="6" width="12" height="12" rx="1"/>',
  dl: '<path d="M12 3v12M7 10l5 5 5-5M5 21h14"/>',
  search: '<circle cx="11" cy="11" r="7"/><path d="M21 21l-4.3-4.3"/>',
  moon: '<path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z"/>',
  bell: '<path d="M18 8a6 6 0 0 0-12 0c0 7-3 9-3 9h18s-3-2-3-9M13.7 21a2 2 0 0 1-3.4 0"/>',
  hang: '<path d="M3 13c5-5 13-5 18 0l-2.5 2.5-3-1.5v-2.5a10 10 0 0 0-7 0V14l-3 1.5z"/>',
  hand: '<path d="M18 11V6a2 2 0 0 0-4 0M14 10V4a2 2 0 0 0-4 0v2M10 10.5V6a2 2 0 0 0-4 0v8a8 8 0 0 0 16 0v-2a2 2 0 0 0-4 0"/>',
  upload: '<path d="M12 21V9M7 14l5-5 5 5M5 3h14"/>',
  check: '<path d="M5 12l5 5L20 7"/>',
  shield: '<path d="M12 2l8 4v6c0 5-3.5 8.5-8 10-4.5-1.5-8-5-8-10V6z"/>',
  out: '<path d="M15 3h6v6M21 3l-8 8"/><path d="M20 15.5v3a2 2 0 0 1-2.2 2A17 17 0 0 1 3.5 6.2 2 2 0 0 1 5.5 4h3l1.5 4-2 1.5a12 12 0 0 0 6.5 6.5l1.5-2z"/>',
  loop: '<path d="M17 2l4 4-4 4"/><path d="M3 11V9a3 3 0 0 1 3-3h15M7 22l-4-4 4-4"/><path d="M21 13v2a3 3 0 0 1-3 3H3"/>',
  qr: '<rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/><rect x="3" y="14" width="7" height="7"/><path d="M14 14h3v3h-3zM20 14v.01M14 20h.01M17 20h4v-3"/>',
};
const ic = (n, s = 17) => `<svg width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">${I[n]}</svg>`;

const NAV = [
  ['Operate', [
    ['dashboard', 'Overview', 'dash'],
    ['talk', 'Talk to Ava', 'mic'],
    ['live', 'Live call', 'live', '<span class="lamp ring"></span>'],
    ['outbound', 'Make a call', 'out'],
    ['calls', 'Call history', 'phone'],
    ['contacts', 'Contacts & rules', 'contact'],
  ]],
  ['Assistant', [
    ['agents', 'Agents', 'bot'],
    ['automations', 'Automations & loops', 'loop'],
    ['knowledge', 'Knowledge', 'book'],
    ['tools', 'Tools (MCP)', 'plug'],
    ['skills', 'Skills', 'spark'],
  ]],
  ['Engine', [
    ['models', 'Language models', 'chip'],
    ['speech', 'Voice & hearing', 'mic'],
    ['hardware', 'This computer', 'cpu'],
  ]],
  ['Connect', [
    ['lines', 'Phone lines', 'line'],
    ['voiceserver', 'Voice server', 'server'],
    ['devices', 'Paired devices', 'device'],
  ]],
  ['Admin', [
    ['users', 'Users & access', 'users'],
    ['logs', 'Activity & logs', 'log'],
    ['settings', 'Settings', 'gear'],
  ]],
];

/* Simple mode: what a new user sees. Everything else is behind "Show all features". */
const SIMPLE_NAV = [
  ['home', 'Home', 'dash'],
  ['talk', 'Talk to Ava', 'mic'],
  ['calls', 'Calls', 'phone'],
  ['outbound', 'Make a call', 'out'],
  ['assistant', 'My assistant', 'bot'],
  ['lines', 'Phone line', 'line'],
  ['settings', 'Settings', 'gear'],
];
let advanced = localStorage.getItem('ll-adv') === '1';
function setAdvanced(v) { advanced = v; localStorage.setItem('ll-adv', v ? '1' : ''); render(); }

const TITLES = Object.fromEntries(NAV.flatMap(([g, items]) => items.map(i => [i[0], [g, i[1]]])));
TITLES.assistant = ['Assistant', 'Agents › Ava'];
TITLES.home = ['', 'Home'];
TITLES.talk = ['Operate', 'Talk to Ava'];
TITLES.call = ['Operate', 'Call history › Sarah Mitchell'];

/* ---------- shared fragments ---------- */
const head = (title, desc, actions = '') => `
  <div class="page-head"><div><h1>${title}</h1>${desc ? `<p>${desc}</p>` : ''}</div>
  ${actions ? `<div class="actions">${actions}</div>` : ''}</div>`;
const btn = (label, cls = '', icon = '', on = '') =>
  `<button class="btn ${cls}" onclick="${on || `toast('${label.replace(/'/g, '')} — demo only')`}">${icon ? ic(icon) : ''}${label}</button>`;
const tog = (on = true) => `<label class="toggle"><input type="checkbox" ${on ? 'checked' : ''}><span></span></label>`;
const lamp = s => `<span class="lamp ${s}"></span>`;
const badge = (t, c = '') => `<span class="badge ${c}">${t}</span>`;
const meter = (pct, c = '') => `<div class="meter"><i class="${c}" style="width:${pct}%"></i></div>`;
const wave = (n = 28, quiet = false) =>
  `<div class="wave ${quiet ? 'quiet' : ''}">${Array.from({ length: n }, (_, i) =>
    `<i style="height:${10 + ((i * 37) % 24)}px;animation-delay:${(i % 7) * -0.13}s"></i>`).join('')}</div>`;

function callPath(live = true) {
  const st = [
    ['Caller', 'PSTN · Twilio', '—', 'on'],
    ['Voice server', 'LiveKit SIP', '18 ms', 'on'],
    ['Hearing', 'Whisper large-v3-turbo', '210 ms', 'on'],
    ['Thinking', 'Qwen3 8B · Ollama', '160 ms', live ? 'ring' : 'on'],
    ['Speaking', 'Kokoro · "Bella"', '95 ms', 'on'],
  ];
  return `<div class="callpath">${st.map((s, i) => `
    ${i ? `<div class="cord ${live ? '' : 'idle'}"></div>` : ''}
    <div class="jack ${live && s[3] === 'ring' ? 'hot' : ''}">
      <div class="eyebrow">${lamp(s[3])}${s[0]}</div>
      <div class="name">${s[1]}</div><div class="ms">${s[2]}</div>
    </div>`).join('')}</div>
    <div class="callpath-total"><span>Reply time <b>~480 ms</b></span><span>Turn detection <b>local · v1-mini</b></span><span>Audio <b>G.711 µ-law 8 kHz → 16 kHz</b></span></div>`;
}

/* ---------- mock data ---------- */
const CALLS = [
  ['Riverside Dental', '+44 20 7946 0011', 'Today 11:05', '2m 40s', '↗ AI called · goal met', 'Moved check-up to Tue 14 Oct, 10:00', 'green'],
  ['Sarah Mitchell', '+44 7700 900123', 'Today 10:42', '3m 12s', 'AI answered', 'Booked a viewing for Thursday 2pm', 'green'],
  ['Unknown', '+44 20 7946 0958', 'Today 09:15', '0m 48s', 'Screened', 'Sales call — declined politely', 'amber'],
  ['Dr. Patel’s office', '+44 161 496 0321', 'Today 08:30', '1m 55s', 'AI answered', 'Appointment moved to 14 Oct', 'green'],
  ['James Okafor', '+44 7700 900456', 'Yesterday 17:20', '5m 03s', 'Taken over', 'You joined after 1m 10s', 'blue'],
  ['Unknown', '+1 415 555 0134', 'Yesterday 13:02', '0m 06s', 'Blocked', 'Matched spam list', 'red'],
  ['Amira Haddad', '+44 7700 900789', 'Mon 11:48', '2m 21s', 'Message taken', '“Call back about the invoice”', 'green'],
  ['Landline · Home', '+44 1632 960555', 'Mon 09:01', '1m 40s', 'AI answered', 'Parcel delivery confirmed', 'green'],
];
const MODELS = [
  ['Qwen3 8B', 'Q4_K_M', '5.2 GB', 'Great fit', 'green', true, 'Best all-round for calls. Fast tool calling.'],
  ['Llama 3.3 8B Instruct', 'Q4_K_M', '4.9 GB', 'Great fit', 'green', false, 'Strong English conversation.'],
  ['Gemma 3 12B', 'Q4_K_M', '8.1 GB', 'Fits', 'blue', false, 'Better reasoning, slower first word.'],
  ['Mistral Small 3.2 24B', 'Q4_K_M', '14.3 GB', 'Tight', 'amber', false, 'Needs 16 GB free memory.'],
  ['Qwen3 32B', 'Q4_K_M', '19.8 GB', 'Too large', 'red', false, 'Exceeds available memory.'],
  ['Qwen3 1.7B', 'Q8_0', '1.8 GB', 'Great fit', 'green', false, 'For small machines and Raspberry Pi.'],
];

/* ---------- pages ---------- */
const P = {};



let talkMode = 'caller', talking = false;
P.talk = () => `
  <div style="max-width:760px;margin:0 auto">
  <div style="text-align:center;margin-bottom:22px">
    <h1 style="font-size:30px">Talk to Ava</h1>
    <p class="muted" style="margin:6px 0 14px">Uses your microphone. Nothing leaves this computer.</p>
    <div class="seg"><button class="${talkMode === 'caller' ? 'on' : ''}" onclick="talkMode='caller';render()">Pretend I’m a caller</button><button class="${talkMode === 'owner' ? 'on' : ''}" onclick="talkMode='owner';render()">Give Ava instructions</button></div>
    <p class="small muted" style="margin-top:10px">${talkMode === 'caller' ? 'Ava answers exactly as she would on a real call — same greeting, rules and tools.' : 'Ask Ava to make calls, check messages or change how she answers. e.g. “Call the dentist and move my appointment.”'}</p>
  </div>
  <div class="card card-pad" style="padding:34px;text-align:center">
    <button onclick="talking=!talking;render()" aria-label="${talking ? 'Stop talking' : 'Start talking'}" style="width:112px;height:112px;border-radius:50%;border:0;cursor:pointer;background:${talking ? 'var(--red)' : 'var(--amber)'};color:var(--navy);display:inline-grid;place-items:center;box-shadow:0 0 0 ${talking ? 14 : 0}px rgba(242,169,59,.18)">${ic(talking ? 'stop' : 'mic', 40)}</button>
    <div style="margin-top:16px;font-weight:600">${talking ? 'Listening… tap to stop' : 'Tap to start talking'}</div>
    <div style="display:flex;justify-content:center;margin-top:14px">${wave(34, !talking)}</div>
  </div>
  <div class="card" style="margin-top:16px"><div class="card-head"><h2>Conversation</h2><div class="right">${btn('Clear', 'sm ghost')}</div></div>
    <div class="card-pad transcript">${talkMode === 'caller' ? `
      <div class="turn ai"><div class="who">Ava</div><div class="bubble">Hi, you’ve reached Keyhan’s line. I’m Ava, his assistant — how can I help?</div></div>
      <div class="turn"><div class="who">You</div><div class="bubble">Hi, is the flat on Elm Street still available?</div></div>
      <div class="turn ai"><div class="who">Ava</div><div><div class="bubble">It is! It’s a two-bed with parking at the rear. Would you like to book a viewing?</div><div class="meta">0.44 s reply · from Knowledge: listings-oct.pdf</div></div></div>` : `
      <div class="turn"><div class="who">You</div><div class="bubble">Call Riverside Dental and move my check-up to next week, mornings only.</div></div>
      <div class="turn ai"><div class="who">Ava</div><div><div class="bubble">Okay — I’ll call Riverside Dental now from your Twilio number and ask for a morning next week. I’ll let you know what they say.</div>
        <div class="row" style="margin-top:8px">${btn('Start the call', 'amber sm', 'out', "go('outbound')")}${btn('Edit details', 'sm', '', "go('outbound')")}</div></div></div>`}
    </div>
    <div class="modal-foot" style="justify-content:stretch"><input class="input" placeholder="Or type a message…"><button class="btn primary">Send</button></div>
  </div></div>`;

P.home = () => `
  <div style="max-width:880px;margin:0 auto">
  <div class="card card-pad" style="padding:28px;margin-bottom:16px">
    <div class="row between">
      <div><div class="row">${lamp('on')}<span class="eyebrow">Answering on +44 20 3870 1142</span></div>
      <h1 style="font-size:30px;margin-top:10px">Ava is answering your calls.</h1>
      <p class="muted" style="margin:6px 0 0">Everything runs on this computer. 4 calls today · 1 message waiting.</p></div>
      <label class="row" style="gap:10px"><span class="small">Answering</span>${tog(true)}</label>
    </div>
  </div>
  <div class="grid g3" style="margin-bottom:16px">
    ${[['out', 'Make a call', 'Tell Ava who to call and why.', 'outbound'], ['mic', 'Talk to Ava', 'Try her as a caller, or give her instructions.', 'talk'], ['bot', 'Change what Ava says', 'Greeting, instructions, voice.', 'assistant']].map(a => `
      <a class="card card-pad pick" href="#/${a[3]}" style="text-decoration:none;display:block;padding:22px">
        <div class="logo" style="background:var(--amber-soft);border-color:transparent;color:#9a5f00">${ic(a[0], 19)}</div>
        <h3 style="margin-top:14px;font-size:16px">${a[1]}</h3><div class="small muted">${a[2]}</div></a>`).join('')}
  </div>
  <div class="card">
    <div class="card-head"><h2>Latest calls</h2><div class="right"><a class="btn sm" href="#/calls">See all</a></div></div>
    ${CALLS.slice(0, 4).map(c => `<div class="tile click" style="cursor:pointer" onclick="go('call')"><div class="logo">${c[4].startsWith('↗') ? ic('out', 16) : ic('phone', 16)}</div>
      <div style="flex:1"><b>${c[0]}</b><div class="small muted">${c[5]}</div></div><div style="text-align:right">${badge(c[4], c[6])}<div class="small muted mono" style="margin-top:4px">${c[2]}</div></div></div>`).join('')}
  </div></div>`;

P.dashboard = () => `
  ${head('Good morning, Keyhan', 'Your assistant is answering on 2 lines. Everything runs on this computer.',
    btn('Talk to your assistant', '', 'mic', "go('talk')") + btn('Make a call', '', 'out', "go('outbound')") + btn('Simulate incoming call', 'amber', 'phone', 'ring()'))}
  <div class="card card-pad" style="margin-bottom:16px">
    <div class="row between" style="margin-bottom:12px"><h2>Call path</h2>${badge(lamp('on') + 'All stages ready', 'green')}</div>
    ${callPath(false)}
  </div>
  <div class="grid g4" style="margin-bottom:16px">
    <div class="card card-pad"><div class="eyebrow">Calls today</div><div class="stat">14</div><div class="small muted">11 handled by AI · 2 screened · 1 blocked</div></div>
    <div class="card card-pad"><div class="eyebrow">Avg reply time</div><div class="stat">0.48<small>s</small></div><div class="small muted">From caller pause to first word</div></div>
    <div class="card card-pad"><div class="eyebrow">Calls made by AI</div><div class="stat">5</div><div class="small muted">4 goals met · 1 retry at 14:00 · <a href="#/outbound">View</a></div></div>
    <div class="card card-pad"><div class="eyebrow">Memory in use</div><div class="stat">11.4<small>/ 32 GB</small></div>${meter(36)}</div>
  </div>
  <div class="grid g3">
    <div class="card span2">
      <div class="card-head"><h2>Recent calls</h2><div class="right"><a class="btn sm" href="#/calls">View all</a></div></div>
      <table><tbody>${CALLS.slice(0, 5).map((c, i) => `<tr class="click" onclick="go('call')">
        <td><b>${c[0]}</b><div class="small muted mono">${c[1]}</div></td><td>${badge(c[4], c[6])}</td>
        <td class="small">${c[5]}</td><td class="small muted mono">${c[2]}</td></tr>`).join('')}</tbody></table>
    </div>
    <div class="stack">
      <div class="card">
        <div class="card-head"><h2>Phone lines</h2></div>
        <div class="tile"><div class="logo" style="color:#f22f46">Tw</div><div style="flex:1"><b>Twilio</b><div class="small muted mono">+44 20 3870 1142</div></div>${lamp('on')}</div>
        <div class="tile"><div class="logo">☎</div><div style="flex:1"><b>Home landline</b><div class="small muted">Grandstream HT813 · FXO</div></div>${lamp('on')}</div>
        <div class="tile"><div class="logo" style="color:#00c08b">Tx</div><div style="flex:1"><b>Telnyx</b><div class="small muted">Not connected</div></div>${lamp('off')}</div>
      </div>
      <div class="card card-pad">
        <div class="row between"><h3>Answering mode</h3>${badge('After 3 rings', 'amber')}</div>
        <div class="seg" style="margin-top:10px"><button>Never</button><button>Ask me</button><button class="on">After rings</button><button>Always</button></div>
        <p class="small muted" style="margin:10px 0 0">Unknown callers are screened first. VIPs ring your devices before the AI picks up.</p>
      </div>
    </div>
  </div>`;

P.live = () => `
  ${head('Live call', 'Sarah Mitchell · +44 7700 900123 · via Twilio', `
    ${btn('Mute AI', '', 'mic')}${btn('Take over', 'amber', 'hand', "toast('You are now on the call. AI is listening and taking notes.')")}${btn('Hang up', 'danger', 'hang', "toast('Call ended. Summary saved.');go('call')")}`)}
  <div class="card card-pad" style="margin-bottom:16px">
    <div class="row between" style="margin-bottom:12px"><div class="row">${badge(lamp('ring') + 'On call · 01:47', 'amber')}<span class="small muted">Room <span class="mono">pstn-in-7f3a</span></span></div>${wave(40)}</div>
    ${callPath(true)}
  </div>
  <div class="grid g3">
    <div class="card span2">
      <div class="card-head"><h2>Transcript</h2><div class="right">${badge('Live')}<button class="btn sm ghost">Copy</button></div></div>
      <div class="card-pad transcript">
        <div class="turn ai"><div class="who">AI</div><div><div class="bubble">Hi, you’ve reached Keyhan’s line. I’m his assistant — how can I help?</div><div class="meta">00:01 · greeting clip</div></div></div>
        <div class="turn"><div class="who">Caller</div><div><div class="bubble">Hi, it’s Sarah. I wanted to book a viewing for the flat on Thursday.</div><div class="meta">00:06 · 0.94 confidence</div></div></div>
        <div class="turn tool"><div class="who">Tool</div><div><div class="bubble">calendar.find_free_slots(day="Thu") → 11:00, 14:00, 16:30</div><div class="meta">00:08 · MCP · Google Calendar · read-only</div></div></div>
        <div class="turn ai"><div class="who">AI</div><div><div class="bubble">Thursday works. I have 11am, 2pm or 4:30. Which suits you?</div><div class="meta">00:09 · 0.46 s reply</div></div></div>
        <div class="turn"><div class="who">Caller</div><div><div class="bubble">2pm is perfect.</div><div class="meta">00:13</div></div></div>
        <div class="turn tool"><div class="who">Tool</div><div><div class="bubble">calendar.create_event(…) — waiting for your approval</div><div class="meta">00:14 · write action</div></div></div>
      </div>
    </div>
    <div class="stack">
      <div class="card card-pad" style="border-color:var(--amber)">
        <div class="eyebrow" style="color:#9a5f00">Approval needed</div>
        <h3 style="margin:6px 0">Create calendar event</h3>
        <dl class="kv small"><dt>Title</dt><dd>Viewing — Sarah Mitchell</dd><dt>When</dt><dd>Thu 9 Oct, 14:00–14:30</dd></dl>
        <div class="row" style="margin-top:12px">${btn('Approve', 'green', 'check', "toast('Approved. Event created.')")}${btn('Deny', '')}</div>
      </div>
      <div class="card card-pad">
        <h3>Whisper to the AI</h3>
        <p class="small muted" style="margin:4px 0 10px">Only the AI hears this. The caller does not.</p>
        <textarea class="input" placeholder="e.g. Offer her the 4:30 slot instead"></textarea>
        <div style="margin-top:8px">${btn('Send instruction', 'primary')}</div>
      </div>
      <div class="card card-pad">
        <h3>Caller</h3>
        <dl class="kv small" style="margin-top:8px"><dt>Contact</dt><dd>Sarah Mitchell ${badge('VIP', 'amber')}</dd><dt>Previous calls</dt><dd>4</dd><dt>Skills active</dt><dd>Calendar, Take message</dd><dt>Knowledge</dt><dd>Property listings</dd></dl>
      </div>
    </div>
  </div>`;

P.calls = () => `
  ${head('Call history', 'Every call is recorded on this computer only. Recordings and transcripts never leave it.', btn('Export', '', 'dl'))}
  <div class="row wrap" style="margin-bottom:14px">
    <div class="seg"><button class="on">All</button><button>Incoming</button><button>Made by AI</button><button>AI answered</button><button>Messages</button><button>Screened</button><button>Blocked</button></div>
    <input class="input" style="width:260px;margin-left:auto" placeholder="Search name, number or words said">
    <select class="input" style="width:150px"><option>All lines</option><option>Twilio</option><option>Home landline</option></select>
  </div>
  <div class="card"><table>
    <thead><tr><th>Caller</th><th>Outcome</th><th>Summary</th><th>Line</th><th>Duration</th><th>When</th></tr></thead>
    <tbody>${CALLS.map((c, i) => `<tr class="click" onclick="go('call')">
      <td><b>${c[0]}</b><div class="small muted mono">${c[1]}</div></td><td>${badge(c[4], c[6])}</td><td class="small">${c[5]}</td>
      <td class="small muted">${i === 6 ? 'Landline' : 'Twilio'}</td><td class="mono small">${c[3]}</td><td class="mono small muted">${c[2]}</td></tr>`).join('')}</tbody>
  </table></div>`;

P.call = () => `
  ${head('Sarah Mitchell', '+44 7700 900123 · Today 10:42 · 3m 12s · Twilio', btn('Call back', '', 'phone') + btn('Delete recording', 'danger'))}
  <div class="grid g3">
    <div class="card span2">
      <div class="card-head"><h2>Recording</h2></div>
      <div class="card-pad"><div class="row">${btn('', 'primary sm', 'play')}${wave(70, true)}<span class="mono small muted">00:00 / 03:12</span></div></div>
      <div class="card-head" style="border-top:1px solid var(--line)"><h2>Transcript</h2></div>
      <div class="card-pad transcript">
        <div class="turn ai"><div class="who">AI</div><div class="bubble">Hi, you’ve reached Keyhan’s line. How can I help?</div></div>
        <div class="turn"><div class="who">Caller</div><div class="bubble">Hi, it’s Sarah. I wanted to book a viewing for Thursday.</div></div>
        <div class="turn ai"><div class="who">AI</div><div class="bubble">Thursday works. I have 11am, 2pm or 4:30.</div></div>
        <div class="turn"><div class="who">Caller</div><div class="bubble">2pm is perfect, thanks.</div></div>
      </div>
    </div>
    <div class="stack">
      <div class="card card-pad"><h3>Summary</h3><p class="small" style="margin:6px 0 0">Sarah booked a flat viewing for Thursday 9 Oct at 14:00. She asked whether parking is available — the AI answered from “Property listings”.</p></div>
      <div class="card card-pad"><h3>Actions taken</h3>
        <div class="small" style="margin-top:8px">${badge('Approved', 'green')} Calendar event created</div>
        <div class="small" style="margin-top:6px">${badge('Sent', 'blue')} Text confirmation to caller</div></div>
      <div class="card card-pad"><h3>Timing</h3><dl class="kv small" style="margin-top:8px"><dt>Avg reply</dt><dd class="mono">0.46 s</dd><dt>Slowest reply</dt><dd class="mono">1.10 s</dd><dt>Interruptions</dt><dd class="mono">2</dd></dl></div>
    </div>
  </div>`;

P.contacts = () => `
  ${head('Contacts & rules', 'Decide who the AI answers, who rings through to you, and who never gets through.', btn('Import contacts', '', 'upload') + btn('Add contact', 'primary', 'plus'))}
  <div class="grid g3">
    <div class="card span2"><table>
      <thead><tr><th>Name</th><th>Number</th><th>Rule</th><th>Calls</th></tr></thead>
      <tbody>
        <tr><td><b>Sarah Mitchell</b></td><td class="mono small">+44 7700 900123</td><td>${badge('VIP · ring me first', 'amber')}</td><td class="mono">4</td></tr>
        <tr><td><b>James Okafor</b></td><td class="mono small">+44 7700 900456</td><td>${badge('AI answers', 'green')}</td><td class="mono">9</td></tr>
        <tr><td><b>Dr. Patel’s office</b></td><td class="mono small">+44 161 496 0321</td><td>${badge('AI answers', 'green')}</td><td class="mono">2</td></tr>
        <tr><td><b>Spam list</b> <span class="small muted">· 1,204 numbers</span></td><td class="mono small">—</td><td>${badge('Block', 'red')}</td><td class="mono">31</td></tr>
      </tbody></table></div>
    <div class="card card-pad stack">
      <h3>Unknown callers</h3>
      <div class="field"><label>When the number isn’t in contacts</label><select class="input"><option>Screen first, then decide</option><option>AI answers fully</option><option>Take a message only</option><option>Send to voicemail</option></select></div>
      <div class="row between"><span>Block withheld numbers</span>${tog(false)}</div>
      <div class="row between"><span>Never tell callers my schedule</span>${tog(true)}</div>
      <div class="row between"><span>Quiet hours 22:00–07:00</span>${tog(true)}</div>
    </div>
  </div>`;

P.assistant = () => `
  ${head('Ava · Receptionist', 'How this agent sounds, what it says first, and what it does on every call it answers.', btn('Test with a call', 'amber', 'phone', 'ring()') + btn('Save changes', 'primary'))}
  <div class="tabs"><button class="on">Persona</button><button>Call flow</button><button>Skills & tools</button><button>Hand-offs</button><button>Hours</button><button>Safety</button></div>
  <div class="grid g2">
    <div class="card card-pad stack">
      <div class="field"><label>Assistant name</label><input class="input" value="Ava"></div>
      <div class="field"><label>Greeting</label><input class="input" value="Hi, you’ve reached Keyhan’s line. I’m Ava, his assistant — how can I help?"><span class="hint">Pre-recorded so the caller hears it instantly.</span></div>
      <div class="field"><label>Instructions</label><textarea class="input" rows="7">You answer calls for Keyhan. Be warm and brief. Book viewings using the calendar. Never share his personal address or schedule details beyond free slots. If the caller is upset or asks for Keyhan directly, offer to transfer.</textarea></div>
      <div class="grid g2">
        <div class="field"><label>Language</label><select class="input"><option>English (UK)</option><option>Auto-detect</option><option>فارسی</option><option>Español</option></select></div>
        <div class="field"><label>Voice</label><select class="input"><option>Kokoro · Bella</option><option>Piper · Amy</option></select></div>
      </div>
    </div>
    <div class="stack">
      <div class="card">
        <div class="card-head"><h2>Call flow</h2><div class="right">${btn('Add step', 'sm', 'plus')}</div></div>
        ${[['Ring', 'Ring my devices for 3 rings (VIPs: 5 rings)'], ['Greet', 'Play greeting clip'], ['Identify', 'Match caller to contacts'], ['Converse', 'Answer using Knowledge + Skills'], ['Escalate', 'Transfer to me if caller says “urgent”'], ['Wrap up', 'Summarise, save, notify my phone']].map((s, i) =>
          `<div class="tile"><span class="mono small muted" style="width:18px">${i + 1}</span><div style="flex:1"><b>${s[0]}</b><div class="small muted">${s[1]}</div></div>${tog(true)}</div>`).join('')}
      </div>
      <div class="card card-pad"><h3>Interruptions</h3>
        <div class="row between" style="margin-top:8px"><span class="small">Caller can interrupt the AI</span>${tog(true)}</div>
        <div class="row between" style="margin-top:8px"><span class="small">Ignore short “mm-hm”s</span>${tog(true)}</div>
        <div class="field" style="margin-top:10px"><label>Wait before replying</label><input type="range" min="0" max="100" value="35"><span class="hint">Shorter feels snappier; longer avoids talking over slow speakers.</span></div>
      </div>
    </div>
  </div>`;

P.knowledge = () => `
  ${head('Knowledge', 'Documents your assistant can look up during calls. Indexed and searched on this computer.', btn('Add website', '', 'plus') + btn('Upload files', 'primary', 'upload'))}
  <div class="grid g4" style="margin-bottom:16px">
    <div class="card card-pad"><div class="eyebrow">Sources</div><div class="stat">5</div></div>
    <div class="card card-pad"><div class="eyebrow">Passages</div><div class="stat">2,418</div></div>
    <div class="card card-pad"><div class="eyebrow">Index size</div><div class="stat">38<small>MB</small></div></div>
    <div class="card card-pad"><div class="eyebrow">Embedding model</div><div style="font-weight:600;margin-top:6px">nomic-embed-text</div><div class="small muted">Local · Ollama</div></div>
  </div>
  <div class="card"><table>
    <thead><tr><th>Source</th><th>Type</th><th>Who can hear it</th><th>Status</th><th></th></tr></thead>
    <tbody>
      <tr><td><b>Property listings</b><div class="small muted">listings-oct.pdf · 42 pages</div></td><td>PDF</td><td>${badge('All callers')}</td><td>${badge(lamp('on') + 'Indexed', 'green')}</td><td>${btn('Re-index', 'sm ghost')}</td></tr>
      <tr><td><b>FAQ</b><div class="small muted">faq.md</div></td><td>Markdown</td><td>${badge('All callers')}</td><td>${badge(lamp('on') + 'Indexed', 'green')}</td><td>${btn('Re-index', 'sm ghost')}</td></tr>
      <tr><td><b>Price list</b><div class="small muted">prices.xlsx</div></td><td>Sheet</td><td>${badge('Contacts only', 'blue')}</td><td>${badge(lamp('on') + 'Indexed', 'green')}</td><td>${btn('Re-index', 'sm ghost')}</td></tr>
      <tr><td><b>example-lettings.co.uk</b><div class="small muted">36 pages crawled</div></td><td>Website</td><td>${badge('All callers')}</td><td>${badge(lamp('ring') + 'Indexing 64%', 'amber')}</td><td></td></tr>
      <tr><td><b>Private notes</b><div class="small muted">notes/</div></td><td>Folder</td><td>${badge('Me only', 'red')}</td><td>${badge(lamp('on') + 'Indexed', 'green')}</td><td>${btn('Re-index', 'sm ghost')}</td></tr>
    </tbody></table></div>
  <div class="card card-pad" style="margin-top:16px">
    <h3>Try a question</h3>
    <div class="row" style="margin-top:8px"><input class="input" value="Is there parking at the Elm Street flat?">${btn('Search', 'primary', 'search')}</div>
    <div class="small" style="margin-top:10px;padding:10px 12px;background:var(--canvas);border-radius:6px">“…Elm Street, 2 bed, allocated parking space at rear…” <span class="muted mono">— listings-oct.pdf p.14 · 0.82</span></div>
  </div>`;

P.tools = () => `
  ${head('Tools (MCP)', 'Connect MCP servers so the assistant can check calendars, look up orders or send texts. Anything that changes data asks you first.', btn('Browse catalog', '') + btn('Add MCP server', 'primary', 'plus', "modal('mcp')"))}
  <div class="card">
    ${[['Google Calendar', 'gcal', 'stdio · npx @mcp/google-calendar', '4 tools', 'on', 'Ask before writing'], ['Local files', 'fs', 'stdio · built-in', '3 tools', 'on', 'Read only'], ['SMS (via Twilio)', 'sms', 'built-in', '1 tool', 'on', 'Ask before sending'], ['Shop orders', 'shop', 'http · http://localhost:8790/mcp', '6 tools', 'err', 'Can’t connect — server not running'], ['Home Assistant', 'ha', 'http · http://homeassistant.local:8123/mcp', '12 tools', 'off', 'Disabled']].map(t => `
      <div class="tile"><div class="logo">${ic('plug', 18)}</div>
        <div style="flex:1"><div class="row"><b>${t[0]}</b>${badge(t[3])}</div><div class="small muted mono">${t[2]}</div><div class="small ${t[4] === 'err' ? '' : 'muted'}" style="${t[4] === 'err' ? 'color:var(--red)' : ''}">${t[5]}</div></div>
        <div class="row">${lamp(t[4])}${btn('Configure', 'sm')}${tog(t[4] !== 'off')}</div></div>`).join('')}
  </div>
  <div class="card" style="margin-top:16px">
    <div class="card-head"><h2>Google Calendar · tools</h2><div class="right small muted">Per-tool permission</div></div>
    <table><thead><tr><th>Tool</th><th>What it does</th><th>Callers</th><th>Permission</th></tr></thead><tbody>
      <tr><td class="mono">find_free_slots</td><td class="small">Lists open times</td><td>${badge('All')}</td><td><select class="input" style="width:170px;height:30px"><option>Allow</option></select></td></tr>
      <tr><td class="mono">create_event</td><td class="small">Books a meeting</td><td>${badge('Contacts', 'blue')}</td><td><select class="input" style="width:170px;height:30px"><option>Ask me every time</option></select></td></tr>
      <tr><td class="mono">list_events</td><td class="small">Reads your schedule</td><td>${badge('Me only', 'red')}</td><td><select class="input" style="width:170px;height:30px"><option>Allow</option></select></td></tr>
      <tr><td class="mono">delete_event</td><td class="small">Removes a meeting</td><td>—</td><td><select class="input" style="width:170px;height:30px"><option>Never</option></select></td></tr>
    </tbody></table>
  </div>`;

P.skills = () => `
  ${head('Skills', 'Ready-made behaviours you switch on. Each skill is a folder with instructions and optional tools — write your own or import one.', btn('Import skill', '', 'upload') + btn('New skill', 'primary', 'plus'))}
  <div class="grid g3">
    ${[['Take a message', 'Collects name, number and reason; texts you a summary.', true], ['Book appointments', 'Uses your calendar to offer and book slots.', true], ['Answer FAQs', 'Answers from Knowledge; says so when it doesn’t know.', true], ['Transfer to me', 'Rings your paired phone and bridges the caller.', true], ['Screen unknown callers', 'Asks who’s calling and why before deciding.', true], ['Restaurant orders', 'Takes takeaway orders from your menu file.', false], ['Delivery drivers', 'Gives safe-place instructions for parcels.', false], ['Spam deflector', 'Ends sales calls politely in under 20 seconds.', true], ['Voicemail', 'Records a message when nothing else applies.', true]].map(s => `
      <div class="card card-pad"><div class="row between"><div class="logo">${ic('spark', 18)}</div>${tog(s[2])}</div>
      <h3 style="margin-top:12px">${s[0]}</h3><p class="small muted" style="margin:4px 0 10px">${s[1]}</p>${btn('Edit', 'sm')}</div>`).join('')}
  </div>`;

P.models = () => `
  ${head('Language models', 'Pick the engine that runs models and the model that does the thinking. Sizes are checked against this computer.', btn('Add model file', '', 'upload') + btn('Browse catalog', 'primary', 'search'))}
  <h2 style="margin-bottom:10px">Runtime</h2>
  <div class="grid g4" style="margin-bottom:22px">
    ${[['Ollama', 'v0.12 · running · port 11434', 'on', 'sel', 'Stop'], ['llama.cpp', 'Built in · ready', 'off', '', 'Use'], ['LM Studio', 'Not installed', 'off', '', 'Install'], ['vLLM', 'Needs NVIDIA GPU + Linux', 'off', '', 'Unavailable']].map(r => `
      <div class="card card-pad pick ${r[3]}"><div class="row between"><b>${r[0]}</b>${lamp(r[2])}</div><div class="small muted" style="margin:4px 0 12px">${r[1]}</div>
      ${btn(r[4], r[4] === 'Install' ? 'primary sm' : 'sm', r[4] === 'Install' ? 'dl' : '', r[4] === 'Install' ? "modal('install')" : '')}</div>`).join('')}
  </div>
  <div class="card" style="margin-bottom:16px">
    <div class="card-head"><h2>Loaded now</h2><div class="right small muted">Memory: <span class="mono">5.6 / 32 GB</span></div></div>
    <div class="tile"><div class="logo">Q</div><div style="flex:1"><div class="row"><b>Qwen3 8B</b>${badge('Q4_K_M')}${badge('Default for calls', 'amber')}</div>
      <div class="small muted mono">GPU (Metal) · 41 tok/s · first token 160 ms · context 8k</div><div style="margin-top:8px;max-width:360px">${meter(18, 'green')}</div></div>
      <div class="row">${btn('Unload', 'sm', 'stop', "toast('Qwen3 8B unloaded. 5.6 GB freed.')")}${btn('Test', 'sm')}</div></div>
  </div>
  <div class="card">
    <div class="card-head"><h2>Catalog</h2><div class="right"><div class="seg"><button class="on">Fits this computer</button><button>All</button><button>Downloaded</button></div></div></div>
    <table><thead><tr><th>Model</th><th>Size</th><th>Fit</th><th>Notes</th><th></th></tr></thead><tbody>
      ${MODELS.map(m => `<tr><td><b>${m[0]}</b> <span class="small muted mono">${m[1]}</span></td><td class="mono small">${m[2]}</td><td>${badge(m[3], m[4])}</td><td class="small muted">${m[6]}</td>
      <td style="text-align:right">${m[5] ? btn('Loaded', 'sm green') : m[4] === 'red' ? `<button class="btn sm" disabled>Download</button>` : btn('Download', 'sm', 'dl', `toast('Downloading ${m[0]} · ${m[2]}')`)}</td></tr>`).join('')}
    </tbody></table>
  </div>`;

P.speech = () => `
  ${head('Voice & hearing', 'Hearing turns the caller’s speech into text. Voice speaks the reply. Both run locally.', btn('Run latency test', 'primary', 'play', "toast('Test: hearing 210 ms · voice 95 ms')"))}
  <div class="tabs"><button class="on">Hearing (speech-to-text)</button><button>Voice (text-to-speech)</button><button>Turn detection</button></div>
  <div class="grid g2">
    <div class="card">
      <div class="card-head"><h2>Hearing engines</h2></div>
      ${[['Whisper large-v3-turbo', 'whisper.cpp · 1.6 GB · 99 languages', 'Loaded', 'green'], ['Parakeet TDT 0.6B v3', 'NVIDIA NeMo · 25 EU languages · fastest', 'Download', ''], ['Whisper small', 'whisper.cpp · 466 MB · low-end machines', 'Downloaded', 'blue'], ['Vosk small', '50 MB · Raspberry Pi', 'Download', '']].map(e => `
        <div class="tile"><div class="logo">${ic('mic', 18)}</div><div style="flex:1"><b>${e[0]}</b><div class="small muted">${e[1]}</div></div>
        ${e[2] === 'Loaded' ? badge(lamp('on') + 'Loaded', 'green') + btn('Unload', 'sm') : e[2] === 'Downloaded' ? btn('Load', 'sm') : btn('Download', 'sm', 'dl')}</div>`).join('')}
    </div>
    <div class="card">
      <div class="card-head"><h2>Voices</h2><div class="right"><select class="input" style="height:30px;width:140px"><option>English</option><option>Persian</option><option>All</option></select></div></div>
      ${[['Bella', 'Kokoro 82M · warm, UK', true], ['Adam', 'Kokoro 82M · calm, US', false], ['Amy', 'Piper medium · clear, UK', false], ['Amir', 'Piper medium · Persian', false]].map(v => `
        <div class="tile"><button class="btn sm" onclick="toast('Playing sample: ${v[0]}')">${ic('play')}</button><div style="flex:1"><b>${v[0]}</b><div class="small muted">${v[1]}</div></div>
        ${v[2] ? badge('In use', 'amber') : btn('Use', 'sm')}</div>`).join('')}
      <div class="card-pad" style="border-top:1px solid var(--line)"><div class="field"><label>Hear any sentence</label><div class="row"><input class="input" value="Thursday at 2pm works perfectly."><button class="btn primary" onclick="toast('Speaking…')">${ic('play')}Speak</button></div></div></div>
    </div>
  </div>`;

P.hardware = () => `
  ${head('This computer', 'What LocalAILine found, and what it recommends.', btn('Scan again', '', '', "toast('Scanned. No changes.')"))}
  <div class="grid g4" style="margin-bottom:16px">
    <div class="card card-pad"><div class="eyebrow">Processor</div><div style="font-weight:600;margin-top:6px">Apple M3 Pro</div><div class="small muted">12 cores</div></div>
    <div class="card card-pad"><div class="eyebrow">Memory</div><div style="font-weight:600;margin-top:6px">32 GB unified</div>${meter(36)}</div>
    <div class="card card-pad"><div class="eyebrow">Graphics</div><div style="font-weight:600;margin-top:6px">18-core GPU · Metal</div><div class="small muted">Shared with memory</div></div>
    <div class="card card-pad"><div class="eyebrow">Free disk</div><div style="font-weight:600;margin-top:6px">212 GB</div>${meter(58)}</div>
  </div>
  <div class="card card-pad" style="margin-bottom:16px">
    <div class="row between"><div><div class="eyebrow">Recommended setup</div><h2 style="margin-top:4px">Balanced — natural conversation, under half a second</h2></div>${btn('Apply', 'primary')}</div>
    <div class="grid g3" style="margin-top:14px">
      <div><div class="small muted">Thinking</div><b>Qwen3 8B · Q4</b> <span class="small muted mono">5.2 GB</span></div>
      <div><div class="small muted">Hearing</div><b>Whisper large-v3-turbo</b> <span class="small muted mono">1.6 GB</span></div>
      <div><div class="small muted">Voice</div><b>Kokoro 82M</b> <span class="small muted mono">0.3 GB</span></div>
    </div>
  </div>
  <div class="grid g3">
    ${[['Light', 'Any laptop · 8 GB', 'Qwen3 1.7B · Whisper small · Piper', '~0.7 s'], ['Balanced', '16–32 GB or 8 GB GPU', 'Qwen3 8B · Whisper turbo · Kokoro', '~0.5 s'], ['Power', '24 GB+ NVIDIA GPU', 'Mistral Small 24B · Parakeet · Kokoro', '~0.4 s']].map((t, i) => `
      <div class="card card-pad pick ${i === 1 ? 'sel' : ''}"><div class="row between"><h3>${t[0]}</h3><span class="mono small">${t[3]}</span></div><div class="small muted">${t[1]}</div><div class="small" style="margin-top:8px">${t[2]}</div></div>`).join('')}
  </div>`;

P.lines = () => `
  ${head('Phone lines', 'Connect a phone number from a provider, or plug in a landline. Incoming calls on any line go to your assistant.', btn('Add phone line', 'primary', 'plus', "modal('line')"))}
  <div class="card" style="margin-bottom:16px">
    ${[['Tw', '#f22f46', 'Twilio', '+44 20 3870 1142 · SIP trunk', 'on', 'Connected · last call 10:42'], ['☎', '', 'Home landline', 'Grandstream HT813 · 192.168.1.40 · FXO', 'on', 'Registered · line voltage OK'], ['Tx', '#00c08b', 'Telnyx', '+1 415 555 0199', 'err', 'Credentials rejected (401). Check the SIP password.']].map(l => `
      <div class="tile"><div class="logo" style="color:${l[1]}">${l[0]}</div>
      <div style="flex:1"><b>${l[2]}</b><div class="small muted mono">${l[3]}</div><div class="small" style="${l[4] === 'err' ? 'color:var(--red)' : 'color:var(--muted)'}">${l[5]}</div></div>
      <div class="row">${lamp(l[4])}${btn('Test call', 'sm', 'phone', 'ring()')}${btn('Edit', 'sm')}</div></div>`).join('')}
  </div>
  <h2 style="margin-bottom:10px">Supported</h2>
  <div class="grid g4">
    ${[['Twilio', 'Elastic SIP trunk'], ['Telnyx', 'SIP connection'], ['Vonage', 'SIP trunk'], ['Plivo', 'Zentrunk'], ['Any SIP provider', 'Username + password'], ['Landline (FXO box)', 'Grandstream HT813, Obihai'], ['USB phone modem', 'Basic, no hold music'], ['Forward my mobile', 'Conditional call forwarding']].map(p => `
      <div class="card card-pad pick" onclick="modal('line')"><b>${p[0]}</b><div class="small muted">${p[1]}</div></div>`).join('')}
  </div>`;

P.voiceserver = () => `
  ${head('Voice server', 'The built-in LiveKit server that connects phone calls, your browser and your paired phone to the assistant.', btn('View config', '') + btn('Restart', 'primary'))}
  <div class="grid g4" style="margin-bottom:16px">
    ${[['LiveKit server', 'v1.13 · :7880', 'on'], ['LiveKit SIP', ':5060 · trunks & landline', 'on'], ['Line registrar', '2 lines registered', 'on'], ['Agent worker', '1 call running', 'on']].map(s => `
      <div class="card card-pad"><div class="row between"><b>${s[0]}</b>${lamp(s[2])}</div><div class="small muted mono">${s[1]}</div></div>`).join('')}
  </div>
  <div class="grid g2">
    <div class="card"><div class="card-head"><h2>Rooms</h2></div><table><thead><tr><th>Room</th><th>Who</th><th>Since</th></tr></thead><tbody>
      <tr><td class="mono small">pstn-in-7f3a</td><td class="small">Caller · AI</td><td class="mono small">01:47</td></tr>
      <tr><td class="mono small">desk-keyhan</td><td class="small">Keyhan (browser)</td><td class="mono small">idle</td></tr></tbody></table></div>
    <div class="card"><div class="card-head"><h2>Routing</h2></div><table><thead><tr><th>Line</th><th>Goes to</th></tr></thead><tbody>
      <tr><td class="small">Twilio trunk</td><td class="small">Room <span class="mono">pstn-in-*</span> → Ava</td></tr>
      <tr><td class="small">Home landline</td><td class="small">Room <span class="mono">pstn-in-*</span> → Ava</td></tr></tbody></table></div>
  </div>
  <div class="card card-pad" style="margin-top:16px">
    <div class="row between" style="margin-bottom:10px"><h3>Network</h3><span class="small muted">Phone providers need to reach this computer.</span></div>
    <div class="grid g3">
      <div class="card card-pad pick sel"><b>Register with provider</b><div class="small muted">Works behind home routers. No ports to open. Telnyx, Twilio SIP Domains, most SIP providers.</div></div>
      <div class="card card-pad pick"><b>Open ports on my router</b><div class="small muted">UDP 5060 and 10000–20000. Firewall rules added for you.</div></div>
      <div class="card card-pad pick"><b>Media stream over tunnel</b><div class="small muted">Twilio/Telnyx audio over a secure websocket. Cloudflare Tunnel or Tailscale Funnel.</div></div>
    </div>
  </div>
  <div class="code" style="margin-top:16px"><span class="dim">10:42:01</span> <span class="ok">INFO</span>  sip  INVITE from +447700900123 via twilio-trunk
<span class="dim">10:42:01</span> <span class="ok">INFO</span>  room created pstn-in-7f3a
<span class="dim">10:42:02</span> <span class="ok">INFO</span>  agent ava joined (dispatch: inbound)
<span class="dim">10:42:02</span> <span class="ok">INFO</span>  greeting clip played (first audio 640 ms)
<span class="dim">10:42:31</span> <span class="warn">WARN</span>  blocked INVITE from 185.243.x.x (not in provider allow-list)</div>`;

P.devices = () => `
  ${head('Paired devices', 'Use your phone or another computer to get ring alerts, listen in and take over calls — from anywhere on your network.', btn('Pair a device', 'primary', 'qr', "modal('pair')"))}
  <div class="card">
    ${[['Keyhan’s iPhone', 'iOS app · last seen 2 min ago', 'on'], ['Pixel 8', 'Android app · last seen yesterday', 'off'], ['Office PC', 'Windows · browser', 'on']].map(d => `
      <div class="tile"><div class="logo">${ic('device', 18)}</div><div style="flex:1"><b>${d[0]}</b><div class="small muted">${d[1]}</div></div>
      <div class="row">${lamp(d[2])}<span class="small">Ring me</span>${tog(true)}${btn('Remove', 'sm ghost')}</div></div>`).join('')}
  </div>`;

P.users = () => `
  ${head('Users & access', 'Everyone who can sign in to this LocalAILine, and what they can do.', btn('Invite user', 'primary', 'plus', "modal('user')"))}
  <div class="tabs"><button class="on">Users</button><button>Roles</button><button>Sessions</button></div>
  <div class="card" style="margin-bottom:16px"><table>
    <thead><tr><th>User</th><th>Role</th><th>Lines</th><th>Two-step sign-in</th><th>Last active</th><th></th></tr></thead><tbody>
      <tr><td><div class="row"><span class="avatar">KA</span><div><b>Keyhan Azarjoo</b><div class="small muted">keyhan@local</div></div></div></td><td>${badge('Owner', 'amber')}</td><td class="small">All</td><td>${badge('On', 'green')}</td><td class="small muted">Now</td><td></td></tr>
      <tr><td><div class="row"><span class="avatar" style="background:#cfe0f3">MR</span><div><b>Maya Rahimi</b><div class="small muted">maya@local</div></div></div></td><td>${badge('Operator', 'blue')}</td><td class="small">Twilio</td><td>${badge('On', 'green')}</td><td class="small muted">2 h ago</td><td>${btn('Edit', 'sm ghost')}</td></tr>
      <tr><td><div class="row"><span class="avatar" style="background:#e3f6ec">TB</span><div><b>Tom Brennan</b><div class="small muted">tom@local</div></div></div></td><td>${badge('Viewer')}</td><td class="small">Landline</td><td>${badge('Off', 'red')}</td><td class="small muted">5 days ago</td><td>${btn('Edit', 'sm ghost')}</td></tr>
    </tbody></table></div>
  <div class="card"><div class="card-head"><h2>What each role can do</h2></div><table>
    <thead><tr><th>Permission</th><th>Owner</th><th>Admin</th><th>Operator</th><th>Viewer</th></tr></thead><tbody>
      ${[['See calls & transcripts', 1, 1, 1, 1], ['Take over live calls', 1, 1, 1, 0], ['Approve AI actions', 1, 1, 1, 0], ['Edit persona, skills & knowledge', 1, 1, 0, 0], ['Manage models & phone lines', 1, 1, 0, 0], ['Manage users', 1, 0, 0, 0]].map(r => `
        <tr><td class="small">${r[0]}</td>${r.slice(1).map(v => `<td>${v ? `<span style="color:var(--green)">${ic('check', 16)}</span>` : '<span class="muted">—</span>'}</td>`).join('')}</tr>`).join('')}
    </tbody></table></div>`;

P.logs = () => `
  ${head('Activity & logs', 'Who changed what, and what the system is doing.', btn('Export', '', 'dl'))}
  <div class="tabs"><button class="on">Audit trail</button><button>System</button><button>Errors</button></div>
  <div class="card"><table><thead><tr><th>When</th><th>Who</th><th>What</th></tr></thead><tbody>
    ${[['10:44', 'Keyhan', 'Approved calendar.create_event during call with Sarah Mitchell'], ['10:20', 'Maya', 'Signed in from Office PC'], ['09:58', 'System', 'Loaded Qwen3 8B (5.2 GB) in 3.1 s'], ['09:57', 'System', 'LocalAILine started · all services healthy'], ['Yesterday', 'Keyhan', 'Changed answering mode to “After 3 rings”'], ['Yesterday', 'Keyhan', 'Added phone line Telnyx']].map(r => `
      <tr><td class="mono small muted">${r[0]}</td><td class="small"><b>${r[1]}</b></td><td class="small">${r[2]}</td></tr>`).join('')}
  </tbody></table></div>`;

P.settings = () => `
  ${head('Settings', '', btn('Save changes', 'primary'))}
  <div class="tabs"><button class="on">General</button><button>Privacy & storage</button><button>Backups</button><button>Notifications</button><button>Updates</button><button>About</button></div>
  <div class="grid g2">
    <div class="card card-pad stack">
      <h3>General</h3>
      <div class="field"><label>Computer name</label><input class="input" value="Keyhan’s MacBook"></div>
      <div class="row between"><span>Start LocalAILine when I sign in</span>${tog(true)}</div>
      <div class="row between"><span>Keep running when the window is closed</span>${tog(true)}</div>
      <div class="row between"><span>Stop my computer sleeping while lines are active</span>${tog(true)}</div>
      <div class="row between"><span>Dark appearance</span><label class="toggle"><input type="checkbox" onchange="theme()" ${document.documentElement.dataset.theme === 'dark' ? 'checked' : ''}><span></span></label></div>
    </div>
    <div class="card card-pad stack">
      <h3>Privacy & storage</h3>
      <div class="field"><label>Keep recordings for</label><select class="input"><option>30 days</option><option>7 days</option><option>Forever</option><option>Don’t record</option></select></div>
      <div class="row between"><span>Tell callers the call is recorded</span>${tog(true)}</div>
      <div class="row between"><span>Encrypt database and recordings</span>${tog(true)}</div>
      <dl class="kv small"><dt>Data folder</dt><dd class="mono">~/LocalAILine</dd><dt>Database</dt><dd class="mono">localline.db · 48 MB</dd><dt>Recordings</dt><dd class="mono">1.2 GB</dd></dl>
    </div>
    <div class="card card-pad stack">
      <h3>Backups</h3>
      <div class="row between"><span>Daily backup to a folder</span>${tog(true)}</div>
      <div class="row">${btn('Back up now', '', 'dl')}${btn('Restore…', '')}</div>
    </div>
    <div class="card card-pad stack">
      <h3>About</h3>
      <dl class="kv small"><dt>Version</dt><dd class="mono">0.1.0-demo</dd><dt>License</dt><dd>Apache-2.0</dd><dt>Source</dt><dd class="mono">github.com/keyhan-azarjoo/LocalAILine</dd></dl>
      <div class="row">${btn('Check for updates', '')}</div>
    </div>
  </div>`;


P.outbound = () => `
  ${head('Make a call', 'Tell your assistant who to call and what to achieve. It calls from your number, introduces itself as your AI assistant, and reports back.', btn('Import call list', '', 'upload'))}
  <div class="card card-pad" style="margin-bottom:16px">
    <div class="eyebrow">Just ask</div>
    <div class="row" style="margin-top:8px">
      <input class="input" style="height:44px;font-size:15px" value="Call Riverside Dental and move my check-up to next week, any morning except Wednesday.">
      <button class="btn primary lg" onclick="toast('Call task drafted — check the details below')">${ic('out')}Draft call</button>
      <button class="btn lg" title="Say it" onclick="toast('Listening…')">${ic('mic')}</button>
    </div>
    <div class="small muted" style="margin-top:8px">Or fill in the details yourself. Nothing is dialled until you press Start call.</div>
  </div>
  <div class="grid g3">
    <div class="card span2">
      <div class="card-head"><h2>Call task</h2><div class="right">${badge('Draft', 'amber')}</div></div>
      <div class="card-pad stack">
        <div class="grid g2">
          <div class="field"><label>Who to call</label><input class="input" value="Riverside Dental · +44 20 7946 0011"><span class="hint">A contact, a number, or a list for several calls.</span></div>
          <div class="field"><label>Call from</label><select class="input"><option>Twilio · +44 20 3870 1142</option><option>Home landline</option></select></div>
        </div>
        <div class="field"><label>Goal</label><textarea class="input" rows="3">Move my dental check-up (currently Thu 9 Oct, 09:30) to next week. Any morning except Wednesday.</textarea></div>
        ${advanced ? `        <div class="grid g2">
          <div class="field"><label>Must find out</label>
            <div class="row wrap">${['New date & time', 'Any cancellation fee', 'Name of person spoken to'].map(x => badge(x, 'blue')).join('')}<button class="btn sm ghost">${ic('plus')}Add</button></div></div>
          <div class="field"><label>Allowed to share</label>
            <div class="row wrap">${['My full name', 'Date of birth', 'Patient number'].map(x => badge(x)).join('')}<button class="btn sm ghost">${ic('plus')}Add</button></div><span class="hint">Anything not listed stays private.</span></div>
        </div>
        <div class="grid g3">
          <div class="field"><label>Agent</label><select class="input"><option>Max · Outbound caller</option><option>Ava · Receptionist</option></select></div>
          <div class="field"><label>Language</label><select class="input"><option>English (UK)</option><option>فارسی</option></select></div>
          <div class="field"><label>Max call length</label><select class="input"><option>5 minutes</option><option>10 minutes</option></select></div>
        </div>
        <div class="grid g3">
          <div class="field"><label>When</label><select class="input"><option>Now</option><option>Schedule…</option><option>Next business hours</option></select></div>
          <div class="field"><label>If no answer</label><select class="input"><option>Retry 2× every 30 min</option><option>Leave a voicemail</option><option>Give up</option></select></div>
          <div class="field"><label>If they need a decision</label><select class="input"><option>Ask me live (ring my phone)</option><option>Say I’ll call back</option></select></div>
        </div>
` : `<button class="btn sm ghost" style="align-self:flex-start" onclick="setAdvanced(true)">More options (what to find out, retries, schedule…)</button>`}
      </div>
      <div class="modal-foot" style="justify-content:space-between">
        <span class="small muted">${ic('shield', 14)} Opens with “Hi, I’m Keyhan’s AI assistant calling on his behalf.” Recorded with notice.</span>
        <div class="row">${btn('Preview conversation', '', '', "modal('script')")}${btn('Schedule', '')}${btn('Start call', 'amber', 'out', "toast('Dialling Riverside Dental…');go('live')")}</div>
      </div>
    </div>
    <div class="stack">
      <div class="card card-pad"><h3>Calling rules</h3>
        <div class="row between" style="margin-top:8px"><span class="small">Only call 09:00–20:00 local time</span>${tog(true)}</div>
        <div class="row between" style="margin-top:8px"><span class="small">Hang up if voicemail and none allowed</span>${tog(true)}</div>
        <div class="row between" style="margin-top:8px"><span class="small">Never call numbers on my do-not-call list</span>${tog(true)}</div>
        <div class="row between" style="margin-top:8px"><span class="small">Daily limit</span><span class="mono small">20 calls</span></div>
        <div class="row between" style="margin-top:8px"><span class="small">Spend limit (provider)</span><span class="mono small">£5 / day</span></div>
      </div>
      <div class="card card-pad"><h3>Last result</h3>
        <div class="row" style="margin-top:8px">${badge(lamp('on') + 'Goal met', 'green')}<span class="small muted mono">11:05 · 2m 40s</span></div>
        <dl class="kv small" style="margin-top:10px"><dt>New time</dt><dd>Tue 14 Oct, 10:00</dd><dt>Fee</dt><dd>None</dd><dt>Spoke to</dt><dd>Hannah, reception</dd></dl>
        <div class="row" style="margin-top:10px">${btn('Add to calendar', 'sm primary')}${btn('Open call', 'sm', '', "go('call')")}</div>
      </div>
    </div>
  </div>
  <div class="card" style="margin-top:16px">
    <div class="card-head"><h2>Call queue</h2><div class="right"><div class="seg"><button class="on">Active & scheduled</button><button>Finished</button></div></div></div>
    <table><thead><tr><th>Who</th><th>Goal</th><th>Status</th><th>Attempt</th><th>When</th><th></th></tr></thead><tbody>
      <tr><td><b>Greenway Plumbing</b><div class="small muted mono">+44 161 496 0777</div></td><td class="small">Get a quote for a boiler service</td><td>${badge(lamp('ring') + 'On call · 00:52', 'amber')}</td><td class="mono small">1 / 3</td><td class="mono small muted">Now</td><td>${btn('Listen', 'sm', '', "go('live')")}</td></tr>
      <tr><td><b>Council tax office</b><div class="small muted mono">+44 20 7946 0400</div></td><td class="small">Confirm single-person discount was applied</td><td>${badge('No answer · retrying')}</td><td class="mono small">2 / 3</td><td class="mono small muted">14:00</td><td>${btn('Cancel', 'sm ghost')}</td></tr>
      <tr><td><b>Supplier list</b> <span class="small muted">· 3 numbers</span></td><td class="small">Ask today’s price for 20 bags of cement</td><td>${badge('Scheduled', 'blue')}</td><td class="mono small">—</td><td class="mono small muted">Mon 09:30</td><td>${btn('Edit', 'sm ghost')}</td></tr>
    </tbody></table>
  </div>`;

const AGENTS = [
  ['Ava', 'Receptionist', 'Answers all incoming calls, screens strangers, takes messages, books viewings.', 'Incoming · all lines', 'Qwen3 8B', 'Kokoro · Bella', 6, 3, 'on'],
  ['Max', 'Outbound caller', 'Makes calls you ask for: rescheduling, quotes, confirmations. Reports back.', 'Outgoing · Twilio', 'Qwen3 8B', 'Kokoro · Adam', 4, 2, 'on'],
  ['Sam', 'Support', 'Handles existing customers: orders, invoices, troubleshooting from Knowledge.', 'Hand-off from Ava', 'Gemma 3 12B', 'Kokoro · Bella', 3, 2, 'on'],
  ['Copper Kettle orders', 'Order taker', 'Takes takeaway orders from the menu, quotes prices, places the order.', 'Hand-off from Ava', 'Qwen3 8B', 'Piper · Amy', 2, 1, 'off'],
];
P.agents = () => `
  ${head('Agents', 'Each agent has its own voice, instructions, skills and tools. Agents can hand a call to each other or to you.', btn('Import agent', '', 'upload') + btn('New agent', 'primary', 'plus', "modal('agent')"))}
  <div class="grid g2" style="margin-bottom:16px">
    ${AGENTS.map(a => `<div class="card">
      <div class="card-pad"><div class="row between"><div class="row"><div class="logo">${ic('bot', 18)}</div><div><h3>${a[0]}</h3><div class="small muted">${a[1]}</div></div></div><div class="row">${lamp(a[8])}${tog(a[8] === 'on')}</div></div>
      <p class="small" style="margin:12px 0">${a[2]}</p>
      <dl class="kv small"><dt>Handles</dt><dd>${a[3]}</dd><dt>Thinks with</dt><dd>${a[4]}</dd><dt>Voice</dt><dd>${a[5]}</dd><dt>Skills · tools</dt><dd>${a[6]} skills · ${a[7]} MCP servers</dd></dl></div>
      <div class="modal-foot" style="justify-content:flex-start">${btn('Edit', 'sm primary', '', "go('assistant')")}${btn('Test call', 'sm', 'phone', 'ring()')}${btn('Duplicate', 'sm ghost')}</div></div>`).join('')}
  </div>
  <div class="card card-pad">
    <div class="row between" style="margin-bottom:12px"><h2>Hand-offs</h2><span class="small muted">Who passes a call to whom, and when.</span></div>
    <div class="callpath">
      <div class="jack"><div class="eyebrow">${lamp('on')}Incoming</div><div class="name">Any line</div></div><div class="cord idle"></div>
      <div class="jack hot"><div class="eyebrow">${lamp('ring')}Agent</div><div class="name">Ava · Receptionist</div><div class="ms">greets & routes</div></div><div class="cord idle"></div>
      <div class="jack"><div class="eyebrow">${lamp('on')}If “order”</div><div class="name">Copper Kettle orders</div></div><div class="cord idle"></div>
      <div class="jack"><div class="eyebrow">${lamp('on')}If customer</div><div class="name">Sam · Support</div></div><div class="cord idle"></div>
      <div class="jack"><div class="eyebrow">${lamp('on')}If “urgent”</div><div class="name">Transfer to you</div><div class="ms">rings paired phone</div></div>
    </div>
  </div>`;

const AUTOS = [
  ['Morning briefing', 'Every day 08:00', 'Summarise yesterday’s calls → send to my phone', 'on', 'Today 08:00 · done'],
  ['Call back missed messages', 'After a call ends with “Message taken”', 'Wait 2 h → if I haven’t called back, Max calls them → repeat until reached (max 3)', 'on', 'Today 10:51 · waiting'],
  ['Appointment reminders', 'Every weekday 17:00', 'For each calendar event tomorrow → call the guest → confirm or reschedule → update calendar', 'on', 'Yesterday · 4 calls'],
  ['Supplier price check', 'Every Monday 09:30', 'For each supplier in list → ask price of item → compare → text me the cheapest', 'on', 'Mon · 3 calls'],
  ['Spam learning', 'After a call ends with “Screened”', 'If caller was sales → add number to block list', 'off', '—'],
];
P.automations = () => `
  ${head('Automations & loops', 'Tasks your agents run on their own: on a schedule, after a call, or in a loop until a goal is met. Every step is logged.', btn('Templates', '') + btn('New automation', 'primary', 'plus'))}
  <div class="card" style="margin-bottom:16px"><table>
    <thead><tr><th>Automation</th><th>Starts</th><th>Does</th><th>Last run</th><th></th></tr></thead><tbody>
    ${AUTOS.map((a, i) => `<tr class="click"><td><div class="row">${lamp(a[3])}<b>${a[0]}</b></div></td><td class="small">${a[1]}</td><td class="small muted">${a[2]}</td><td class="small mono muted">${a[4]}</td><td>${tog(a[3] === 'on')}</td></tr>`).join('')}
    </tbody></table></div>
  <div class="grid g3">
    <div class="card span2">
      <div class="card-head"><h2>Appointment reminders</h2><div class="right">${btn('Run now', 'sm', 'play', "toast('Run started — 4 calls queued')")}${btn('Save', 'sm primary')}</div></div>
      <div class="card-pad">
        ${[
          ['Trigger', 'clock', 'Every weekday at 17:00', ''],
          ['Get', 'tool', 'Google Calendar → events tomorrow with a guest phone number', ''],
          ['Loop', 'loop', 'For each event', 'loop'],
          ['Call', 'call', 'Max calls the guest: “Confirm tomorrow’s appointment, or offer another slot”', 'in'],
          ['Branch', 'if', 'If they want another time → find_free_slots → book → update event', 'in'],
          ['Until', 'until', 'Reached, or 2 attempts 30 min apart', 'in'],
          ['Notify', 'bell', 'Text me: “3 confirmed, 1 moved to Fri 11:00”', ''],
        ].map(s => `<div class="row" style="align-items:flex-start;margin-left:${s[3] === 'in' ? 34 : 0}px;padding:10px 0;border-bottom:1px solid var(--line)">
          <span class="badge ${s[0] === 'Loop' || s[0] === 'Until' ? 'amber' : s[0] === 'Trigger' ? 'blue' : ''}" style="min-width:64px;justify-content:center">${s[0]}</span>
          <span class="small" style="flex:1">${s[2]}</span><button class="btn sm ghost">Edit</button></div>`).join('')}
        <div style="margin-top:12px">${btn('Add step', 'sm', 'plus')}</div>
      </div>
    </div>
    <div class="stack">
      <div class="card card-pad"><h3>Limits</h3>
        <dl class="kv small" style="margin-top:8px"><dt>Max calls per run</dt><dd class="mono">10</dd><dt>Max loop rounds</dt><dd class="mono">3</dd><dt>Stop if spend over</dt><dd class="mono">£2</dd><dt>Needs my approval</dt><dd>Booking changes</dd></dl></div>
      <div class="card"><div class="card-head"><h3>Runs</h3></div>
        ${[['Yesterday 17:00', '4 calls · 3 confirmed · 1 moved', 'green'], ['Fri 17:00', '2 calls · 1 no answer', 'amber'], ['Thu 17:00', 'No events', '']].map(r => `<div class="tile"><div style="flex:1"><div class="mono small">${r[0]}</div><div class="small muted">${r[1]}</div></div>${badge(r[2] === 'green' ? 'Done' : r[2] === 'amber' ? 'Partly' : 'Skipped', r[2])}</div>`).join('')}
      </div>
    </div>
  </div>`;

/* ---------- full-screen pages ---------- */
P.login = () => `
  <div class="full"><div class="full-side">${brand()}<h1>Your computer<br>answers <em>your phone</em>.</h1>
    <p style="margin-top:16px;max-width:300px">Private AI receptionist. Models, calls and recordings stay on this machine.</p></div>
  <div class="full-main" style="display:grid;place-items:center"><div style="width:360px" class="stack">
    <h2 style="font-size:24px">Sign in</h2>
    <div class="field"><label>Username</label><input class="input" value="keyhan"></div>
    <div class="field"><label>Password</label><input class="input" type="password" value="password"></div>
    <div class="field"><label>Code from your authenticator app</label><input class="input mono" placeholder="000 000"></div>
    <button class="btn primary lg" style="width:100%;justify-content:center" onclick="go('home')">Sign in</button>
    <p class="small muted">Forgot your password? Ask the owner of this computer to reset it from Users & access.</p>
    <p class="small"><a href="#/welcome">First time? Set up LocalAILine</a></p>
  </div></div></div>`;

const STEPS = ['Welcome', 'Create your account', 'Set up the AI', 'Connect your phone line', 'Try it'];
let step = 0;
P.welcome = () => `
  <div class="full"><div class="full-side">${brand()}
    <ol class="steps">${STEPS.map((s, i) => `<li class="${i < step ? 'done' : i === step ? 'cur' : ''}"><span class="n">${i < step ? '✓' : i + 1}</span>${s}</li>`).join('')}</ol>
    <p class="small" style="margin-top:auto;color:#6f86a3">Nothing is sent to any server during setup.</p></div>
  <div class="full-main">
    <div class="wizard-step ${step === 0 ? 'on' : ''}"><div class="eyebrow">Setup · about 10 minutes</div><h1 style="font-size:34px;margin:8px 0 12px">Let’s turn this computer into your receptionist.</h1>
      <p class="muted" style="max-width:520px">LocalAILine installs an AI engine, a speech engine and a voice server on this computer, then connects it to your phone number. You can change everything later.</p>
      <div class="grid g3" style="margin:24px 0">${[['Hears', 'Speech-to-text, locally'], ['Thinks', 'A language model you choose'], ['Speaks', 'Natural voices, no cloud']].map(x => `<div class="card card-pad"><b>${x[0]}</b><div class="small muted">${x[1]}</div></div>`).join('')}</div>
      ${wizNav()}</div>
    <div class="wizard-step ${step === 1 ? 'on' : ''}"><h1 style="font-size:28px;margin-bottom:6px">Create the owner account</h1><p class="muted">The owner can add other users and change everything.</p>
      <div class="stack" style="max-width:420px;margin:20px 0"><div class="field"><label>Your name</label><input class="input" value="Keyhan Azarjoo"></div><div class="field"><label>Username</label><input class="input" value="keyhan"></div><div class="field"><label>Password</label><input class="input" type="password" value="xxxxxxxxxx"><span class="hint">At least 10 characters.</span></div><div class="row between"><span>Turn on two-step sign-in</span>${tog(true)}</div></div>${wizNav()}</div>
    <div class="wizard-step ${step === 2 ? 'on' : ''}"><h1 style="font-size:28px;margin-bottom:6px">Setting up the AI for this computer</h1><p class="muted">We checked your computer and picked what runs best. This downloads about 7 GB once.</p>
      <div class="card card-pad" style="margin:20px 0"><div class="row between"><div><div class="eyebrow">Your computer</div><b>Apple M3 Pro · 32 GB memory</b></div>${badge('Great for AI', 'green')}</div></div>
      <div class="card" style="margin-bottom:12px">${[['Thinking', 'Qwen3 8B', '5.2 GB', 72], ['Hearing', 'Whisper turbo', '1.6 GB', 100], ['Voice', 'Kokoro · Bella', '0.3 GB', 100]].map(m => `<div class="tile"><div style="width:90px" class="small muted">${m[0]}</div><div style="flex:1"><b>${m[1]}</b> <span class="mono small muted">${m[2]}</span><div style="margin-top:6px">${meter(m[3], m[3] === 100 ? 'green' : 'amber')}</div></div><span class="mono small">${m[3] === 100 ? 'Ready' : m[3] + '%'}</span></div>`).join('')}</div>
      <p class="small"><a href="#" onclick="toast('Opens engine & model choices');return false">Choose engine and models myself</a></p>${wizNav()}</div>
    <div class="wizard-step ${step === 3 ? 'on' : ''}"><h1 style="font-size:28px;margin-bottom:6px">Connect a phone line</h1><p class="muted">You can add more later, or skip and talk to the assistant from this computer first.</p>
      ${lineForm()}<div style="margin-top:20px">${wizNav('Skip for now')}</div></div>
    <div class="wizard-step ${step === 4 ? 'on' : ''}"><h1 style="font-size:28px;margin-bottom:6px">Make a test call</h1><p class="muted">Call <b class="mono">+44 20 3870 1142</b> from your mobile, or talk right here.</p>
      <div class="card card-pad" style="margin:20px 0"><div class="row between"><div class="row">${lamp('ring')}<b>Waiting for a call…</b></div>${wave(30)}</div></div>
      <div class="row">${btn('Talk from this computer', '', 'mic', "go('live')")}${btn('Finish setup', 'primary', 'check', "go('home')")}</div></div>
  </div></div>`;

function wizNav(skip) {
  return `<div class="row">${step ? `<button class="btn" onclick="step--;render()">Back</button>` : ''}${skip ? `<button class="btn ghost" onclick="step++;render()">${skip}</button>` : ''}<button class="btn primary lg" onclick="step++;render()">${step === 0 ? 'Start setup' : 'Continue'}</button></div>`;
}
function lineForm() {
  return `<div class="grid g4" style="margin:18px 0">${['Twilio', 'Telnyx', 'Other SIP', 'Landline box'].map((p, i) => `<div class="card card-pad pick ${i ? '' : 'sel'}" onclick="this.parentNode.querySelectorAll('.pick').forEach(p=>p.classList.remove('sel'));this.classList.add('sel')"><b>${p}</b></div>`).join('')}</div>
    <div class="grid g2"><div class="field"><label>Account SID</label><input class="input mono" value="AC••••••••••••••••••••••••3f1"></div><div class="field"><label>Auth token</label><input class="input mono" type="password" value="xxxxxxxxxxxxxxxx"><span class="hint">Stored encrypted on this computer.</span></div>
    <div class="field"><label>Phone number</label><select class="input mono"><option>+44 20 3870 1142</option><option>+44 161 850 2210</option></select><span class="hint">Found 2 numbers on your account.</span></div>
    <div class="field"><label>Connection</label><select class="input"><option>Automatic (recommended)</option><option>SIP trunk to my public IP</option><option>Tunnel</option></select><span class="hint">LocalAILine creates the SIP trunk on your account for you.</span></div></div>`;
}
function brand() {
  return `<a class="brand" href="#/"><span class="brand-mark"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#f2a93b" stroke-width="2.2" stroke-linecap="round"><path d="M4 12h3l2-6 4 12 2-6h5"/></svg></span><span class="brand-name">Local<b>AI</b>Line</span></a>`;
}

/* ---------- modals ---------- */
const MODALS = {
  agent: ['New agent', `<div class="stack"><div class="field"><label>Start from</label><div class="grid g2">${['Receptionist', 'Outbound caller', 'Support', 'Order taker', 'Appointment setter', 'Blank'].map((t, i) => `<div class="card card-pad pick ${i ? '' : 'sel'}" onclick="this.parentNode.querySelectorAll('.pick').forEach(p=>p.classList.remove('sel'));this.classList.add('sel')"><b>${t}</b></div>`).join('')}</div></div>
    <div class="field"><label>Name</label><input class="input" placeholder="e.g. Nora"></div></div>`, 'Create agent'],
  script: ['Preview conversation', `<p class="small muted" style="margin-top:0">A rehearsal with the AI playing the other side. Nothing is dialled.</p><div class="transcript">
    <div class="turn ai"><div class="who">Max</div><div class="bubble">Hi, I’m Keyhan Azarjoo’s AI assistant calling on his behalf. I’d like to move his check-up on Thursday to next week, please.</div></div>
    <div class="turn"><div class="who">Them</div><div class="bubble">Sure, can I take his date of birth?</div></div>
    <div class="turn ai"><div class="who">Max</div><div class="bubble">Of course — it’s the 4th of March. Do you have any mornings next week, apart from Wednesday?</div></div></div>`, 'Looks good'],
  line: ['Add phone line', `<p class="muted small" style="margin-top:0">Choose where calls come from.</p>${lineForm()}`, 'Connect line'],
  mcp: ['Add MCP server', `<div class="stack"><div class="field"><label>Name</label><input class="input" placeholder="e.g. Shop orders"></div>
    <div class="field"><label>Type</label><div class="seg"><button class="on">Local command</button><button>URL</button></div></div>
    <div class="field"><label>Command</label><input class="input mono" value="npx -y @modelcontextprotocol/server-filesystem ~/Documents"></div>
    <div class="field"><label>Who can use it</label><select class="input"><option>Only me (when I talk to the assistant)</option><option>Known contacts</option><option>All callers</option></select></div></div>`, 'Add and test'],
  install: ['Install LM Studio', `<p class="small muted" style="margin-top:0">LocalAILine will download the official installer (≈ 480 MB) and run it.</p><div class="code">Downloading LM-Studio-0.3.x-arm64.dmg   <span class="warn">38%</span>
<span class="dim">Verifying signature…</span></div>`, 'Install'],
  pair: ['Pair a device', `<div style="display:grid;place-items:center;padding:10px"><div style="width:180px;height:180px;border-radius:10px;background:var(--canvas);display:grid;place-items:center;border:1px solid var(--line)">${ic('qr', 120)}</div>
    <p class="small muted" style="text-align:center">Open LocalAILine on your phone and scan this code.<br>Both devices must be on the same network or tunnel.</p><div class="mono">PAIR-7Q4K-2M9X</div></div>`, 'Done'],
  user: ['Invite user', `<div class="stack"><div class="field"><label>Name</label><input class="input"></div><div class="field"><label>Username</label><input class="input"></div>
    <div class="field"><label>Role</label><select class="input"><option>Operator</option><option>Admin</option><option>Viewer</option></select></div>
    <div class="field"><label>Lines they can see</label><select class="input"><option>All lines</option><option>Twilio</option><option>Home landline</option></select></div>
    <p class="small muted">They’ll get a one-time setup code to sign in for the first time.</p></div>`, 'Create invite'],
};
function modal(k) {
  const [t, body, ok] = MODALS[k];
  document.getElementById('modalBody').innerHTML = `<div class="card-head"><h2>${t}</h2><div class="right"><button class="btn sm ghost" onclick="closeModal()">Close</button></div></div>
    <div class="modal-body">${body}</div><div class="modal-foot"><button class="btn" onclick="closeModal()">Cancel</button><button class="btn primary" onclick="closeModal();toast('${ok} — demo only')">${ok}</button></div>`;
  document.getElementById('modal').classList.add('show');
}
function closeModal() { document.getElementById('modal').classList.remove('show'); }

/* ---------- ring ---------- */
let ringTimer;
function ring() {
  document.getElementById('ring').classList.add('show');
  let n = 3; const el = document.getElementById('ringCount'); el.textContent = n;
  clearInterval(ringTimer);
  ringTimer = setInterval(() => { n--; el.textContent = n; if (n <= 0) answer('ai'); }, 1000);
}
function closeRing() { clearInterval(ringTimer); document.getElementById('ring').classList.remove('show'); }
function answer(who) { closeRing(); go('live'); if (who === 'me') toast('You’re on the call. AI is taking notes.'); }

/* ---------- utils ---------- */
let tt;
function toast(m) { const t = document.getElementById('toast'); t.textContent = m; t.classList.add('show'); clearTimeout(tt); tt = setTimeout(() => t.classList.remove('show'), 2400); }
function go(r) { location.hash = '#/' + r; }
function theme() {
  const d = document.documentElement;
  d.dataset.theme = d.dataset.theme === 'dark' ? '' : 'dark';
  localStorage.setItem('ll-theme', d.dataset.theme);
}

function render() {
  const r = (location.hash.replace('#/', '') || (advanced ? 'dashboard' : 'home'));
  const root = document.getElementById('root');
  if (r === 'welcome' || r === 'login') { root.innerHTML = P[r](); return; }
  const page = P[r] ? r : 'home';
  const t = TITLES[page];
  root.innerHTML = `<div class="app">
    <aside class="sidebar">${brand()}
      <nav class="nav">${advanced ? NAV.map(([g, items]) => `<div class="nav-group"><div class="nav-label">${g}</div>
        ${items.map(i => `<a href="#/${i[0]}" class="${i[0] === page || (page === 'call' && i[0] === 'calls') || (page === 'assistant' && i[0] === 'agents') ? 'active' : ''}">${ic(i[2])}${i[1]}${i[3] || ''}</a>`).join('')}</div>`).join('')
        : `<div class="nav-group">${SIMPLE_NAV.map(i => `<a href="#/${i[0]}" style="padding:10px 12px;font-size:14.5px" class="${i[0] === page || (page === 'call' && i[0] === 'calls') ? 'active' : ''}">${ic(i[2], 19)}${i[1]}</a>`).join('')}</div>`}
        <div class="nav-group" style="padding:0 10px;margin-top:22px"><label class="row between small" style="color:#8fa6c2;cursor:pointer"><span>Show all features</span><label class="toggle"><input type="checkbox" ${advanced ? 'checked' : ''} onchange="setAdvanced(this.checked)"><span></span></label></label></div></nav>
      <div class="sidebar-foot"><div class="me"><span class="avatar">KA</span><div><div style="color:#fff">Keyhan</div><div style="color:#6f86a3;font-size:11.5px">Owner · <a href="#/login" style="color:#6f86a3">Sign out</a></div></div></div></div>
    </aside>
    <div class="main">
      <header class="topbar"><div class="crumb">${t[0] && advanced ? t[0] + ' / ' : ''}<b>${t[1]}</b></div><div class="spacer"></div>
        ${advanced ? `<div class="search">${ic('search', 15)}Search calls, contacts, settings<span class="kbd">⌘K</span></div>` : ''}
        ${badge(lamp('on') + 'Answering', 'green')}
        <button class="btn ghost sm" title="Notifications">${ic('bell', 16)}</button>
        <button class="btn ghost sm" title="Toggle dark mode" onclick="theme()">${ic('moon', 16)}</button>
      </header>
      <main class="content"><div class="page">${P[page]()}</div></main>
    </div></div>
    <div class="demo-banner"><span class="eyebrow">Demo</span><a class="btn sm" href="#/welcome" onclick="step=0">Setup wizard</a><a class="btn sm" href="#/login">Sign-in</a><button class="btn sm amber" onclick="ring()">Ring</button></div>`;
  document.querySelector('.content').scrollTop = 0;
}

document.documentElement.dataset.theme = localStorage.getItem('ll-theme') || '';
window.addEventListener('hashchange', render);
document.addEventListener('keydown', e => { if (e.key === 'Escape') { closeModal(); closeRing(); } });
document.getElementById('modal').addEventListener('click', e => { if (e.target.id === 'modal') closeModal(); });
render();
