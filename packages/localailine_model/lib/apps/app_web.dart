import 'dart:convert';

import 'app_spec.dart';
import 'app_styles.dart';

/// The website every user-built app gets. One small page that reads the app's
/// description (/api/_spec) and draws it: customer pages at `/`, the manager at `/manage`.
String appHtml(AppSpec spec, {bool manager = false}) {
  final style = styleOf(spec.style);
  final accent = spec.theme.isEmpty ? null : spec.theme;
  // The manager page previews every style, so it loads every font.
  final fonts = manager ? siteStyles.map((s) => s.fonts).toSet().join('&family=') : style.fonts;
  final styles = jsonEncode([
    for (final s in siteStyles)
      {'id': s.id, 'name': s.name, 'about': s.about, 'goodFor': s.goodFor, 'bg': s.bg, 'surface': s.surface, 'ink': s.ink, 'muted': s.muted, 'accent': s.accent, 'head': s.headFont, 'dark': s.dark},
  ]);
  return '''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>${_esc(spec.name)}</title><meta name="description" content="${_esc(spec.site['tagline'] ?? spec.summary)}">
<meta name="theme-color" content="${style.bg}">
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=$fonts&display=swap">
<style>${style.css(accent)}</style><link rel="stylesheet" href="/app.css"></head>
<body class="${style.dark ? 'dark ' : ''}st-${style.id}${manager ? ' is-admin' : ''}"><div id="app"><div class="boot"><div class="spinner"></div></div></div>
<script>window.STYLES=$styles;</script><script src="/app.js"></script></body></html>''';
}

String pausedHtml(AppSpec spec) {
  final style = styleOf(spec.style);
  return '''<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${_esc(spec.name)}</title><link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=${style.fonts}&display=swap">
<style>${style.css(spec.theme.isEmpty ? null : spec.theme)}</style><link rel="stylesheet" href="/app.css"></head>
<body class="${style.dark ? 'dark' : ''}"><div class="paused"><div class="paused-card"><div class="monogram lg">${_esc(spec.name.isEmpty ? '?' : spec.name.substring(0, 1).toUpperCase())}</div>
<h1>${_esc(spec.name)}</h1><p>We’re taking a short break right now. Please check back soon.</p></div></div></body></html>''';
}

String _esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

const appCss = r'''
*,*::before,*::after{box-sizing:border-box}
html{-webkit-text-size-adjust:100%;scroll-behavior:smooth}
body{margin:0;font:16px/1.6 var(--body);color:var(--ink);background:var(--bg);-webkit-font-smoothing:antialiased}
img{display:block;max-width:100%}
a{color:inherit}
h1,h2,h3,h4{font-family:var(--head);font-weight:var(--head-weight);line-height:1.15;margin:0;letter-spacing:-.01em}
p{margin:0}
.muted{color:var(--muted)}
.wrap{width:100%;max-width:1180px;margin:0 auto;padding:0 24px}
.boot{display:grid;place-items:center;min-height:100vh}
.spinner{width:28px;height:28px;border:3px solid var(--line);border-top-color:var(--accent);border-radius:50%;animation:spin .8s linear infinite}
@keyframes spin{to{transform:rotate(360deg)}}
@keyframes rise{from{opacity:0;transform:translateY(10px)}to{opacity:1;transform:none}}
@keyframes pop{0%{transform:scale(.6);opacity:0}70%{transform:scale(1.08)}100%{transform:scale(1);opacity:1}}
.icon{width:1em;height:1em;flex:none;stroke:currentColor;fill:none;stroke-width:2;stroke-linecap:round;stroke-linejoin:round;vertical-align:-.125em}

/* buttons & inputs */
.btn{display:inline-flex;align-items:center;justify-content:center;gap:8px;font:600 15px/1 var(--body);padding:12px 20px;border-radius:calc(var(--radius) * .75 + 4px);border:1px solid var(--line);background:var(--surface);color:var(--ink);cursor:pointer;text-decoration:none;transition:transform .15s,box-shadow .2s,background .2s,opacity .2s;white-space:nowrap}
.btn:hover{transform:translateY(-1px);box-shadow:var(--shadow)}
.btn:active{transform:none}
.btn.primary{background:var(--accent);border-color:var(--accent);color:var(--on-accent)}
.btn.ghost{background:transparent}
.btn.lg{padding:16px 28px;font-size:16px}
.btn.sm{padding:8px 14px;font-size:14px}
.btn.block{width:100%}
.btn.danger{color:#d92d20}
.btn:disabled{opacity:.5;cursor:default;transform:none;box-shadow:none}
.iconbtn{display:inline-grid;place-items:center;width:38px;height:38px;border-radius:50%;border:1px solid var(--line);background:var(--surface);color:var(--ink);cursor:pointer;font-size:17px}
.iconbtn:hover{background:var(--soft)}
input,select,textarea{width:100%;font:16px/1.4 var(--body);color:var(--ink);background:var(--surface);border:1px solid var(--line);border-radius:calc(var(--radius) * .6 + 4px);padding:12px 14px;outline:none;transition:border-color .2s,box-shadow .2s}
input:focus,select:focus,textarea:focus{border-color:var(--accent);box-shadow:0 0 0 4px color-mix(in srgb,var(--accent) 18%,transparent)}
textarea{min-height:110px;resize:vertical}
select{appearance:none;background-image:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='8' fill='none' stroke='%23888' stroke-width='2'%3E%3Cpath d='M1 1l5 5 5-5'/%3E%3C/svg%3E");background-repeat:no-repeat;background-position:right 14px center;padding-right:38px}
label.lbl{display:block;font-weight:600;font-size:14px;margin:0 0 7px}
label.lbl .req{color:var(--accent)}
.field{margin-bottom:18px}
.field.full{grid-column:1/-1}
.hint{font-size:13px;color:var(--muted);margin-top:6px}
.pills{display:flex;flex-wrap:wrap;gap:8px}
.pill-opt{border:1px solid var(--line);background:var(--surface);color:var(--ink);border-radius:999px;padding:9px 16px;font:500 14px var(--body);cursor:pointer;transition:all .15s;white-space:nowrap}
.pill-opt:hover{border-color:var(--accent)}
.pill-opt.on{background:var(--accent);border-color:var(--accent);color:var(--on-accent)}
.switch{display:inline-flex;align-items:center;gap:10px;cursor:pointer;font-weight:500}
.switch input{display:none}
.switch i{width:44px;height:26px;border-radius:99px;background:var(--line);position:relative;transition:background .2s}
.switch i::after{content:"";position:absolute;top:3px;left:3px;width:20px;height:20px;border-radius:50%;background:#fff;box-shadow:0 1px 3px rgba(0,0,0,.2);transition:transform .2s}
.switch input:checked+i{background:var(--accent)}
.switch input:checked+i::after{transform:translateX(18px)}

/* header */
.topnav{position:sticky;top:0;z-index:20;background:color-mix(in srgb,var(--bg) 82%,transparent);backdrop-filter:saturate(1.6) blur(14px);-webkit-backdrop-filter:saturate(1.6) blur(14px);border-bottom:1px solid color-mix(in srgb,var(--line) 70%,transparent)}
.topnav .wrap{display:flex;align-items:center;gap:28px;height:72px}
.brand{display:flex;align-items:center;gap:12px;text-decoration:none;font-family:var(--head);font-weight:var(--head-weight);font-size:21px;letter-spacing:-.01em;margin-right:auto;min-width:0}
.brand span{white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.brand img{height:40px;width:auto;max-width:120px;object-fit:contain;border-radius:8px}
.monogram{display:grid;place-items:center;width:40px;height:40px;border-radius:calc(var(--radius) * .6 + 4px);background:var(--accent);color:var(--on-accent);font:var(--head-weight) 19px var(--head);flex:none}
.monogram.lg{width:72px;height:72px;font-size:32px;margin:0 auto 20px}
.links{display:flex;align-items:center;gap:4px}
.links a{text-decoration:none;font-size:15px;font-weight:500;color:var(--muted);padding:8px 14px;border-radius:999px;text-transform:var(--nav-case)}
.st-elegant .links a,.st-minimal .links a,.st-bold .links a{font-size:13px;letter-spacing:.08em}
.links a:hover,.links a.on{color:var(--ink);background:var(--soft)}
.burger{display:none}
@media (max-width:860px){
  .links{display:none;position:absolute;top:72px;left:0;right:0;flex-direction:column;align-items:stretch;background:var(--bg);border-bottom:1px solid var(--line);padding:12px 16px 18px;box-shadow:var(--shadow-lg)}
  .links.open{display:flex}
  .links a{padding:14px 16px;font-size:16px;border-radius:12px}
  .burger{display:inline-grid}
  .topnav .cta{display:none}
}

/* hero */
.hero{position:relative;overflow:hidden;color:var(--ink);padding:96px 0 104px}
.hero.img{color:#fff;min-height:min(78vh,720px);display:flex;align-items:flex-end;padding:120px 0 88px}
.hero-bg{position:absolute;inset:0;background-size:cover;background-position:center;transform:scale(1.03)}
.hero.img::after{content:"";position:absolute;inset:0;background:linear-gradient(180deg,rgba(0,0,0,.15) 0%,rgba(0,0,0,.35) 45%,rgba(0,0,0,.72) 100%)}
.hero:not(.img)::before{content:"";position:absolute;inset:-40% -10% auto auto;width:760px;height:760px;border-radius:50%;background:radial-gradient(closest-side,color-mix(in srgb,var(--accent) 22%,transparent),transparent);pointer-events:none}
.hero .wrap{position:relative;z-index:2;animation:rise .7s ease both}
.hero h1{font-size:clamp(40px,6.4vw,78px);max-width:15ch;letter-spacing:-.025em}
.hero.sub{padding:72px 0 24px}
.hero.sub h1{font-size:clamp(36px,5vw,58px);max-width:20ch}
.hero.sub::before{display:none}
.st-elegant .hero h1{font-weight:500;letter-spacing:-.01em}
.hero .lead{font-size:clamp(17px,2vw,21px);max-width:56ch;margin-top:20px;opacity:.88}
.hero .actions{display:flex;flex-wrap:wrap;gap:12px;margin-top:34px}
.eyebrow{display:inline-flex;align-items:center;gap:8px;font-size:13px;font-weight:700;letter-spacing:.12em;text-transform:uppercase;color:var(--accent);margin-bottom:18px}
.hero.img .eyebrow{color:#fff;opacity:.9}
.badge{display:inline-flex;align-items:center;gap:8px;font-size:14px;font-weight:600;padding:7px 14px;border-radius:999px;background:var(--surface);border:1px solid var(--line);color:var(--ink);margin-bottom:22px}
.hero.img .badge{background:rgba(255,255,255,.14);border-color:rgba(255,255,255,.3);color:#fff;backdrop-filter:blur(8px)}
.dot{width:8px;height:8px;border-radius:50%;background:#16a34a;box-shadow:0 0 0 4px rgba(22,163,74,.18)}
.dot.off{background:#dc2626;box-shadow:0 0 0 4px rgba(220,38,38,.18)}

/* sections */
.sec{padding:72px 0;animation:rise .6s ease both}
.sec+.sec{padding-top:8px}
.sec-head{display:flex;align-items:flex-end;justify-content:space-between;gap:20px;margin-bottom:28px;flex-wrap:wrap}
.sec-head h2{font-size:clamp(28px,3.6vw,42px)}
.prose{max-width:760px}
.prose h2{font-size:clamp(28px,3.6vw,40px);margin-bottom:16px}
.prose h3{font-size:22px;margin:22px 0 10px}
.prose p{font-size:18px;color:var(--muted);margin-bottom:12px}
.prose ul{padding-left:20px;color:var(--muted);font-size:17px}

/* catalogue */
.toolbar{display:flex;flex-wrap:wrap;gap:12px;align-items:center;margin-bottom:26px}
.search{position:relative;flex:1;min-width:220px;max-width:420px}
.search .icon{position:absolute;left:15px;top:50%;transform:translateY(-50%);color:var(--muted);font-size:18px}
.search input{padding-left:44px;border-radius:999px}
.chips{display:flex;gap:8px;overflow-x:auto;scrollbar-width:none;padding:2px}
.chips::-webkit-scrollbar{display:none}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(270px,1fr));gap:22px}
.grid.settled .item{animation:none}
.grid.compact{grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:16px}
.item{background:var(--surface);border:1px solid var(--line);border-radius:var(--radius);overflow:hidden;display:flex;flex-direction:column;box-shadow:var(--shadow);transition:transform .25s,box-shadow .25s;animation:rise .5s ease both}
.item:hover{transform:translateY(-3px);box-shadow:var(--shadow-lg)}
.media{aspect-ratio:4/3;background:var(--soft);overflow:hidden;position:relative}
.media img{width:100%;height:100%;object-fit:cover;transition:transform .6s}
.item:hover .media img{transform:scale(1.04)}
.ph{width:100%;height:100%;display:grid;place-items:center;font:var(--head-weight) 52px var(--head);color:color-mix(in srgb,var(--accent) 55%,var(--surface));background:radial-gradient(120% 90% at 20% 0%,color-mix(in srgb,var(--accent) 7%,var(--surface)),color-mix(in srgb,var(--accent) 20%,var(--surface)));position:relative}
.ph::after{content:"";position:absolute;inset:14px;border:1px solid color-mix(in srgb,var(--accent) 22%,transparent);border-radius:calc(var(--radius) * .6)}
.ph.sm::after{display:none}
.ph.sm{font-size:18px}
.item .body{padding:18px 20px 20px;display:flex;flex-direction:column;gap:8px;flex:1}
.item .top{display:flex;align-items:flex-start;gap:12px;justify-content:space-between}
.item h3{font-size:19px}
.price{font:700 17px var(--body);color:var(--accent);white-space:nowrap}
.st-minimal .price,.st-bold .price{color:var(--ink)}
.desc{color:var(--muted);font-size:15px;display:-webkit-box;-webkit-line-clamp:3;-webkit-box-orient:vertical;overflow:hidden}
.meta{display:flex;flex-wrap:wrap;gap:6px;margin-top:2px}
.tag{display:inline-flex;align-items:center;gap:5px;font-size:12.5px;font-weight:600;padding:4px 10px;border-radius:999px;background:var(--soft);color:var(--muted)}
.tag.acc{background:color-mix(in srgb,var(--accent) 14%,transparent);color:var(--accent)}
.st-bold .tag.acc{color:var(--ink)}
.item .foot{margin-top:auto;padding-top:10px;display:flex;align-items:center;justify-content:space-between;gap:10px}
.qtybadge{font-size:13px;font-weight:700;color:var(--accent)}
.st-bold .qtybadge{color:var(--ink)}
.empty{padding:48px 24px;text-align:center;color:var(--muted);border:1px dashed var(--line);border-radius:var(--radius)}
.empty .icon{font-size:28px;margin-bottom:8px}

/* info card */
.info{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:18px}
.info-card{background:var(--surface);border:1px solid var(--line);border-radius:var(--radius);padding:24px;box-shadow:var(--shadow)}
.info-row{display:flex;gap:14px;align-items:flex-start;padding:12px 0;border-bottom:1px solid var(--line)}
.info-row:last-child{border:0;padding-bottom:0}
.info-row:first-of-type{padding-top:0}
.info-ic{display:grid;place-items:center;width:40px;height:40px;border-radius:12px;background:color-mix(in srgb,var(--accent) 12%,transparent);color:var(--accent);font-size:18px;flex:none}
.st-bold .info-ic{color:var(--ink)}
.info-row small{display:block;color:var(--muted);font-size:13px;font-weight:600;text-transform:uppercase;letter-spacing:.06em}
.info-row b{font-weight:600;font-size:17px}

/* forms */
.formwrap{display:grid;grid-template-columns:1.25fr .75fr;gap:28px;align-items:start}
.formwrap.single{grid-template-columns:minmax(0,760px);justify-content:center}
@media (max-width:900px){.formwrap{grid-template-columns:1fr}}
.panel{background:var(--surface);border:1px solid var(--line);border-radius:var(--radius);padding:32px;box-shadow:var(--shadow)}
@media (max-width:600px){.panel{padding:22px}}
.panel h2{font-size:clamp(26px,3vw,34px)}
.panel>.sub{color:var(--muted);margin:8px 0 26px}
.fgrid{display:grid;grid-template-columns:1fr 1fr;gap:0 18px}
@media (max-width:600px){.fgrid{grid-template-columns:1fr}}
.aside{position:sticky;top:92px}
.aside h3{font-size:20px;margin-bottom:14px}
.cart-line{display:flex;align-items:center;gap:12px;padding:12px 0;border-bottom:1px solid var(--line)}
.cart-line .thumb{width:46px;height:46px;border-radius:10px;overflow:hidden;flex:none}
.cart-line .thumb img{width:100%;height:100%;object-fit:cover}
.cart-line .nm{flex:1;min-width:0;font-weight:600;font-size:15px}
.cart-line .nm small{display:block;color:var(--muted);font-weight:500}
.stepper{display:inline-flex;align-items:center;border:1px solid var(--line);border-radius:999px;overflow:hidden}
.stepper button{border:0;background:transparent;color:var(--ink);width:32px;height:32px;cursor:pointer;font-size:15px;display:grid;place-items:center}
.stepper button:hover{background:var(--soft)}
.stepper b{min-width:22px;text-align:center;font-size:14px}
.total{display:flex;justify-content:space-between;align-items:baseline;padding-top:16px;font-weight:700;font-size:18px}
.total .price{font-size:22px}
.cart-empty{color:var(--muted);font-size:15px;padding:8px 0 4px}
.success{text-align:center;padding:24px 8px}
.success .ok{width:76px;height:76px;border-radius:50%;display:grid;place-items:center;margin:0 auto 20px;background:color-mix(in srgb,var(--accent) 15%,transparent);color:var(--accent);font-size:38px;animation:pop .5s ease both}
.st-bold .success .ok{color:var(--ink)}
.success h2{margin-bottom:10px}
.success p{color:var(--muted);margin-bottom:24px}
.err{background:#fef3f2;color:#b42318;border:1px solid #fecdca;padding:12px 16px;border-radius:12px;font-size:14.5px;margin:4px 0 14px}
.dark .err{background:#2b1414;border-color:#5c2020;color:#ffb4ab}
.floatcart{position:fixed;left:50%;bottom:20px;transform:translate(-50%,160%);z-index:30;transition:transform .35s cubic-bezier(.2,.8,.2,1);box-shadow:var(--shadow-lg)}
.floatcart.show{transform:translate(-50%,0)}
.floatcart:not(.show){visibility:hidden;transition:transform .35s,visibility 0s .35s}

/* uploads */
.drop{border:1.5px dashed var(--line);border-radius:var(--radius);padding:22px;text-align:center;color:var(--muted);cursor:pointer;transition:all .2s;background:var(--soft)}
.drop:hover,.drop.over{border-color:var(--accent);color:var(--ink)}
.drop .icon{font-size:26px;margin:0 auto 6px;display:block}
.drop-prev{position:relative;border-radius:var(--radius);overflow:hidden;border:1px solid var(--line)}
.drop-prev img{width:100%;max-height:260px;object-fit:cover}
.drop-prev .row{position:absolute;right:10px;bottom:10px;display:flex;gap:8px}

/* footer */
.footer{margin-top:80px;border-top:1px solid var(--line);background:var(--surface)}
.dark .footer{background:#0f1015}
.footer .cols{display:grid;grid-template-columns:1.4fr 1fr 1fr 1fr;gap:36px;padding-top:56px;padding-bottom:36px}
@media (max-width:860px){.footer .cols{grid-template-columns:1fr 1fr}}
@media (max-width:520px){.footer .cols{grid-template-columns:1fr}}
.footer h4{font-family:var(--body);font-size:13px;letter-spacing:.1em;text-transform:uppercase;color:var(--muted);margin-bottom:14px;font-weight:700}
.footer p,.footer a{font-size:15px;color:var(--ink);text-decoration:none;display:block;margin-bottom:8px}
.footer .brand{display:flex}
.footer a:hover{color:var(--accent)}
.footer .about{color:var(--muted);margin-top:14px;max-width:36ch}
.footer .bottom{display:flex;justify-content:space-between;flex-wrap:wrap;gap:10px;border-top:1px solid var(--line);padding-top:20px;padding-bottom:28px;font-size:13.5px;color:var(--muted)}
.footer .bottom a{display:inline;color:var(--muted);font-size:13.5px;margin:0}

/* availability */
.avail{background:var(--surface);border:1px solid var(--line);border-radius:var(--radius);padding:26px;box-shadow:var(--shadow)}
.avail-ctl{display:flex;flex-wrap:wrap;gap:16px;align-items:flex-end;margin-bottom:18px}
.avail-ctl .field{margin:0}
.avail-ctl input[type=date]{width:auto;min-width:180px}
.guests{display:inline-flex;align-items:center;gap:6px;border:1px solid var(--line);border-radius:999px;padding:4px}
.guests button{width:36px;height:36px;border-radius:50%;border:0;background:var(--soft);color:var(--ink);cursor:pointer;font-size:16px;display:grid;place-items:center}
.guests b{min-width:64px;text-align:center;font-size:15px}
.slots{display:flex;flex-wrap:wrap;gap:8px;padding:2px 2px 14px}
.slot{border:1px solid var(--line);background:var(--surface);color:var(--ink);border-radius:999px;padding:9px 14px;font:600 14px var(--body);cursor:pointer;white-space:nowrap}
.slot.on{background:var(--accent);border-color:var(--accent);color:var(--on-accent)}
.slot.full{opacity:.4;text-decoration:line-through}
.slot:disabled{opacity:.3;cursor:default}
.res-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:12px;margin-top:8px}
.res{border:1.5px solid var(--line);border-radius:calc(var(--radius) * .7 + 4px);padding:14px;text-align:left;background:var(--surface);color:var(--ink);font:inherit;cursor:pointer;transition:all .15s;position:relative}
.res b{display:block;font:var(--head-weight) 20px var(--head)}
.res small{color:var(--muted);font-size:13px}
.res .st{display:inline-flex;align-items:center;gap:6px;margin-top:8px;font-size:12.5px;font-weight:700}
.res.free .st{color:#15803d}.res.free:hover{border-color:var(--accent);transform:translateY(-2px)}
.res.taken{cursor:not-allowed;background:var(--soft)}.res.taken b{color:var(--muted)}.res.taken .st{color:#b91c1c}
.res.small{opacity:.55;cursor:not-allowed}
.res.picked{border-color:var(--accent);box-shadow:0 0 0 4px color-mix(in srgb,var(--accent) 20%,transparent)}
.dark .res.free .st{color:#86efac}.dark .res.taken .st{color:#fca5a5}
.tl{overflow-x:auto;margin-top:18px;border:1px solid var(--line);border-radius:12px}
.tl table{border-collapse:collapse;font-size:12.5px;min-width:100%}
.tl th,.tl td{border-bottom:1px solid var(--line);border-right:1px solid var(--line);padding:0;height:34px;min-width:44px;text-align:center}
.tl th{background:var(--soft);font-weight:600;color:var(--muted);padding:0 6px;white-space:nowrap}
.tl th.rn{position:sticky;left:0;background:var(--surface);text-align:left;padding:0 12px;color:var(--ink);min-width:110px;z-index:1}
.tl td.b{background:color-mix(in srgb,var(--accent) 78%,transparent);color:var(--on-accent);font-weight:600;cursor:pointer;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:1px;padding:0 8px;font-size:12px;text-align:left;border-radius:6px;box-shadow:inset 0 0 0 2px var(--surface)}
.tl td.b:hover{filter:brightness(1.08)}
.tl td.f{cursor:pointer}.tl td.f:hover{background:var(--soft)}
.tl td.past{background:repeating-linear-gradient(45deg,transparent,transparent 4px,var(--soft) 4px,var(--soft) 8px)}
.legend{display:flex;gap:16px;font-size:13px;color:var(--muted);margin-top:10px;flex-wrap:wrap}
.legend i{display:inline-block;width:12px;height:12px;border-radius:3px;margin-right:6px;vertical-align:-1px}
.daynav{display:flex;align-items:center;gap:8px}

/* manager on the website */
.adminbar{position:sticky;top:0;z-index:25;background:#111827;color:#f9fafb;font:500 14px var(--body)}
.adminbar .wrap{display:flex;align-items:center;gap:10px;height:46px;flex-wrap:nowrap;overflow-x:auto}
.adminbar b{margin-right:auto;display:flex;align-items:center;gap:8px;white-space:nowrap}
.adminbar a,.adminbar button{color:#f9fafb;background:rgba(255,255,255,.1);border:0;border-radius:8px;padding:6px 12px;font:500 13.5px var(--body);text-decoration:none;cursor:pointer;white-space:nowrap}
.adminbar a:hover,.adminbar button:hover{background:rgba(255,255,255,.2)}
.has-admin .topnav{top:46px}
.item{position:relative}
.edit-btn{position:absolute;top:10px;right:10px;z-index:3;display:grid;place-items:center;width:36px;height:36px;border-radius:50%;border:0;background:#111827;color:#fff;cursor:pointer;box-shadow:0 4px 14px rgba(0,0,0,.25);font-size:15px}
.edit-btn:hover{transform:scale(1.06)}
.sec-actions{display:flex;gap:8px;flex-wrap:wrap}
.imp-row{display:flex;gap:12px;align-items:flex-start;padding:12px 0;border-bottom:1px solid var(--line)}
.imp-row input[type=checkbox]{width:20px;height:20px;margin-top:2px;flex:none;accent-color:var(--accent)}
.imp-row .nm{font-weight:600}
.imp-row .kv{color:var(--muted);font-size:14px}
.reading{text-align:center;padding:40px 10px;color:var(--muted)}
.reading .spinner{margin:0 auto 16px}

/* toast */
.toast{position:fixed;left:50%;top:22px;transform:translate(-50%,-160%);z-index:99;background:var(--ink);color:var(--bg);padding:12px 20px;border-radius:999px;font-weight:600;font-size:14.5px;box-shadow:var(--shadow-lg);transition:transform .35s cubic-bezier(.2,.8,.2,1);display:flex;gap:8px;align-items:center}
.toast.show{transform:translate(-50%,0)}

/* paused */
.paused{min-height:100vh;display:grid;place-items:center;padding:24px}
.paused-card{text-align:center;max-width:420px}
.paused-card h1{font-size:34px;margin-bottom:12px}
.paused-card p{color:var(--muted)}

/* ================= manager ================= */
.admin{display:grid;grid-template-columns:260px 1fr;min-height:100vh}
.side{background:var(--surface);border-right:1px solid var(--line);padding:22px 14px;display:flex;flex-direction:column;gap:4px;position:sticky;top:0;height:100vh;overflow:auto}
.side .brand{font-size:18px;padding:4px 10px 22px;margin:0}
.side .grp{font-size:11.5px;font-weight:700;letter-spacing:.1em;text-transform:uppercase;color:var(--muted);padding:16px 12px 6px}
.nav-btn{display:flex;align-items:center;gap:11px;width:100%;border:0;background:transparent;color:var(--muted);font:500 15px var(--body);padding:10px 12px;border-radius:10px;cursor:pointer;text-align:left;text-decoration:none}
.nav-btn:hover{background:var(--soft);color:var(--ink)}
.nav-btn.on{background:color-mix(in srgb,var(--accent) 13%,transparent);color:var(--ink);font-weight:600}
.nav-btn.on .icon{color:var(--accent)}
.st-bold .nav-btn.on .icon{color:var(--ink)}
.side .spacer{flex:1}
.content{min-width:0;padding:30px 40px 80px}
@media (max-width:900px){.admin{grid-template-columns:1fr}.side{position:static;height:auto;flex-direction:row;flex-wrap:nowrap;overflow-x:auto;padding:10px;gap:6px;border-right:0;border-bottom:1px solid var(--line)}.side .brand,.side .grp,.side .spacer{display:none}.nav-btn{width:auto;white-space:nowrap}.content{padding:20px 16px 80px}}
.head{display:flex;align-items:center;gap:14px;flex-wrap:wrap;margin-bottom:26px}
.head h1{font-size:30px;margin-right:auto}
.head .sub{width:100%;color:var(--muted);margin-top:-8px;font-size:15px}
.stats{display:grid;grid-template-columns:repeat(auto-fill,minmax(200px,1fr));gap:16px;margin-bottom:28px}
.stat{background:var(--surface);border:1px solid var(--line);border-radius:var(--radius);padding:20px;cursor:pointer;transition:all .2s;box-shadow:var(--shadow)}
.stat:hover{border-color:var(--accent)}
.stat small{display:flex;align-items:center;gap:8px;color:var(--muted);font-weight:600;font-size:13.5px}
.stat b{display:block;font:var(--head-weight) 34px var(--head);margin-top:8px}
.card{background:var(--surface);border:1px solid var(--line);border-radius:var(--radius);box-shadow:var(--shadow)}
.card-h{display:flex;align-items:center;gap:12px;padding:18px 22px;border-bottom:1px solid var(--line)}
.card-h h3{font-size:18px;margin-right:auto}
.card-b{padding:22px}
.tablewrap{overflow-x:auto}
table.data{width:100%;border-collapse:collapse;font-size:14.5px}
table.data th{text-align:left;font-size:12px;letter-spacing:.06em;text-transform:uppercase;color:var(--muted);font-weight:700;padding:12px 16px;border-bottom:1px solid var(--line);white-space:nowrap;background:var(--soft)}
table.data td{padding:12px 16px;border-bottom:1px solid var(--line);vertical-align:middle}
table.data tr:last-child td{border-bottom:0}
table.data tbody tr{cursor:pointer;transition:background .15s}
table.data tbody tr:hover{background:var(--soft)}
table.data tr.new{background:color-mix(in srgb,var(--accent) 9%,transparent)}
.thumb-sm{width:44px;height:44px;border-radius:10px;overflow:hidden;flex:none}
.thumb-sm img{width:100%;height:100%;object-fit:cover}
.cell-main{display:flex;align-items:center;gap:12px;font-weight:600}
.status{appearance:none;border:0;font:600 13px var(--body);padding:6px 30px 6px 12px;border-radius:999px;cursor:pointer;width:auto;background-position:right 10px center;background-color:var(--soft);color:var(--ink)}
.status.s0{background-color:#eef4ff;color:#1d4ed8}.status.s1{background-color:#fff6e6;color:#b45309}.status.s2{background-color:#ecfdf3;color:#047857}.status.s3{background-color:#f4f4f5;color:#52525b}.status.s4{background-color:#fef2f2;color:#b91c1c}
.dark .status.s0{background-color:#172554;color:#bfdbfe}.dark .status.s1{background-color:#422006;color:#fde68a}.dark .status.s2{background-color:#052e16;color:#bbf7d0}.dark .status.s3{background-color:#27272a;color:#d4d4d8}.dark .status.s4{background-color:#450a0a;color:#fecaca}
.drawer-bg{position:fixed;inset:0;background:rgba(10,12,20,.45);z-index:40;opacity:0;transition:opacity .25s}
.drawer-bg.show{opacity:1}
.drawer{position:fixed;top:0;right:0;bottom:0;width:min(580px,100%);background:var(--bg);z-index:41;display:flex;flex-direction:column;transform:translateX(100%);transition:transform .3s cubic-bezier(.2,.8,.2,1);box-shadow:var(--shadow-lg)}
.drawer.show{transform:none}
.drawer .dh{display:flex;align-items:center;gap:12px;padding:20px 24px;border-bottom:1px solid var(--line)}
.drawer .dh h3{font-size:20px;margin-right:auto}
.drawer .db{flex:1;overflow:auto;padding:24px}
.drawer .df{display:flex;gap:10px;padding:16px 24px;border-top:1px solid var(--line);background:var(--surface)}
.drawer .df .sp{flex:1}
.styles{display:grid;grid-template-columns:repeat(auto-fill,minmax(230px,1fr));gap:14px}
.stylecard{border:2px solid var(--line);border-radius:14px;overflow:hidden;cursor:pointer;background:var(--surface);transition:all .2s;text-align:left;padding:0;color:var(--ink);font:inherit}
.stylecard:hover{border-color:color-mix(in srgb,var(--accent) 50%,var(--line))}
.stylecard.on{border-color:var(--accent);box-shadow:0 0 0 4px color-mix(in srgb,var(--accent) 18%,transparent)}
.stylecard .sw{height:92px;padding:16px;display:flex;flex-direction:column;justify-content:space-between}
.stylecard .sw b{font-size:28px;line-height:1}
.stylecard .sw i{display:block;width:56px;height:10px;border-radius:99px}
.stylecard .tx{padding:12px 14px 14px}
.stylecard .tx strong{display:block;font-size:15px}
.stylecard .tx span{display:block;font-size:13px;color:var(--muted);margin-top:3px;line-height:1.4}
.savebar{position:sticky;bottom:16px;display:flex;justify-content:flex-end;gap:10px;margin-top:22px}
.savebar .btn{box-shadow:var(--shadow-lg)}
.login{min-height:100vh;display:grid;place-items:center;padding:24px;background:radial-gradient(900px 500px at 80% -10%,color-mix(in srgb,var(--accent) 18%,transparent),transparent)}
.login .panel{width:100%;max-width:420px;text-align:center}
.login h1{font-size:28px;margin-bottom:6px}
.login input{text-align:center;font-size:24px;letter-spacing:.4em;margin:22px 0 14px}
.sectitle{font-size:22px;margin:34px 0 14px}
.pagebox{border:1px solid var(--line);border-radius:var(--radius);padding:20px;margin-bottom:14px;background:var(--surface)}
.pagebox h4{font-size:17px;margin-bottom:14px;display:flex;gap:8px;align-items:center}
.pagebox .blk{border-top:1px dashed var(--line);padding-top:16px;margin-top:4px}
.colorrow{display:flex;gap:12px;align-items:center;margin-top:18px;flex-wrap:wrap}
.colorrow input[type=color]{width:52px;height:40px;padding:3px;cursor:pointer}

/* status colours: new (blue), in hand (amber), good (green), over (grey), off (red) */
.t-blue{--pc:#1d4ed8;--pb:#eef4ff}.t-amber{--pc:#b45309;--pb:#fff6e6}.t-green{--pc:#047857;--pb:#ecfdf3}.t-grey{--pc:#52525b;--pb:#f4f4f5}.t-red{--pc:#b91c1c;--pb:#fef2f2}
.dark .t-blue{--pc:#bfdbfe;--pb:#172554}.dark .t-amber{--pc:#fde68a;--pb:#422006}.dark .t-green{--pc:#bbf7d0;--pb:#052e16}.dark .t-grey{--pc:#d4d4d8;--pb:#27272a}.dark .t-red{--pc:#fecaca;--pb:#450a0a}
.status[class*=t-]{background-color:var(--pb);color:var(--pc)}
.spill{display:inline-flex;align-items:center;gap:6px;font:600 12.5px/1 var(--body);padding:6px 10px;border-radius:999px;background:var(--pb,var(--soft));color:var(--pc,var(--ink));white-space:nowrap}
.spill::before{content:"";width:6px;height:6px;border-radius:50%;background:currentColor;opacity:.8}
.small{font-size:13px}
.count{font:600 14px var(--body);color:var(--muted);background:var(--soft);border-radius:999px;padding:4px 10px;vertical-align:middle;margin-left:6px;letter-spacing:0}
.count:empty{display:none}

/* nav on phones, sticky actions */
.burger[aria-expanded=true]{background:var(--soft)}
.topnav.many .links a{padding:8px 11px;font-size:14px}
@media (max-width:1100px){
  .topnav.many .links{display:none;position:absolute;top:72px;left:0;right:0;flex-direction:column;align-items:stretch;background:var(--bg);border-bottom:1px solid var(--line);padding:12px 16px 18px;box-shadow:var(--shadow-lg)}
  .topnav.many .links.open{display:flex}
  .topnav.many .links a{padding:14px 16px;font-size:16px;border-radius:12px}
  .topnav.many .burger{display:inline-grid}
}
.links.open{animation:rise .25s ease both}
.mbar{display:none}
@media (max-width:760px){
  .mbar{display:flex;gap:8px;position:fixed;left:0;right:0;bottom:0;z-index:29;padding:10px 12px calc(10px + env(safe-area-inset-bottom));background:color-mix(in srgb,var(--bg) 88%,transparent);backdrop-filter:blur(14px);-webkit-backdrop-filter:blur(14px);border-top:1px solid var(--line)}
  .mbar .btn{flex:1;padding:13px 12px}
  .mbar .btn.call{flex:none;width:48px;padding:0}
  .has-mbar .footer{padding-bottom:76px}
  .has-mbar .floatcart{bottom:84px}
}

/* footer extras */
.cta-band{background:color-mix(in srgb,var(--accent) 8%,var(--surface));border-bottom:1px solid var(--line)}
.cta-band .wrap{display:flex;align-items:center;justify-content:space-between;gap:24px;flex-wrap:wrap;padding-top:40px;padding-bottom:40px}
.cta-band h2{font-size:clamp(24px,3vw,34px)}
.cta-band p{color:var(--muted);margin-top:6px}
.cta-band .actions{display:flex;gap:10px;flex-wrap:wrap}
.footer .soft{color:var(--muted)}
.footer .dirs{display:inline-flex;align-items:center;gap:6px;color:var(--accent);font-weight:600}
.st-bold .footer .dirs{color:var(--ink)}

/* menu layout */
.menu-nav{position:sticky;top:72px;z-index:5;display:flex;gap:6px;overflow-x:auto;scrollbar-width:none;padding:10px 0;margin:-6px 0 18px;background:color-mix(in srgb,var(--bg) 90%,transparent);backdrop-filter:blur(10px);-webkit-backdrop-filter:blur(10px)}
.menu-nav::-webkit-scrollbar{display:none}
.menu-nav a{flex:none;text-decoration:none;font-weight:600;font-size:14px;padding:8px 16px;border-radius:999px;border:1px solid var(--line);background:var(--surface);color:var(--ink)}
.menu-nav a:hover{border-color:var(--accent)}
.has-admin .menu-nav{top:118px}
.menu-cols{display:grid;gap:8px 56px;grid-template-columns:1fr}
@media (min-width:980px){.menu-cols{grid-template-columns:1fr 1fr;align-items:start}}
.menu-cat{scroll-margin-top:140px;margin-bottom:26px}
.menu-h{position:sticky;top:124px;z-index:2;background:var(--bg);font-size:clamp(24px,2.6vw,30px);padding:8px 0 10px;border-bottom:2px solid var(--ink);margin-bottom:6px}
.has-admin .menu-h{top:170px}
.mi{position:relative;display:flex;gap:16px;align-items:flex-start;padding:16px 0;border-bottom:1px solid var(--line)}
.mi:last-child{border-bottom:0}
.mi-img{width:76px;height:76px;border-radius:calc(var(--radius) * .6 + 4px);overflow:hidden;flex:none;background:var(--soft)}
.mi-img img{width:100%;height:100%;object-fit:cover}
.mi-b{flex:1;min-width:0}
.mi-top{display:flex;align-items:baseline;gap:10px}
.mi-top h4{font-size:18px;font-family:var(--head);font-weight:var(--head-weight)}
.mi-top .dots{flex:1;border-bottom:2px dotted color-mix(in srgb,var(--muted) 45%,transparent);transform:translateY(-4px);min-width:16px}
.mi-d{color:var(--muted);font-size:15px;margin-top:4px}
.mi-meta{display:flex;flex-wrap:wrap;gap:6px;margin-top:8px;align-items:center}
.mi-meta:empty{display:none}
.mi-add{display:flex;align-items:center;gap:8px;flex:none;align-self:center}
.mi.out{opacity:.55}
.mi .edit-btn{top:12px;right:auto;left:-6px;width:30px;height:30px;font-size:13px}
.dbadge{display:inline-flex;align-items:center;gap:4px;font:700 11.5px/1 var(--body);letter-spacing:.02em;padding:5px 8px;border-radius:999px;background:var(--soft);color:var(--muted)}
.dbadge .icon{font-size:12px}
.dbadge.vg,.dbadge.v{background:#e8f6ec;color:#166534}.dbadge.gf{background:#fdf3e1;color:#92400e}.dbadge.sp{background:#fdecec;color:#b91c1c}
.dbadge.pop{background:color-mix(in srgb,var(--accent) 14%,transparent);color:var(--accent)}.dbadge.out{background:var(--ink);color:var(--bg)}
.dark .dbadge.vg,.dark .dbadge.v{background:#052e16;color:#bbf7d0}.dark .dbadge.gf{background:#422006;color:#fde68a}.dark .dbadge.sp{background:#450a0a;color:#fecaca}.st-bold .dbadge.pop{color:var(--ink)}
.allerg{font-size:12.5px;color:var(--muted)}
.menu-note{display:flex;gap:8px;align-items:center;color:var(--muted);font-size:14px;margin-top:8px;padding:14px 16px;border:1px dashed var(--line);border-radius:var(--radius)}

/* gallery */
.gallery{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));grid-auto-rows:200px;grid-auto-flow:dense;gap:12px}
.g-item{position:relative;border:0;padding:0;border-radius:var(--radius);overflow:hidden;cursor:zoom-in;background:var(--soft)}
.g-item:nth-child(5n+1){grid-row:span 2}
.g-item img{width:100%;height:100%;object-fit:cover;transition:transform .6s}
.g-item:hover img{transform:scale(1.05)}
.g-item span{position:absolute;left:10px;bottom:10px;background:rgba(0,0,0,.55);color:#fff;font-size:13px;font-weight:600;padding:5px 10px;border-radius:999px;backdrop-filter:blur(6px)}
.lightbox{position:fixed;inset:0;z-index:90;background:rgba(8,9,12,.92);display:flex;align-items:center;justify-content:center;gap:12px;padding:20px;animation:rise .2s ease both}
.lightbox figure{margin:0;max-width:min(1100px,86vw);text-align:center}
.lightbox img{max-height:80vh;max-width:100%;border-radius:12px;margin:0 auto}
.lightbox figcaption{color:#e5e7eb;margin-top:12px;font-weight:600}
.lightbox .iconbtn{background:rgba(255,255,255,.12);border-color:transparent;color:#fff}
.lb-x{position:absolute;top:18px;right:18px}

/* reviews */
.avg{display:flex;align-items:center;gap:10px}.avg b{font:var(--head-weight) 28px var(--head)}
.quotes{display:grid;grid-template-columns:repeat(auto-fill,minmax(280px,1fr));gap:18px}
.quote{position:relative;margin:0;background:var(--surface);border:1px solid var(--line);border-radius:var(--radius);padding:26px;box-shadow:var(--shadow);display:flex;flex-direction:column;gap:14px;animation:rise .5s ease both}
.quote blockquote{margin:0;font-size:17px;line-height:1.6;flex:1}
.st-elegant .quote blockquote{font-family:var(--head);font-style:italic}
.quote figcaption{display:flex;align-items:center;gap:12px}
.quote figcaption small{display:block;color:var(--muted);font-size:13px}
.stars{color:#f59e0b;letter-spacing:2px;font-size:16px}.stars span{color:var(--line)}
.avatar{display:grid;place-items:center;width:36px;height:36px;border-radius:50%;flex:none;font-weight:700;font-size:14px;color:hsl(var(--h) 45% 32%);background:hsl(var(--h) 60% 90%)}
.dark .avatar{color:hsl(var(--h) 60% 85%);background:hsl(var(--h) 30% 22%)}

/* contact */
.lead2{color:var(--muted);font-size:17px;max-width:60ch;margin:-12px 0 22px}
.contact{display:grid;grid-template-columns:1fr 1.2fr;gap:18px}
@media (max-width:820px){.contact{grid-template-columns:1fr}}
.contact .info-row b a{text-decoration:none}
.small-link{display:inline-flex;align-items:center;gap:5px;margin-left:10px;font-size:13.5px;color:var(--accent);font-weight:600;text-decoration:none}
.sub2{display:flex;align-items:center;gap:8px;font-size:14px;color:var(--muted);font-weight:500;margin-top:4px}
.mapcard{position:relative;display:block;min-height:280px;border-radius:var(--radius);overflow:hidden;border:1px solid var(--line);text-decoration:none;color:var(--ink);box-shadow:var(--shadow)}
.map-bg{position:absolute;inset:0;background:linear-gradient(115deg,transparent 46%,color-mix(in srgb,var(--accent) 22%,transparent) 46.5%,color-mix(in srgb,var(--accent) 22%,transparent) 49%,transparent 49.5%),linear-gradient(25deg,transparent 60%,color-mix(in srgb,var(--muted) 18%,transparent) 60.5%,color-mix(in srgb,var(--muted) 18%,transparent) 62%,transparent 62.5%),repeating-linear-gradient(0deg,transparent 0 38px,color-mix(in srgb,var(--line) 80%,transparent) 38px 40px),repeating-linear-gradient(90deg,transparent 0 38px,color-mix(in srgb,var(--line) 80%,transparent) 38px 40px),color-mix(in srgb,var(--accent) 4%,var(--surface));transition:transform .8s}
.mapcard:hover .map-bg{transform:scale(1.04)}
.map-pin{position:absolute;left:50%;top:44%;transform:translate(-50%,-50%);display:grid;place-items:center;width:58px;height:58px;border-radius:50%;background:var(--accent);color:var(--on-accent);font-size:26px;box-shadow:0 0 0 10px color-mix(in srgb,var(--accent) 20%,transparent),var(--shadow-lg)}
.map-cap{position:absolute;left:14px;right:14px;bottom:14px;display:flex;justify-content:space-between;align-items:center;gap:10px;background:var(--surface);border:1px solid var(--line);border-radius:12px;padding:12px 16px;flex-wrap:wrap}
.map-cap span{display:inline-flex;align-items:center;gap:6px;color:var(--accent);font-weight:600;font-size:14px}
.st-bold .map-cap span,.st-bold .small-link{color:var(--ink)}

/* highlights */
.features{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:18px}
.feature{background:var(--surface);border:1px solid var(--line);border-radius:var(--radius);padding:26px;box-shadow:var(--shadow);animation:rise .5s ease both}
.f-ic{display:grid;place-items:center;width:48px;height:48px;border-radius:14px;background:color-mix(in srgb,var(--accent) 12%,transparent);color:var(--accent);font-size:22px;margin-bottom:16px}
.st-bold .f-ic{color:var(--ink)}
.feature h3{font-size:19px;margin-bottom:6px}
.feature p{color:var(--muted);font-size:15px}

/* cart extras */
.sub-line{display:flex;justify-content:space-between;color:var(--muted);font-size:15px;padding-top:10px}
.minwarn{margin-top:12px;font-size:14px;padding:10px 12px;border-radius:10px;background:#fff7e6;color:#92400e}
.dark .minwarn{background:#422006;color:#fde68a}
.cart-hint{font-size:13px;color:var(--muted);margin-top:10px}
.closed-note{display:flex;align-items:center;gap:10px;padding:14px 16px;border-radius:12px;background:#fef2f2;color:#991b1b;font-weight:600;margin-bottom:12px}
.dark .closed-note{background:#450a0a;color:#fecaca}

/* manager: dashboard */
.kpis{display:grid;grid-template-columns:repeat(auto-fill,minmax(190px,1fr));gap:16px;margin-bottom:22px}
.kpi{background:var(--surface);border:1px solid var(--line);border-radius:var(--radius);padding:18px 20px;box-shadow:var(--shadow)}
.kpi small{display:flex;align-items:center;gap:8px;color:var(--muted);font-weight:600;font-size:13px}
.kpi small .icon{color:var(--accent)}
.st-bold .kpi small .icon{color:var(--ink)}
.kpi b{display:block;font:var(--head-weight) 32px/1.1 var(--head);margin:10px 0 4px;font-variant-numeric:tabular-nums}
.kpi span{font-size:12.5px;color:var(--muted)}
.dash{display:grid;grid-template-columns:1.35fr 1fr;gap:22px;align-items:start}
@media (max-width:1100px){.dash{grid-template-columns:1fr}}
.dcol{display:flex;flex-direction:column;gap:22px;min-width:0}
.card-h .small{margin-left:auto}
.card-h h3+.small{margin-left:0}
.minis{display:grid;grid-template-columns:repeat(auto-fill,minmax(230px,1fr));gap:20px}
.mini{cursor:pointer;border-radius:12px;padding:6px;margin:-6px}
.mini:hover{background:var(--soft)}
.mini-h{display:flex;justify-content:space-between;align-items:baseline;gap:8px;margin-bottom:8px;font-size:14px}
.mini-h span{color:var(--muted);font-size:12.5px}
svg.bars{width:100%;height:auto;display:block;overflow:visible}
svg.bars .base{stroke:var(--line);stroke-width:1}
svg.bars path{fill:color-mix(in srgb,var(--accent) 42%,var(--surface))}
svg.bars .today path{fill:var(--accent)}
svg.bars .hit{fill:transparent}
svg.bars g:hover path{fill:var(--accent)}
svg.bars text{fill:var(--muted);font:500 11px var(--body)}
.hours{display:flex;gap:3px;margin-bottom:10px}
.hcell{flex:1;min-width:0;text-align:center}
.hcell i{display:block;height:34px;border-radius:5px}
.hcell.peak i{box-shadow:inset 0 0 0 2px var(--ink)}
.hcell small{display:block;font-size:10.5px;color:var(--muted);margin-top:4px;height:14px}
.tline{display:flex;flex-direction:column;gap:2px;max-height:430px;overflow:auto}
.trow{display:grid;grid-template-columns:56px 1fr auto;gap:12px;align-items:center;width:100%;text-align:left;border:0;background:transparent;color:var(--ink);font:inherit;padding:10px 8px;border-radius:10px;cursor:pointer}
.trow:hover{background:var(--soft)}
.trow>b{font-variant-numeric:tabular-nums;font-size:15px}
.trow .tn{font-weight:600}
.trow small{color:var(--muted);font-size:13px}
.trow.past{opacity:.55}
.nowrow{display:flex;align-items:center;gap:8px;margin:4px 0;color:#dc2626;font:700 12px var(--body)}
.nowrow i{flex:1;height:2px;background:#dc2626;border-radius:2px}
.att{display:flex;flex-direction:column;gap:4px}
.arow{display:flex;align-items:center;gap:12px;padding:10px 8px;border-radius:10px;cursor:pointer}
.arow:hover{background:var(--soft)}
.a-ic{display:grid;place-items:center;width:36px;height:36px;border-radius:10px;background:#eef4ff;color:#1d4ed8;flex:none}
.dark .a-ic{background:#172554;color:#bfdbfe}
.a-b{flex:1;min-width:0}.a-b b{display:block}.a-b small{color:var(--muted);font-size:13px}
.allgood{display:flex;gap:12px;align-items:center;padding:6px}
.allgood>.icon{font-size:22px;color:#16a34a}
.nb-t{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.nb-n{font:700 11.5px var(--body);background:var(--accent);color:var(--on-accent);border-radius:999px;padding:2px 7px}
.nb-n:empty{display:none}

/* manager: tables, board */
.seg{display:inline-flex;border:1px solid var(--line);border-radius:12px;padding:3px;background:var(--surface);gap:2px}
.seg button{display:inline-flex;align-items:center;gap:6px;border:0;background:transparent;color:var(--muted);font:600 13.5px var(--body);padding:7px 12px;border-radius:9px;cursor:pointer}
.seg button.on{background:var(--soft);color:var(--ink)}
.seg.wide{display:flex;flex-wrap:wrap;margin-bottom:18px}
.seg.wide button{flex:1}
.st-seg button.on{background:var(--pb);color:var(--pc)}
table.data th.num,table.data td.num{text-align:right;font-variant-numeric:tabular-nums}
table.data.sortable th{cursor:pointer;user-select:none}
table.data.sortable th:hover{color:var(--ink)}
table.data th.sorted{color:var(--ink)}
.sort-ic{font-style:normal;font-size:9px;margin-left:5px;opacity:.8}
table.data td small{display:block}
.yes{color:#16a34a}
a.tel{text-decoration:none;font-variant-numeric:tabular-nums;white-space:nowrap}
a.tel:hover{color:var(--accent)}
.card.plain{background:transparent;border:0;box-shadow:none}
.board{display:grid;grid-auto-flow:column;grid-auto-columns:minmax(250px,1fr);gap:14px;overflow-x:auto;padding-bottom:10px}
.col{background:var(--soft);border-radius:var(--radius);padding:10px;min-height:200px;transition:background .15s}
.col.over{background:color-mix(in srgb,var(--accent) 12%,transparent)}
.col-h{display:flex;justify-content:space-between;align-items:center;padding:4px 4px 10px}
.col-b{display:flex;flex-direction:column;gap:10px}
.kcard{background:var(--surface);border:1px solid var(--line);border-radius:12px;padding:12px 14px;box-shadow:var(--shadow);cursor:grab;display:flex;flex-direction:column;gap:6px}
.kcard.drag{opacity:.5}
.kcard:hover{border-color:color-mix(in srgb,var(--accent) 45%,var(--line))}
.k-top{display:flex;justify-content:space-between;gap:8px;align-items:baseline}
.kcard small{display:flex;align-items:center;gap:6px;color:var(--muted);font-size:13px}
.k-items{display:block!important;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.k-foot{display:flex;justify-content:space-between;align-items:center;gap:8px;margin-top:4px}
.k-foot .btn{padding:6px 10px;font-size:12.5px}

/* manager: one record */
.dh-t{margin-right:auto;min-width:0}
.dh-t small{color:var(--muted);font-size:12.5px;font-weight:600;text-transform:uppercase;letter-spacing:.06em}
.drawer .dh-t h3{margin:0;font-size:22px}
.rec-img{border-radius:var(--radius);overflow:hidden;margin-bottom:18px;max-height:220px}
.rec-img img{width:100%;height:100%;object-fit:cover}
.rec-contact{display:flex;gap:10px;flex-wrap:wrap;margin-bottom:18px}
.rec-dl{display:grid;grid-template-columns:1fr 1fr;gap:0 18px;margin:0 0 16px}
.rec-dl>div{padding:10px 0;border-bottom:1px solid var(--line);min-width:0}
.rec-dl>div.full{grid-column:1/-1}
.rec-dl dt{font-size:12px;font-weight:700;letter-spacing:.06em;text-transform:uppercase;color:var(--muted);display:flex;gap:6px;align-items:center}
.rec-dl dd{margin:4px 0 0;font-weight:500;overflow-wrap:anywhere;white-space:pre-wrap}
.mo{color:var(--muted)}
.receipt{background:var(--surface);border:1px solid var(--line);border-radius:var(--radius);padding:18px 20px;margin-bottom:16px;box-shadow:var(--shadow)}
.receipt h4{display:flex;align-items:center;gap:8px;font-size:16px;margin-bottom:10px}
.rl{display:flex;justify-content:space-between;gap:12px;padding:6px 0;font-variant-numeric:tabular-nums}
.rl.sub{color:var(--muted);font-size:14.5px}
.rl.sub:first-of-type,.rl.tot{border-top:1px dashed var(--line);margin-top:6px;padding-top:10px}
.rl.tot{font-weight:800;font-size:18px}
.rec-meta{margin-bottom:12px}
.rec-others h4{font-size:15px;margin:18px 0 8px}
.orow{display:flex;justify-content:space-between;align-items:center;gap:10px;width:100%;text-align:left;border:1px solid var(--line);background:var(--surface);color:var(--ink);font:inherit;padding:10px 14px;border-radius:12px;cursor:pointer;margin-bottom:8px}
.orow:hover{border-color:var(--accent)}
.orow small{display:block;color:var(--muted);font-size:13px}
.tl{position:relative}
.nowline{position:absolute;top:0;bottom:0;width:2px;background:#dc2626;z-index:2;pointer-events:none}
.nowline span{position:absolute;top:2px;left:4px;font:700 10.5px var(--body);color:#fff;background:#dc2626;border-radius:4px;padding:1px 4px}
.gal-edit{display:flex;flex-wrap:wrap;gap:10px;margin-bottom:6px}
.gal-th{position:relative;width:110px;height:84px;border-radius:10px;overflow:hidden;border:1px solid var(--line)}
.gal-th img{width:100%;height:100%;object-fit:cover}
.gal-th .iconbtn{position:absolute;top:4px;right:4px;width:26px;height:26px;font-size:13px}
.gal-add{width:180px}
.gal-add .drop{padding:12px}
.item.out{opacity:.6}
/* sale prices, places left, sold homes */
.price s{color:var(--muted);font-weight:500;font-size:.85em;margin-right:4px}
.price small{font-weight:500;color:var(--muted);font-size:.75em}
.media .flags{position:absolute;top:12px;left:12px;display:flex;flex-wrap:wrap;gap:6px;z-index:1}
.media .flags .dbadge{box-shadow:0 2px 8px rgba(0,0,0,.18)}
.dbadge.sale{background:#dc2626;color:#fff}
.dbadge.places{background:#e8f6ec;color:#166534}
.dbadge.few{background:#fff4e5;color:#9a3412}
.media .flags .dbadge.places{background:#fff;color:#166534}.media .flags .dbadge.few{background:#fff;color:#9a3412}

/* weekly timetable */
.tt{display:grid;grid-template-columns:repeat(auto-fit,minmax(170px,1fr));gap:14px;align-items:start}
.tt-day{background:var(--surface);border:1px solid var(--line);border-radius:var(--radius);padding:14px;box-shadow:var(--shadow);display:flex;flex-direction:column;gap:10px}
.tt-day.today{border-color:var(--accent);box-shadow:0 0 0 3px color-mix(in srgb,var(--accent) 18%,transparent)}
.tt-day h3{font-size:17px;display:flex;align-items:center;gap:8px}
.tt-day h3 span{font:700 11px var(--body);letter-spacing:.06em;text-transform:uppercase;color:var(--on-accent);background:var(--accent);padding:3px 7px;border-radius:999px}
.tt-c{position:relative;border-radius:12px;background:var(--soft);padding:12px;display:flex;flex-direction:column;gap:3px}
.tt-c b{font-family:var(--head);font-weight:var(--head-weight);font-size:16px}
.tt-c small{color:var(--muted);font-size:13px}
.tt-t{display:flex;align-items:baseline;gap:8px;font:700 14px var(--body);color:var(--accent);font-variant-numeric:tabular-nums}
.tt-t small{font-weight:500}
.tt-f{display:flex;align-items:center;justify-content:space-between;gap:8px;margin-top:6px;flex-wrap:wrap}
.tt-f:empty{display:none}
.tt-c.full{opacity:.6}
.tt-c .edit-btn{top:6px;right:6px;width:28px;height:28px;font-size:12px}

/* rooms for a stay */
.stay .avail-ctl{align-items:flex-end}
.stay-sum{margin-left:auto;font-size:15px}
.stay-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(260px,1fr));gap:16px}
.room{border:1.5px solid var(--line);border-radius:var(--radius);overflow:hidden;background:var(--surface);display:flex;flex-direction:column;transition:transform .2s,box-shadow .2s}
.room:hover{transform:translateY(-2px);box-shadow:var(--shadow-lg)}
.room.off{opacity:.55}.room.off:hover{transform:none;box-shadow:none}
.room.picked{border-color:var(--accent);box-shadow:0 0 0 4px color-mix(in srgb,var(--accent) 20%,transparent)}
.room-img{aspect-ratio:16/10;background:var(--soft);overflow:hidden}
.room-img img,.room-img .ph{width:100%;height:100%;object-fit:cover}
.room-b{padding:16px 18px 18px;display:flex;flex-direction:column;gap:8px;flex:1}
.room-b .top{display:flex;justify-content:space-between;gap:10px;align-items:flex-start}
.room-b h3{font-size:19px}
.room-b .desc{color:var(--muted);font-size:14.5px}
.room-b .meta{display:flex;flex-wrap:wrap;gap:6px}
.room-b .foot{margin-top:auto;padding-top:8px;display:flex;align-items:center;justify-content:space-between;gap:10px}

/* manager: week */
.wk{overflow-x:auto;border:1px solid var(--line);border-radius:12px}
.wk table{border-collapse:collapse;width:100%;min-width:760px;table-layout:fixed;font-size:13px}
.wk th,.wk td{border-bottom:1px solid var(--line);border-right:1px solid var(--line);vertical-align:top}
.wk th{background:var(--soft);color:var(--muted);font-weight:600;padding:8px 6px;white-space:nowrap}
.wk th small{display:block;color:#b91c1c;font-size:11px}
.wk th.today{color:var(--accent);background:color-mix(in srgb,var(--accent) 10%,var(--surface))}
.wk th.hr{width:62px;text-align:right;font-variant-numeric:tabular-nums}
.wk td{height:46px;padding:3px;cursor:pointer}
.wk td:hover{background:var(--soft)}
.wk td.past{background:color-mix(in srgb,var(--soft) 55%,transparent)}
.wk td.shut,.wk th.shut{background:repeating-linear-gradient(45deg,transparent,transparent 5px,#fde2e2 5px,#fde2e2 10px);cursor:default}
.wk-b{display:block;width:100%;text-align:left;border:0;border-left:3px solid var(--pc,var(--accent));background:var(--pb,var(--soft));color:var(--ink);font:500 12px/1.3 var(--body);padding:4px 6px;border-radius:6px;margin-bottom:3px;cursor:pointer;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.wk-b b{font-variant-numeric:tabular-nums}
.wk-b small{display:block;color:var(--muted);font-size:11px}
.wk-b:hover{filter:brightness(.97)}

/* manager: month */
.cal{background:var(--surface);border:1px solid var(--line);border-radius:var(--radius);box-shadow:var(--shadow);padding:16px}
.cal-h{display:flex;align-items:center;gap:10px;margin-bottom:12px;flex-wrap:wrap}
.cal-h h3{font-size:20px;min-width:170px;text-align:center}
.cal-h .small{margin-left:auto}
.cal-g{display:grid;grid-template-columns:repeat(7,minmax(0,1fr));border-top:1px solid var(--line);border-left:1px solid var(--line)}
.cal-dn{padding:8px;font-size:12px;font-weight:700;color:var(--muted);text-transform:uppercase;letter-spacing:.06em;border-right:1px solid var(--line);border-bottom:1px solid var(--line);background:var(--soft)}
.cal-d{min-height:104px;padding:6px;border-right:1px solid var(--line);border-bottom:1px solid var(--line);display:flex;flex-direction:column;gap:3px;cursor:pointer;min-width:0}
.cal-d:hover{background:color-mix(in srgb,var(--soft) 70%,transparent)}
.cal-d.other{background:color-mix(in srgb,var(--soft) 45%,transparent)}.cal-d.other .cal-n{opacity:.45}
.cal-d.today .cal-n{background:var(--accent);color:var(--on-accent)}
.cal-n{align-self:flex-start;font:600 13px/1 var(--body);padding:5px 7px;border-radius:999px;font-variant-numeric:tabular-nums}
.cal-b{display:block;width:100%;text-align:left;border:0;border-left:3px solid var(--pc,var(--accent));background:var(--pb,var(--soft));color:var(--ink);font:500 12px/1.3 var(--body);padding:3px 6px;border-radius:5px;cursor:pointer;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.cal-more{border:0;background:transparent;color:var(--accent);font:600 12px var(--body);text-align:left;cursor:pointer;padding:2px 4px}
@media (max-width:700px){.cal-d{min-height:70px}.cal-b{font-size:10.5px;padding:2px 4px}}

/* manager: rooms by night */
.occ th small{display:block;font-size:13px;color:var(--ink)}
.occ th.today{color:var(--accent);background:color-mix(in srgb,var(--accent) 10%,var(--surface))}
.occ th{height:44px}
.occ td.b{background:var(--pc,var(--accent));color:#fff}
.occ td.b.t-blue{background:#3b6fd8}.occ td.b.t-green{background:#0f8a62}.occ td.b.t-amber{background:#c2650a}.occ td.b.t-grey{background:#71717a}
.occ td.shut,.occ th.shut{background:repeating-linear-gradient(45deg,transparent,transparent 5px,#fde2e2 5px,#fde2e2 10px)}
.occ-rate{font-size:14px;color:var(--muted)}.occ-rate b{color:var(--ink);font-size:18px}

/* manager: takings by service */
.svc{display:flex;flex-direction:column;gap:12px;cursor:pointer}
.svc-r{display:grid;grid-template-columns:minmax(120px,1.1fr) 2fr auto;gap:12px;align-items:center}
.svc-n{display:flex;flex-direction:column;min-width:0}.svc-n b{font-size:14px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.svc-bar{height:10px;border-radius:99px;background:var(--soft);overflow:hidden}
.svc-bar i{display:block;height:100%;border-radius:99px;background:var(--accent)}
.svc-r .num{font-variant-numeric:tabular-nums;font-size:14px}
''';

const appJs = r'''
const MANAGER = location.pathname === '/manage';
const KEY_NAME = 'appkey_' + location.port;
let SPEC = null, KEY = localStorage.getItem(KEY_NAME) || '';
const cache = {};

// ---------- small helpers ----------
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'}[c]));
const el = (html) => { const t = document.createElement('template'); t.innerHTML = html.trim(); return t.content.firstElementChild; };
const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];
const I = {
  search: '<circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/>', menu: '<path d="M4 7h16M4 12h16M4 17h16"/>', x: '<path d="M18 6 6 18M6 6l12 12"/>',
  plus: '<path d="M12 5v14M5 12h14"/>', minus: '<path d="M5 12h14"/>', check: '<path d="m5 12 5 5L20 7"/>', arrow: '<path d="M5 12h14M13 6l6 6-6 6"/>',
  clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>', phone: '<path d="M22 16.9v3a2 2 0 0 1-2.2 2 19.8 19.8 0 0 1-8.6-3.1 19.5 19.5 0 0 1-6-6A19.8 19.8 0 0 1 2.1 4.2 2 2 0 0 1 4.1 2h3a2 2 0 0 1 2 1.7c.1.9.4 1.8.7 2.7a2 2 0 0 1-.5 2.1L8 9.8a16 16 0 0 0 6 6l1.3-1.3a2 2 0 0 1 2.1-.4c.9.3 1.8.6 2.7.7a2 2 0 0 1 1.7 2z"/>',
  mail: '<rect x="3" y="5" width="18" height="14" rx="2"/><path d="m3 7 9 6 9-6"/>', pin: '<path d="M12 22s7-6.2 7-12a7 7 0 0 0-14 0c0 5.8 7 12 7 12z"/><circle cx="12" cy="10" r="2.5"/>',
  cal: '<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M16 3v4M8 3v4M3 10h18"/>', tag: '<path d="M20.6 13.4 13.4 20.6a2 2 0 0 1-2.8 0L3 13V3h10l7.6 7.6a2 2 0 0 1 0 2.8z"/><circle cx="7.5" cy="7.5" r="1.5"/>',
  image: '<rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-5-5L5 21"/>',
  bag: '<path d="M6 7h12l-1 14H7L6 7z"/><path d="M9 7a3 3 0 0 1 6 0"/>', home: '<path d="m3 11 9-8 9 8"/><path d="M5 10v10h14V10"/>',
  file: '<path d="M14 3H6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9z"/><path d="M14 3v6h6"/>',
  out: '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9"/>', ext: '<path d="M14 4h6v6M20 4l-9 9"/><path d="M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5"/>',
  trash: '<path d="M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13"/>', upload: '<path d="M12 16V4M7 9l5-5 5 5"/><path d="M4 16v3a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-3"/>', bell: '<path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9"/><path d="M10.3 21a1.9 1.9 0 0 0 3.4 0"/>',
  palette: '<circle cx="13.5" cy="6.5" r="1"/><circle cx="17.5" cy="10.5" r="1"/><circle cx="8.5" cy="7.5" r="1"/><circle cx="6.5" cy="12.5" r="1"/><path d="M12 2a10 10 0 0 0 0 20c1 0 1.8-.8 1.8-1.8 0-.5-.2-.9-.5-1.2-.3-.3-.5-.8-.5-1.2 0-1 .8-1.8 1.8-1.8H16a6 6 0 0 0 6-6c0-4.4-4.5-8-10-8z"/>',
  list: '<path d="M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01"/>',
  users: '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.9M16 3.1a4 4 0 0 1 0 7.8"/>',
  board: '<rect x="3" y="4" width="5" height="16" rx="1.5"/><rect x="10" y="4" width="5" height="11" rx="1.5"/><rect x="17" y="4" width="4" height="7" rx="1.5"/>',
  download: '<path d="M12 4v12M7 11l5 5 5-5"/><path d="M4 18v1a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-1"/>', edit: '<path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z"/>',
  lock: '<rect x="4" y="11" width="16" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>', star: '<path d="m12 3 2.8 5.7 6.2.9-4.5 4.4 1.1 6.2L12 17.3 6.4 20.2l1.1-6.2L3 9.6l6.2-.9z"/>',
  leaf: '<path d="M11 20A7 7 0 0 1 9.8 6.1C15.5 5 17 4.5 19 2c1 2 2 4.2 2 8 0 5.5-4.8 10-10 10z"/><path d="M2 21c0-3 1.9-5.4 5.1-6"/>',
  truck: '<path d="M3 6h11v10H3zM14 9h4l3 3v4h-7"/><circle cx="7" cy="18" r="2"/><circle cx="17" cy="18" r="2"/>', gift: '<rect x="3" y="8" width="18" height="4" rx="1"/><path d="M12 8v13M5 12v9h14v-9M7.5 8a2.5 2.5 0 0 1 0-5C10 3 12 8 12 8s2-5 4.5-5a2.5 2.5 0 0 1 0 5"/>',
  glass: '<path d="M8 22h8M12 15v7M6 3h12l-1 7a5 5 0 0 1-10 0z"/>', award: '<circle cx="12" cy="9" r="6"/><path d="m8.5 14-1.5 8 5-3 5 3-1.5-8"/>',
  chef: '<path d="M6 13.9A4 4 0 0 1 7 6a5 5 0 0 1 10 0 4 4 0 0 1 1 7.9V20H6z"/><path d="M6 17h12"/>', flame: '<path d="M12 22a7 7 0 0 0 7-7c0-4-3-6-4-10-2 2-3 4-3 6-1-1-2-2-2-4-2 2-5 5-5 8a7 7 0 0 0 7 7z"/>',
  heart: '<path d="M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1-1.1a5.5 5.5 0 0 0-7.8 7.8L12 21l8.8-8.6a5.5 5.5 0 0 0 0-7.8z"/>', sparkle: '<path d="M12 3v4M12 17v4M3 12h4M17 12h4M6 6l2.5 2.5M15.5 15.5 18 18M6 18l2.5-2.5M15.5 8.5 18 6"/>',
  left: '<path d="m15 18-6-6 6-6"/>', right: '<path d="m9 18 6-6-6-6"/>', chart: '<path d="M3 3v18h18"/><path d="M8 17v-5M13 17V8M18 17v-9"/>',
};
const icon = (n) => '<svg class="icon" viewBox="0 0 24 24">' + (I[n] || I.tag) + '</svg>';

async function api(path, opts = {}) {
  const r = await fetch('/api/' + path, {...opts, headers: {'Content-Type': 'application/json', 'X-Key': KEY, ...(opts.headers || {})}});
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(j.error || ('Something went wrong (' + r.status + ')'));
  return j;
}
const table = (id) => SPEC.tables.find((t) => t.id === id);
const visible = (t) => t.fields.filter((f) => MANAGER || !f.manager_only);
const labelOf = (t) => { const f = t.fields[0]; if (f && !f.manager_only && !['link', 'links', 'longtext', 'yesno', 'image'].includes(f.type)) return f.id; return (t.fields.find((x) => x.type === 'text') || f || {id: 'id'}).id; };
const firstOf = (t, type) => visible(t).find((f) => f.type === type);
async function rows(id, fresh) { if (fresh || !cache[id]) cache[id] = await api('t/' + id); return cache[id]; }
async function byId(id) { const m = {}; for (const r of await rows(id)) m[r.id] = r; return m; }
const nameOf = (t, r) => r ? String(r[labelOf(t)] ?? '#' + r.id) : '';
const hue = (s) => { let h = 0; for (const c of String(s)) h = (h * 31 + c.charCodeAt(0)) % 360; return h; };
const ph = (name, cls = '') => '<div class="ph ' + cls + '" style="--h:' + hue(name) + '">' + esc((String(name).trim()[0] || '•').toUpperCase()) + '</div>';
const media = (url, name, cls = '') => url ? '<img src="' + esc(url) + '" alt="' + esc(name) + '" loading="lazy">' : ph(name, cls);
function money(v) {
  const n = Number(v || 0), c = (SPEC.site || {}).currency || '';
  const s = n % 1 === 0 ? String(n) : n.toFixed(2);
  return c ? (/^[A-Za-z]{2,}$/.test(c) ? s + ' ' + c : c + s) : s;
}
function fmt(f, v, links) {
  if (v === null || v === undefined || v === '') return '';
  const nm = (id) => { const t = table(f.link); return t && links && links[f.link] && links[f.link][id] ? nameOf(t, links[f.link][id]) : String(id); };
  switch (f.type) {
    case 'money': return money(v);
    case 'yesno': return v ? 'Yes' : 'No';
    case 'date': { const d = new Date(v + 'T00:00'); return isNaN(d) ? v : d.toLocaleDateString(undefined, {weekday: 'short', day: 'numeric', month: 'short'}); }
    case 'datetime': { const d = new Date(String(v).replace(' ', 'T')); return isNaN(d) ? v : d.toLocaleString(undefined, {day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit'}); }
    case 'link': return nm(v);
    case 'links': return Array.isArray(v) ? v.map((x) => typeof x === 'object' ? x.qty + ' × ' + nm(x.id) : nm(x)).join(', ') : '';
    case 'image': return '';
    default: return String(v);
  }
}
async function linkMaps(t) { const m = {}; for (const f of t.fields) if (f.link && table(f.link) && !m[f.link]) { try { m[f.link] = await byId(f.link); } catch (_) { m[f.link] = {}; } } return m; }
function toast(msg) { const t = el('<div class="toast">' + icon('check') + '<span>' + esc(msg) + '</span></div>'); document.body.append(t); requestAnimationFrame(() => requestAnimationFrame(() => t.classList.add('show'))); setTimeout(() => { t.classList.remove('show'); setTimeout(() => t.remove(), 400); }, 2600); }
const fieldIcon = (f) => ({time: 'clock', datetime: 'cal', date: 'cal', phone: 'phone', email: 'mail', money: 'tag', link: 'list', links: 'list'})[f.type] || (/address|location|where/.test(f.id) ? 'pin' : 'tag');
const monogram = () => { const s = SPEC.site || {}; return s.logo ? '<img src="' + esc(s.logo) + '" alt="">' : '<div class="monogram">' + esc((SPEC.name[0] || '?').toUpperCase()) + '</div>'; };

/// Opening hours: a one-record table with two times (opens, closes).
async function hours() {
  for (const t of SPEC.tables) {
    if (t.kind !== 'single') continue;
    const times = visible(t).filter((f) => f.type === 'time');
    if (times.length < 2) continue;
    const r = (await rows(t.id).catch(() => []))[0];
    if (!r || !r[times[0].id] || !r[times[1].id]) continue;
    const [o, c] = [r[times[0].id], r[times[1].id]];
    const now = new Date(), m = now.getHours() * 60 + now.getMinutes();
    const mins = (s) => { const [h, mm] = String(s).split(':').map(Number); return h * 60 + (mm || 0); };
    const open = mins(c) > mins(o) ? m >= mins(o) && m < mins(c) : m >= mins(o) || m < mins(c);
    const daysF = visible(t).find((f) => f.type === 'text');
    return {open: o, close: c, isOpen: open, table: t, times, days: daysF ? r[daysF.id] : ''};
  }
  return null;
}

// ---------- pictures ----------
async function shrink(file) {
  if (!/^image\//.test(file.type)) throw new Error('Choose a picture (JPG, PNG or WebP).');
  if (file.type === 'image/png' && file.size < 400000) return file;
  const img = await createImageBitmap(file).catch(() => null);
  if (!img) return file;
  const k = Math.min(1, 1800 / Math.max(img.width, img.height));
  const c = document.createElement('canvas'); c.width = Math.round(img.width * k); c.height = Math.round(img.height * k);
  c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
  return await new Promise((res) => c.toBlob(res, 'image/jpeg', 0.86));
}
async function upload(file) {
  const blob = await shrink(file);
  const r = await fetch('/api/_upload', {method: 'POST', body: blob, headers: {'Content-Type': blob.type || 'image/jpeg', 'X-Key': KEY}});
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(j.error || 'Upload failed');
  return j.url;
}
/// A picture picker: drop or click; shows the picture with Change / Remove.
function imageInput(value, onChange) {
  const box = el('<div></div>');
  let v = value || '';
  const input = el('<input type="file" accept="image/*" hidden>');
  const take = async (file) => { box.style.opacity = .5; try { v = await upload(file); onChange(v); } catch (e) { toast(e.message); } box.style.opacity = 1; draw(); };
  const draw = () => {
    box.innerHTML = '';
    if (v) {
      const p = el('<div class="drop-prev"><img src="' + esc(v) + '" alt=""><div class="row"><button type="button" class="btn sm">Change</button><button type="button" class="btn sm danger">Remove</button></div></div>');
      $$('button', p)[0].onclick = () => input.click();
      $$('button', p)[1].onclick = () => { v = ''; onChange(v); draw(); };
      box.append(p);
    } else {
      const d = el('<div class="drop">' + icon('upload') + '<b>Add a photo</b><div class="hint">Click or drop a picture here</div></div>');
      d.onclick = () => input.click();
      d.ondragover = (e) => { e.preventDefault(); d.classList.add('over'); };
      d.ondragleave = () => d.classList.remove('over');
      d.ondrop = (e) => { e.preventDefault(); d.classList.remove('over'); if (e.dataTransfer.files[0]) take(e.dataTransfer.files[0]); };
      box.append(d);
    }
    box.append(input);
  };
  input.onchange = () => input.files[0] && take(input.files[0]);
  draw();
  return box;
}

// ---------- form fields ----------
/// One input for a field. Returns {node, get(), f}.
async function fieldInput(f, value, ctx = {}) {
  const wrap = el('<div class="field' + (['longtext', 'links', 'image'].includes(f.type) || ctx.full ? ' full' : '') + '"><label class="lbl">' + esc(f.label) + (f.required ? ' <span class="req">*</span>' : '') + '</label></div>');
  const add = (n) => { wrap.append(n); return n; };
  let get, set = () => {};
  const pills = (opts, cur, multi, onPick) => {
    const p = add(el('<div class="pills"></div>'));
    opts.forEach(([val, label]) => { const b = el('<button type="button" class="pill-opt">' + esc(label) + '</button>'); b.dataset.v = val; b.onclick = () => onPick(val, p); p.append(b); });
    return p;
  };
  switch (f.type) {
    case 'longtext': { const n = add(el('<textarea></textarea>')); n.value = value ?? ''; get = () => n.value; break; }
    case 'number': case 'money': { const n = add(el('<input type="number" step="any" inputmode="decimal">')); n.value = value ?? ''; get = () => n.value; set = (v) => n.value = v ?? ''; break; }
    case 'date': case 'time': case 'email': { const n = add(el('<input type="' + f.type + '">')); n.value = value ?? ''; get = () => n.value; set = (v) => n.value = v ?? ''; break; }
    case 'datetime': { const n = add(el('<input type="datetime-local">')); n.value = value ? String(value).replace(' ', 'T').slice(0, 16) : ''; get = () => n.value.replace('T', ' '); break; }
    case 'phone': { const n = add(el('<input type="tel" autocomplete="tel">')); n.value = value ?? ''; get = () => n.value; break; }
    case 'yesno': { const n = add(el('<label class="switch"><input type="checkbox"><i></i><span></span></label>')); const c = $('input', n); c.checked = !!value; const sync = () => $('span', n).textContent = c.checked ? 'Yes' : 'No'; c.onchange = sync; sync(); get = () => c.checked; break; }
    case 'choice': {
      if (f.options.length <= 6) {
        let cur = value ?? '';
        const p = pills(f.options.map((o) => [o, o]), cur, false, (v, p) => { cur = cur === v ? '' : v; $$('.pill-opt', p).forEach((x) => x.classList.toggle('on', x.dataset.v === cur)); });
        $$('.pill-opt', p).forEach((x) => x.classList.toggle('on', x.dataset.v === cur));
        get = () => cur;
      } else { const n = add(el('<select><option value="">Choose…</option>' + f.options.map((o) => '<option' + (o === value ? ' selected' : '') + '>' + esc(o) + '</option>').join('') + '</select>')); get = () => n.value; }
      break;
    }
    case 'image': { let v = value || ''; add(imageInput(v, (x) => v = x)); get = () => v; break; }
    case 'link': {
      const t = table(f.link); const list = t ? await rows(f.link).catch(() => []) : [];
      if (list.length && list.length <= 12) {
        let cur = value ?? null;
        const p = pills(list.map((r) => [String(r.id), nameOf(t, r)]), cur, false, (v, p) => { cur = String(cur) === v ? null : Number(v); $$('.pill-opt', p).forEach((x) => x.classList.toggle('on', x.dataset.v === String(cur))); });
        $$('.pill-opt', p).forEach((x) => x.classList.toggle('on', x.dataset.v === String(cur)));
        get = () => cur;
        set = (v) => { cur = v ?? null; $$('.pill-opt', p).forEach((x) => x.classList.toggle('on', x.dataset.v === String(cur))); };
      } else { const n = add(el('<select><option value="">' + (ctx.optional ? 'Any free one' : 'Choose…') + '</option>' + list.map((r) => '<option value="' + r.id + '"' + (r.id === value ? ' selected' : '') + '>' + esc(nameOf(t, r)) + '</option>').join('') + '</select>')); get = () => n.value ? Number(n.value) : null; set = (v) => n.value = v ?? ''; }
      break;
    }
    case 'links': {
      const t = table(f.link); const list = t ? await rows(f.link).catch(() => []) : [];
      const sel = ctx.sel || {};
      for (const x of (Array.isArray(value) ? value : [])) typeof x === 'object' ? sel[x.id] = x.qty : sel[x] = 1;
      if (!f.qty) {
        const p = pills(list.map((r) => [String(r.id), nameOf(t, r)]), null, true, (v, p) => { sel[v] ? delete sel[v] : sel[v] = 1; $$('.pill-opt', p).forEach((x) => x.classList.toggle('on', !!sel[x.dataset.v])); });
        $$('.pill-opt', p).forEach((x) => x.classList.toggle('on', !!sel[x.dataset.v]));
        get = () => Object.keys(sel).map(Number);
      } else {
        // Picked items with steppers, plus a list to add more; prices and total when there are prices.
        const priceF = priceFieldOf(t), imgF = firstOf(t, 'image');
        const box = add(el('<div></div>')), adder = el('<select style="margin-top:14px"><option value="">+ Add ' + esc(t.title.toLowerCase()) + '…</option>' + list.filter((r) => !soldOut(t, r)).map((r) => '<option value="' + r.id + '">' + esc(nameOf(t, r)) + (priceF ? ' — ' + money(priceNow(t, r)) : '') + '</option>').join('') + '</select>');
        const draw = () => {
          const items = Object.entries(sel).filter(([, q]) => q > 0);
          let h = items.length ? '' : '<div class="cart-empty">' + (ctx.hasList ? 'Tap “Add” on anything above, or choose here.' : 'Nothing chosen yet.') + '</div>', sum = 0;
          for (const [id, q] of items) {
            const r = list.find((x) => String(x.id) === id); if (!r) continue;
            const p = priceF ? Number(priceNow(t, r) || 0) : 0; sum += p * q;
            h += '<div class="cart-line"><div class="thumb">' + media(imgF && r[imgF.id], nameOf(t, r), 'sm') + '</div><div class="nm">' + esc(nameOf(t, r)) + (priceF ? '<small>' + money(p) + '</small>' : '') + '</div><div class="stepper"><button type="button" data-d="-1" data-id="' + id + '">' + icon('minus') + '</button><b>' + q + '</b><button type="button" data-d="1" data-id="' + id + '">' + icon('plus') + '</button></div></div>';
          }
          // Delivery: its fee on top, and the least an order may come to.
          const ex = ctx.extras ? ctx.extras() : {fee: 0, min: 0, delivery: false};
          const fee = ex.delivery ? ex.fee : 0;
          if (priceF && items.length) {
            if (fee) h += '<div class="sub-line"><span>Items</span><span>' + money(sum) + '</span></div><div class="sub-line"><span>Delivery</span><span>' + money(fee) + '</span></div>';
            h += '<div class="total"><span>Total</span><span class="price">' + money(sum + fee) + '</span></div>';
            if (ex.delivery && ex.min && sum < ex.min) h += '<div class="minwarn">The minimum for delivery is ' + money(ex.min) + ': add ' + money(Math.round((ex.min - sum) * 100) / 100) + ' more, or choose collection.</div>';
          }
          if (priceF && !ex.delivery && (ex.fee || ex.min) && ex.canDeliver) h += '<div class="cart-hint">' + icon('truck') + ' Delivery ' + (ex.fee ? money(ex.fee) : 'free') + (ex.min ? ' · minimum order ' + money(ex.min) : '') + '</div>';
          box.innerHTML = h; box.append(adder);
          ctx.sum = sum;
          ctx.onChange && ctx.onChange(items.reduce((a, [, q]) => a + q, 0), sum + fee);
        };
        box.onclick = (e) => { const b = e.target.closest('button[data-id]'); if (!b) return; const id = b.dataset.id; sel[id] = Math.max(0, (sel[id] || 0) + Number(b.dataset.d)); if (!sel[id]) delete sel[id]; draw(); };
        adder.onchange = () => { if (adder.value) { sel[adder.value] = (sel[adder.value] || 0) + 1; adder.value = ''; draw(); } };
        ctx.redraw = draw; draw();
        get = () => Object.entries(sel).filter(([, q]) => q > 0).map(([id, q]) => ({id: Number(id), qty: q}));
      }
      break;
    }
    default: { const n = add(el('<input type="text">')); n.value = value ?? ''; if (/name/.test(f.id)) n.autocomplete = 'name'; get = () => n.value; }
  }
  return {node: wrap, get, set, f};
}

// ---------- statuses, orders, people ----------
/// A colour for a status, by what it means: new (blue), in hand (amber), good (green), over (grey), off (red).
function tone(o) {
  const s = String(o || '').toLowerCase();
  if (/cancel|no.?show|declin|reject|refund/.test(s)) return 'red';
  if (/unpaid|prepar|packing|progress|workshop|cooking|out for|deposit|waiting|seated|checked in/.test(s)) return 'amber';
  if (/done|finish|complet|collected|delivered|redeem|closed|served|viewed|attended|checked out/.test(s)) return 'grey';
  if (/ready|confirm|paid|sent|booked|offer/.test(s)) return 'green';
  return 'blue';
}
const pill = (o) => o ? '<span class="spill t-' + tone(o) + '">' + esc(o) + '</span>' : '';
/// The same number however it's written (07700 900124 = +447700900124).
const digits9 = (p) => { const d = String(p || '').replace(/\D/g, ''); return d.length >= 9 ? d.slice(-9) : ''; };
const phoneOf = (t) => t.fields.find((f) => f.type === 'phone');
const dateOf = (t) => t.fields.find((f) => f.type === 'date' || f.type === 'datetime');
const timeOf = (t) => t.fields.find((f) => f.type === 'time');
const siteNum = (k) => { const n = parseFloat(String((SPEC.site || {})[k] || '').replace(/[^0-9.]/g, '')); return isNaN(n) ? 0 : n; };
const isDelivery = (t, r) => t.fields.some((f) => f.type === 'choice' && !f.manager_only && /^deliver/i.test(String(r[f.id] || '')));
const isOrders = (t) => t.fields.some((f) => f.type === 'links' && f.qty && table(f.link)?.fields.some((x) => x.type === 'money'));
/// An order's lines and total (with the delivery fee on a delivery), from the prices of what's in it.
function orderCalc(t, r, links) {
  let items = 0, any = false; const lines = [];
  for (const f of t.fields) {
    if (f.type !== 'links' || !f.qty || !Array.isArray(r[f.id])) continue;
    const lt = table(f.link), pf = lt && lt.fields.find((x) => x.type === 'money'); if (!pf) continue;
    for (const x of r[f.id]) { const it = links[f.link]?.[x.id]; if (!it) continue; const p = Number(priceNow(lt, it) || 0), q = Number(x.qty || 1); items += p * q; any = true; lines.push({name: nameOf(lt, it), qty: q, price: p}); }
  }
  if (!any) { const tf = t.fields.find((f) => f.type === 'money' && /^(order_)?total$/.test(f.id)); return tf && r[tf.id] != null ? {items: Number(r[tf.id]), fee: 0, total: Number(r[tf.id]), lines} : null; }
  const fee = isDelivery(t, r) ? siteNum('delivery_fee') : 0;
  return {items, fee, total: Math.round((items + fee) * 100) / 100, lines};
}
/// Days off (holidays): a list with a date, called closures / holidays / closed days.
const isClosures = (t) => /closure|holiday|closed/i.test(t.id + ' ' + (t.purpose || '')) && t.fields.some((f) => f.type === 'date');

// ---------- menu, gallery, reviews, contact, highlights ----------
const BADGES = [[/^vegan$/, 'Vegan', 'vg'], [/vegetarian|^veg$/, 'Vegetarian', 'v'], [/gluten/, 'Gluten free', 'gf'], [/spicy|hot|chilli/, 'Spicy', 'sp'], [/popular|favourite|bestseller|signature/, 'Popular', 'pop'], [/featured/, 'Featured', 'pop'], [/^new$/, 'New', 'new']];
const badgesOf = (t, r) => t.fields.filter((f) => f.type === 'yesno' && !f.manager_only && r[f.id] === true && !/stock|availab|sold/.test(f.id))
  .map((f) => { const b = BADGES.find(([re]) => re.test(f.id)); return '<span class="dbadge ' + (b ? b[2] : '') + '">' + (b && b[2] === 'pop' ? icon('star') : '') + esc(b ? b[1] : f.label) + '</span>'; }).join('');
/// A home that is sold or let (its status), or something marked out of stock / sold out.
const goneOf = (t, r) => { const f = t.fields.find((x) => x.type === 'choice' && x.id === 'status' && !x.manager_only); return f && /^(sold|let)$/i.test(String(r[f.id] || '')) ? r[f.id] : ''; };
const soldOut = (t, r) => !!goneOf(t, r) || t.fields.some((f) => f.type === 'yesno' && ((/stock|availab/.test(f.id) && r[f.id] === false) || (/sold/.test(f.id) && r[f.id] === true)));
/// Prices: the usual one, and a sale price that wins when it is lower ("£4 £3.20").
const SALE = /sale|offer|special|discount/;
const priceFieldOf = (t) => visible(t).find((f) => f.type === 'money' && !SALE.test(f.id)) || visible(t).find((f) => f.type === 'money');
const saleFieldOf = (t) => visible(t).find((f) => f.type === 'money' && SALE.test(f.id) && f !== priceFieldOf(t));
function priceNow(t, r) { const p = priceFieldOf(t), s = saleFieldOf(t); const base = p ? r[p.id] : null, sv = s ? r[s.id] : null; return sv != null && sv !== '' && Number(sv) > 0 && (base == null || Number(sv) < Number(base)) ? Number(sv) : base; }
function priceHtml(t, r) { const p = priceFieldOf(t); if (!p || r[p.id] === undefined || r[p.id] === null || r[p.id] === '') return ''; const now = priceNow(t, r); return '<span class="price">' + (Number(now) !== Number(r[p.id]) ? '<s>' + money(r[p.id]) + '</s> ' : '') + money(now) + '</span>'; }
const onSale = (t, r) => { const p = priceFieldOf(t); return p && r[p.id] != null && Number(priceNow(t, r)) < Number(r[p.id]); };
/// Places left on classes, courses and events (counts only, never who): "3 places left", "Full", "Sold out".
async function placesOf(t) { if (!(SPEC.places || []).includes(t.id)) return null; try { return await api('_places/' + t.id); } catch (_) { return null; } }
const fullOf = (p, id) => { const x = p && p.items[id]; return !!x && x.left <= 0; };
function placesBadge(p, id) {
  const x = p && p.items[id]; if (!x) return '';
  if (x.left <= 0) return '<span class="dbadge out">' + (p.word === 'tickets' ? 'Sold out' : 'Full') + '</span>';
  const few = x.left <= Math.max(3, Math.round(x.capacity * .25));
  if (p.word === 'tickets' && !few) return '';
  return '<span class="dbadge places' + (few ? ' few' : '') + '">' + (few ? 'Only ' : '') + x.left + ' ' + (x.left === 1 ? p.word.replace(/s$/, '') : p.word) + ' left</span>';
}

/// A printed-menu look: a section per category (headings stay in view), dotted lines to the price,
/// dietary badges and allergens.
function menuBlock(b, t, all, pick, state) {
  const priceF = visible(t).find((f) => f.type === 'money'), descF = visible(t).find((f) => f.type === 'longtext'), catF = visible(t).find((f) => f.type === 'choice'), imgF = firstOf(t, 'image');
  const allergF = visible(t).find((f) => /allerg/.test(f.id) && f.type !== 'yesno');
  const cats = catF ? [...catF.options.filter((o) => all.some((r) => r[catF.id] === o)), ...(all.some((r) => !catF.options.includes(r[catF.id])) ? [''] : [])] : [''];
  const n = el('<section class="sec menu-sec"><div class="wrap"><div class="sec-head"><h2>' + esc(b.title || t.title) + '</h2>' + (SPEC.manager ? '<div class="sec-actions"><button class="btn sm" data-a="photo">' + icon('image') + ' Add from a photo</button><button class="btn primary sm" data-a="add">' + icon('plus') + ' Add</button></div>' : '') + '</div>'
    + (cats.length > 1 ? '<nav class="menu-nav">' + cats.map((c, i) => '<a href="#m-' + t.id + '-' + i + '">' + esc(c || 'More') + '</a>').join('') + '</nav>' : '')
    + '<div class="menu-cols"></div>' + (allergF ? '<p class="menu-note">' + icon('leaf') + ' Tell us about any allergy or intolerance when you order: the kitchen will look after you.</p>' : '') + '</div></section>');
  if (SPEC.manager) { $('[data-a=add]', n).onclick = () => drawer(t, null, () => site()); $('[data-a=photo]', n).onclick = () => importPhoto(t, () => site()); }
  const box = $('.menu-cols', n);
  const draw = () => {
    box.innerHTML = '';
    cats.forEach((c, i) => {
      const items = all.filter((r) => !catF || (c ? r[catF.id] === c : !catF.options.includes(r[catF.id])));
      if (!items.length) return;
      const sec = el('<section class="menu-cat" id="m-' + t.id + '-' + i + '">' + (catF ? '<h3 class="menu-h">' + esc(c || 'More') + '</h3>' : '') + '<div class="menu-list"></div></section>');
      for (const r of items) {
        const out = soldOut(t, r), q2 = state.sel[t.id]?.[r.id] || 0;
        const row = el('<article class="mi' + (out ? ' out' : '') + '">' + (imgF && r[imgF.id] ? '<div class="mi-img">' + media(r[imgF.id], nameOf(t, r)) + '</div>' : '')
          + '<div class="mi-b"><div class="mi-top"><h4>' + esc(nameOf(t, r)) + '</h4><span class="dots"></span>' + (priceF && r[priceF.id] != null ? priceHtml(t, r) : '') + '</div>'
          + (descF && r[descF.id] ? '<p class="mi-d">' + esc(r[descF.id]) + '</p>' : '')
          + '<div class="mi-meta">' + badgesOf(t, r) + (allergF && r[allergF.id] ? '<span class="allerg">Contains: ' + esc(r[allergF.id]) + '</span>' : '') + (out ? '<span class="dbadge out">Sold out today</span>' : '') + '</div></div>'
          + (pick && !out ? '<div class="mi-add">' + (q2 ? '<span class="qtybadge">' + q2 + '×</span>' : '') + '<button class="iconbtn" aria-label="Add ' + esc(nameOf(t, r)) + '">' + icon('plus') + '</button></div>' : '') + '</article>');
        if (pick && !out) $('.mi-add button', row).onclick = () => state.add(t.id, r.id);
        if (SPEC.manager) { const e = el('<button class="edit-btn" title="Edit">✎</button>'); e.onclick = () => drawer(t, r, () => site()); row.prepend(e); }
        $('.menu-list', sec).append(row);
      }
      box.append(sec);
    });
    if (!box.children.length) box.innerHTML = '<div class="empty">Nothing here yet.</div>';
  };
  state.redrawLists.push(draw);
  draw();
  return n;
}

/// Photos in a grid; tap one to see it big.
async function galleryBlock(b) {
  const pics = (b.images || []).map((u) => ({url: u, name: ''}));
  const t = b.table && table(b.table);
  if (t) { const imgF = firstOf(t, 'image'); if (imgF) for (const r of await rows(t.id).catch(() => [])) if (r[imgF.id]) pics.push({url: r[imgF.id], name: nameOf(t, r)}); }
  if (!pics.length) return null;
  const list = pics.slice(0, 24);
  const n = el('<section class="sec"><div class="wrap">' + (b.title ? '<div class="sec-head"><h2>' + esc(b.title) + '</h2></div>' : '') + '<div class="gallery">'
    + list.map((p, i) => '<button class="g-item" data-i="' + i + '"><img src="' + esc(p.url) + '" alt="' + esc(p.name) + '" loading="lazy">' + (p.name ? '<span>' + esc(p.name) + '</span>' : '') + '</button>').join('') + '</div></div></section>');
  $('.gallery', n).onclick = (e) => { const g = e.target.closest('.g-item'); if (g) lightbox(list, +g.dataset.i); };
  return n;
}
function lightbox(pics, i) {
  const bx = el('<div class="lightbox" role="dialog"><button class="iconbtn lb-x" aria-label="Close">' + icon('x') + '</button><button class="iconbtn lb-p" aria-label="Previous">' + icon('left') + '</button><figure><img alt=""><figcaption></figcaption></figure><button class="iconbtn lb-n" aria-label="Next">' + icon('right') + '</button></div>');
  const show = () => { $('img', bx).src = pics[i].url; $('figcaption', bx).textContent = pics[i].name; };
  const step = (k) => { i = (i + k + pics.length) % pics.length; show(); };
  const close = () => { bx.remove(); document.removeEventListener('keydown', key); };
  const key = (e) => { if (e.key === 'Escape') close(); if (e.key === 'ArrowRight') step(1); if (e.key === 'ArrowLeft') step(-1); };
  bx.onclick = (e) => { if (e.target === bx || e.target.closest('.lb-x')) close(); };
  $('.lb-p', bx).onclick = () => step(-1); $('.lb-n', bx).onclick = () => step(1);
  document.addEventListener('keydown', key); document.body.append(bx); show();
}

/// What people say: quotes with stars, from a table of reviews the manager keeps.
async function testimonialsBlock(b, t) {
  const all = await rows(t.id, true).catch(() => []);
  const label = labelOf(t);
  const quoteF = visible(t).find((f) => f.type === 'longtext') || visible(t).find((f) => f.type === 'text' && f.id !== label);
  const rateF = visible(t).find((f) => f.type === 'number' && /rat|star|score/.test(f.id));
  const srcF = visible(t).find((f) => f.type === 'text' && f.id !== label && f !== quoteF);
  const list = all.filter((r) => quoteF && r[quoteF.id]).slice(0, 9);
  if (!list.length && !SPEC.manager) return null;
  const stars = (v) => { const k = Math.max(0, Math.min(5, Math.round(Number(v) || 0))); return k ? '<div class="stars" aria-label="' + k + ' out of 5">' + '★'.repeat(k) + '<span>' + '★'.repeat(5 - k) + '</span></div>' : ''; };
  const rated = rateF ? list.filter((r) => Number(r[rateF.id]) > 0) : [];
  const avg = rated.length ? rated.reduce((a, r) => a + Number(r[rateF.id]), 0) / rated.length : 0;
  const n = el('<section class="sec"><div class="wrap"><div class="sec-head"><h2>' + esc(b.title || t.title) + '</h2>' + (avg ? '<div class="avg"><b>' + avg.toFixed(1) + '</b>' + stars(avg) + '<span class="muted">' + rated.length + ' review' + (rated.length === 1 ? '' : 's') + '</span></div>' : '')
    + (SPEC.manager ? '<button class="btn primary sm" data-a="add">' + icon('plus') + ' Add a review</button>' : '') + '</div><div class="quotes">'
    + (list.length ? list.map((r, i) => '<figure class="quote" style="animation-delay:' + i * 60 + 'ms">' + (rateF ? stars(r[rateF.id]) : '') + '<blockquote>“' + esc(r[quoteF.id]) + '”</blockquote><figcaption><div class="avatar" style="--h:' + hue(nameOf(t, r)) + '">' + esc((nameOf(t, r).trim()[0] || '?').toUpperCase()) + '</div><div><b>' + esc(nameOf(t, r)) + '</b>' + (srcF && r[srcF.id] ? '<small>' + esc(r[srcF.id]) + '</small>' : '') + '</div></figcaption></figure>').join('') : '<div class="empty">No reviews yet: add the ones you’re proud of.</div>')
    + '</div></div></section>');
  if (SPEC.manager) $('[data-a=add]', n).onclick = () => drawer(t, null, () => site());
  if (SPEC.manager) $$('.quote', n).forEach((q, i) => { const e = el('<button class="edit-btn" title="Edit">✎</button>'); e.onclick = () => drawer(t, list[i], () => site()); q.prepend(e); });
  return n;
}

/// Address, phone, email and hours, with directions on OpenStreetMap (no key needed).
async function contactBlock(b) {
  const s = SPEC.site || {}, h = await hours();
  const map = s.address ? 'https://www.openstreetmap.org/search?query=' + encodeURIComponent(s.address) : '';
  const row = (ic, l, v) => '<div class="info-row"><div class="info-ic">' + icon(ic) + '</div><div><small>' + esc(l) + '</small><b>' + v + '</b></div></div>';
  let rows2 = '';
  if (s.address) rows2 += row('pin', 'Address', esc(s.address) + '<a class="small-link" href="' + map + '" target="_blank" rel="noopener">Get directions ' + icon('ext') + '</a>');
  if (s.phone) rows2 += row('phone', 'Phone', '<a href="tel:' + esc(s.phone.replace(/\s/g, '')) + '">' + esc(s.phone) + '</a>');
  if (s.email) rows2 += row('mail', 'Email', '<a href="mailto:' + esc(s.email) + '">' + esc(s.email) + '</a>');
  if (h) rows2 += row('clock', 'Opening hours', esc(h.open) + ' – ' + esc(h.close) + (h.days ? '<span class="sub2">' + esc(h.days) + '</span>' : '') + '<span class="sub2"><span class="dot' + (h.isOpen ? '' : ' off') + '"></span> ' + (h.isOpen ? 'Open now' : 'Closed now') + '</span>');
  if (!rows2 && !SPEC.manager) return null;
  return el('<section class="sec"><div class="wrap"><div class="sec-head"><h2>' + esc(b.title || 'Find us') + '</h2></div>' + (b.text ? '<p class="lead2">' + esc(b.text) + '</p>' : '')
    + '<div class="contact"><div class="info-card">' + (rows2 || '<div class="muted">Add your address, phone and email in Design & texts.</div>') + '</div>'
    + (map ? '<a class="mapcard" href="' + map + '" target="_blank" rel="noopener"><div class="map-bg"></div><div class="map-pin">' + icon('pin') + '</div><div class="map-cap"><b>' + esc(s.address) + '</b><span>Open the map ' + icon('arrow') + '</span></div></a>' : '')
    + '</div></div></section>');
}

const FEATURE_ICONS = [[/oven|fire|wood|grill|bake|hot/i, 'flame'], [/vegan|vegetar|fresh|organic|garden|leaf|local|grow|seasonal/i, 'leaf'], [/deliver|collect|takeaway|van|parking/i, 'truck'], [/gift|voucher|present/i, 'gift'],
  [/family|team|people|private|room|group|guest|seat|party/i, 'users'], [/wine|drink|bar|cocktail/i, 'glass'], [/award|best|quality|expert|qualified|star/i, 'award'], [/menu|dish|food|pasta|pizza|chef|kitchen|cake|cook/i, 'chef'],
  [/price|amount|£|\$|€|value|cost/i, 'tag'], [/time|hour|quick|fast|minute|valid|month/i, 'clock'], [/love|care|heart|welcome|friendly/i, 'heart'], [/phone|call|text|sent|message/i, 'phone'], [/book|reserv|calendar|date/i, 'cal']];
/// Highlights: one card per line ("Title: what it means"), each with a fitting icon.
function featuresBlock(b) {
  const items = String(b.text || '').split('\n').map((l) => l.trim()).filter(Boolean).map((l) => { const m = /^(.{1,60}?)\s*[:—–-]\s+(.+)$/.exec(l); return m ? {title: m[1], text: m[2]} : {title: l, text: ''}; });
  if (!items.length) return null;
  return el('<section class="sec"><div class="wrap">' + (b.title ? '<div class="sec-head"><h2>' + esc(b.title) + '</h2></div>' : '') + '<div class="features">'
    + items.map((it, i) => '<div class="feature" style="animation-delay:' + i * 70 + 'ms"><div class="f-ic">' + icon((FEATURE_ICONS.find(([re]) => re.test(it.title + ' ' + it.text)) || [0, 'sparkle'])[1]) + '</div><h3>' + esc(it.title) + '</h3>' + (it.text ? '<p>' + esc(it.text) + '</p>' : '') + '</div>').join('')
    + '</div></div></section>');
}

// ================= bookings =================
/// A table of bookings for things booked one at a time (tables, stylists, rooms…).
function shapeOf(t) {
  const links = t.fields.filter((f) => f.type === 'link' && table(f.link) && table(f.link).kind !== 'single');
  const link = links.find((f) => /table|room|stylist|barber|doctor|dentist|therap|staff|trainer|coach|court|desk|seat|bay|chair|lane|pitch|vehicle|tutor|teacher|person/i.test(f.id + ' ' + f.link)) || links[0];
  const date = t.fields.find((f) => f.type === 'date'), time = t.fields.find((f) => f.type === 'time');
  if (!link || !date || !time) return null;
  const res = table(link.link);
  return {link, res, date, time, guests: t.fields.find((f) => f.type === 'number' && /guest|people|party|person|size|covers/.test(f.id))};
}
const toMin = (s) => { const m = /^(\d{1,2}):(\d{2})/.exec(s || ''); return m ? +m[1] * 60 + +m[2] : null; };
const toHHMM = (m) => String(Math.floor(m / 60) % 24).padStart(2, '0') + ':' + String(m % 60).padStart(2, '0');
const todayISO = () => { const d = new Date(); d.setMinutes(d.getMinutes() - d.getTimezoneOffset()); return d.toISOString().slice(0, 10); };
function slotsOf(plan) { const o = toMin(plan.open) ?? 720, c0 = toMin(plan.close) ?? 1320, c = c0 <= o ? c0 + 1440 : c0, out = []; for (let m = o; m <= c - 30; m += 30) out.push(m); return out; }
const isTaken = (plan, id, at) => plan.busy.some((h) => h.resource === id && at < toMin(h.to) + (toMin(h.to) < toMin(h.from) ? 1440 : 0) && at + plan.minutes > toMin(h.from));

/// Customers: pick a day, people and time, see which tables are free, tap one to fill the form.
async function availabilityBlock(b, t, state) {
  const sh = shapeOf(t); if (!sh) return null;
  const what = sh.res.title.toLowerCase();
  const n = el('<section class="sec"><div class="wrap"><div class="sec-head"><h2>' + esc(b.title || 'Find a free ' + what.replace(/s$/, '')) + '</h2></div><div class="avail">'
    + '<div class="avail-ctl"><div class="field"><label class="lbl">Day</label><input type="date"></div>'
    + (sh.guests ? '<div class="field"><label class="lbl">' + esc(sh.guests.label) + '</label><div class="guests"><button type="button" data-d="-1">' + icon('minus') + '</button><b>2</b><button type="button" data-d="1">' + icon('plus') + '</button></div></div>' : '')
    + '</div><label class="lbl">Time</label><div class="slots"></div><div class="res-grid"></div><div class="legend"><span><i style="background:#16a34a"></i>Free</span><span><i style="background:#dc2626"></i>Booked</span>'
    + '<button class="btn sm" data-a="day" style="margin-left:auto">See the whole day</button></div><div class="tl" hidden></div></div></div></section>');
  const day = $('input[type=date]', n), slotsBox = $('.slots', n), grid = $('.res-grid', n), tl = $('.tl', n);
  day.value = todayISO(); day.min = todayISO();
  let guests = 2, at = null, plan = null, picked = null;
  const seats = (r) => r.seats ?? 999;
  const nowMin = () => { const d = new Date(); return day.value === todayISO() ? d.getHours() * 60 + d.getMinutes() : -1; };
  const fill = () => {
    const form = state.forms[t.id]; if (!form) return;
    form[sh.date.id]?.set(day.value); if (at != null) form[sh.time.id]?.set(toHHMM(at));
    if (sh.guests) form[sh.guests.id]?.set(guests); form[sh.link.id]?.set(picked);
  };
  const drawRes = () => {
    grid.innerHTML = '';
    if (at == null) { grid.innerHTML = '<div class="muted" style="grid-column:1/-1">Choose a time to see what’s free.</div>'; return; }
    for (const r of plan.resources) {
      const taken = isTaken(plan, r.id, at), small = !taken && seats(r) < guests;
      const c = el('<button type="button" class="res ' + (taken ? 'taken' : small ? 'small' : 'free') + (picked === r.id ? ' picked' : '') + '"><b>' + esc(r.name) + '</b><small>' + (r.seats ? r.seats + ' seats' : '') + '</small><div class="st">' + (taken ? '● Booked' : small ? 'Too small' : '● Free') + '</div></button>');
      if (!taken && !small) c.onclick = () => { picked = r.id; drawRes(); fill(); $('#form-' + t.id)?.scrollIntoView({behavior: 'smooth', block: 'start'}); toast(sh.res.title.replace(/s$/, '') + ' ' + r.name + ' at ' + toHHMM(at) + ' — add your details below'); };
      grid.append(c);
    }
  };
  const drawSlots = () => {
    slotsBox.innerHTML = '';
    for (const m of slotsOf(plan)) {
      const full = plan.resources.every((r) => isTaken(plan, r.id, m) || seats(r) < guests);
      const s = el('<button type="button" class="slot' + (m === at ? ' on' : '') + (full ? ' full' : '') + '">' + toHHMM(m) + '</button>');
      s.disabled = m <= nowMin() || full;
      s.onclick = () => { at = m; picked = null; drawSlots(); drawRes(); fill(); };
      slotsBox.append(s);
    }
  };
  const drawDay = () => {
    const ss = slotsOf(plan);
    let h = '<table><tr><th class="rn">' + esc(sh.res.title) + '</th>' + ss.map((m) => '<th>' + toHHMM(m) + '</th>').join('') + '</tr>';
    for (const r of plan.resources) {
      h += '<tr><th class="rn">' + esc(r.name) + (r.seats ? ' <span style="color:var(--muted);font-weight:400">· ' + r.seats + '</span>' : '') + '</th>';
      for (let i = 0; i < ss.length; i++) {
        const bk = plan.busy.find((x) => x.resource === r.id && ss[i] >= toMin(x.from) && ss[i] < toMin(x.from) + plan.minutes);
        if (bk) { let k = 1; while (i + k < ss.length && ss[i + k] < toMin(bk.from) + plan.minutes) k++; h += '<td class="b" colspan="' + k + '">Booked</td>'; i += k - 1; continue; }
        h += '<td class="' + (ss[i] <= nowMin() ? 'past' : 'f') + '" data-r="' + r.id + '" data-m="' + ss[i] + '"></td>';
      }
      h += '</tr>';
    }
    tl.innerHTML = h + '</table>';
  };
  tl.onclick = (e) => { const c = e.target.closest('td.f'); if (!c) return; at = +c.dataset.m; picked = +c.dataset.r; drawSlots(); drawRes(); fill(); $('#form-' + t.id)?.scrollIntoView({behavior: 'smooth', block: 'start'}); };
  $('[data-a=day]', n).onclick = (e) => { tl.hidden = !tl.hidden; e.target.textContent = tl.hidden ? 'See the whole day' : 'Hide the day'; };
  const load = async () => {
    plan = await api('_plan/' + t.id + '?date=' + day.value);
    if (plan.closed) { at = null; picked = null; slotsBox.innerHTML = '<div class="closed-note">' + icon('cal') + ' We’re closed that day' + (plan.closed !== 'closed' ? ' (' + esc(plan.closed) + ')' : '') + '. Please choose another day.</div>'; grid.innerHTML = ''; tl.innerHTML = ''; return; }
    if (at != null && (at <= nowMin())) at = null; drawSlots(); drawRes(); drawDay(); fill();
  };
  day.onchange = () => { picked = null; load(); };
  $$('.guests button', n).forEach((x) => x.onclick = () => { guests = Math.max(1, Math.min(30, guests + +x.dataset.d)); $('.guests b', n).textContent = guests + (guests === 1 ? ' person' : ' people'); picked = null; drawSlots(); drawRes(); fill(); });
  if (sh.guests) $('.guests b', n).textContent = '2 people';
  await load();
  return n;
}

// ================= customer website =================
function ctaText(p) { const f = p.blocks.find((b) => b.type === 'form'); return f && f.submit && f.submit.length < 22 ? f.submit : p.title; }

function navbar(pages, current) {
  const formPage = pages.find((p) => p.blocks.some((b) => b.type === 'form'));
  const n = el('<header class="topnav' + (pages.length > 5 ? ' many' : '') + '"><div class="wrap"><a class="brand" href="/">' + monogram() + '<span>' + esc(SPEC.name) + '</span></a>'
    + '<nav class="links">' + pages.map((p) => '<a href="/p/' + p.id + '"' + (p.id === current ? ' class="on"' : '') + '>' + esc(p.title) + '</a>').join('') + '</nav>'
    + (formPage && formPage.id !== current ? '<a class="btn primary sm cta" href="/p/' + formPage.id + '">' + esc(formPage.title) + '</a>' : '')
    + '<button class="iconbtn burger" aria-label="Menu" aria-expanded="false">' + icon('menu') + '</button></div></header>');
  const burger = $('.burger', n), links = $('.links', n);
  const set = (open) => { links.classList.toggle('open', open); burger.setAttribute('aria-expanded', String(open)); burger.innerHTML = icon(open ? 'x' : 'menu'); };
  burger.onclick = () => set(!links.classList.contains('open'));
  links.onclick = (e) => { if (e.target.closest('a')) set(false); };
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape') set(false); });
  return n;
}

/// Where to book or order (a page with free times first, then one with a form).
const actionPages = (pages) => {
  const rank = (p) => p.blocks.some((b) => b.type === 'availability' || b.type === 'stay') ? 0 : p.blocks.some((b) => b.type === 'form' && table(b.table) && isOrders(table(b.table))) ? 1 : p.blocks.some((b) => b.type === 'form') ? 2 : 9;
  return pages.filter((p) => rank(p) < 9).sort((a, b) => rank(a) - rank(b));
};

async function footer(pages) {
  const s = SPEC.site || {}, h = await hours();
  const col = (title, body) => body ? '<div><h4>' + esc(title) + '</h4>' + body + '</div>' : '';
  const cta = actionPages(pages)[0];
  const map = s.address ? 'https://www.openstreetmap.org/search?query=' + encodeURIComponent(s.address) : '';
  return el('<footer class="footer">'
    + (cta ? '<div class="cta-band"><div class="wrap"><div><h2>' + esc(cta.title) + '</h2><p>' + esc(s.tagline || 'We’d love to see you.') + '</p></div><div class="actions"><a class="btn primary lg" href="/p/' + cta.id + '">' + esc(ctaText(cta)) + ' ' + icon('arrow') + '</a>' + (s.phone ? '<a class="btn lg" href="tel:' + esc(s.phone.replace(/\s/g, '')) + '">' + icon('phone') + ' ' + esc(s.phone) + '</a>' : '') + '</div></div></div>' : '')
    + '<div class="wrap cols">'
    + '<div><a class="brand" href="/">' + monogram() + '<span>' + esc(SPEC.name) + '</span></a>' + (s.about || s.tagline ? '<p class="about">' + esc(s.about || s.tagline) + '</p>' : '') + '</div>'
    + col('Visit us', (s.address ? '<p>' + esc(s.address) + '</p><a class="dirs" href="' + map + '" target="_blank" rel="noopener">' + icon('pin') + ' Get directions</a>' : '') + (s.phone ? '<a href="tel:' + esc(s.phone.replace(/\s/g, '')) + '">' + esc(s.phone) + '</a>' : '') + (s.email ? '<a href="mailto:' + esc(s.email) + '">' + esc(s.email) + '</a>' : ''))
    + col('Hours', h ? '<p>' + esc(h.open) + ' – ' + esc(h.close) + '</p>' + (h.days ? '<p class="soft">' + esc(h.days) + '</p>' : '') + '<p class="soft"><span class="dot' + (h.isOpen ? '' : ' off') + '" style="display:inline-block;margin-right:8px"></span>' + (h.isOpen ? 'Open now' : 'Closed now') + '</p>' : '')
    + col('Explore', pages.map((p) => '<a href="/p/' + p.id + '">' + esc(p.title) + '</a>').join(''))
    + '</div><div class="wrap bottom"><span>© ' + new Date().getFullYear() + ' ' + esc(SPEC.name) + (s.footer ? ' · ' + esc(s.footer) : '') + '</span><span><a href="/manage">Manager sign-in</a></span></div></footer>');
}

async function heroBlock(b, isFirst) {
  const s = SPEC.site || {}, img = b.image || (isFirst ? s.hero : '');
  const h = isFirst ? await hours() : null;
  return el('<section class="hero' + (img ? ' img' : (isFirst ? '' : ' sub')) + '">' + (img ? '<div class="hero-bg" style="background-image:url(\'' + esc(img) + '\')"></div>' : '') + '<div class="wrap">'
    + (h ? '<div class="badge"><span class="dot' + (h.isOpen ? '' : ' off') + '"></span>' + (h.isOpen ? 'Open now · until ' + esc(h.close) : 'Closed · opens ' + esc(h.open)) + '</div>' : (isFirst && s.tagline && b.title !== s.tagline ? '<div class="eyebrow">' + esc(s.tagline) + '</div>' : ''))
    + '<h1>' + esc(b.title) + '</h1>' + (b.text ? '<p class="lead">' + esc(b.text) + '</p>' : '')
    + (b.link ? '<div class="actions"><a class="btn primary lg" href="/p/' + esc(b.link) + '">' + esc(b.button || 'Get started') + ' ' + icon('arrow') + '</a></div>' : '')
    + '</div></section>');
}

function textBlock(b) {
  let html = '', list = false;
  for (const l of b.text.split('\n')) {
    const s = esc(l).replace(/\*\*(.+?)\*\*/g, '<b>$1</b>');
    if (/^[-*] /.test(l)) { if (!list) { html += '<ul>'; list = true; } html += '<li>' + s.slice(2) + '</li>'; continue; }
    if (list) { html += '</ul>'; list = false; }
    if (/^#{1,2} /.test(l)) html += '<h2>' + s.replace(/^#{1,2} /, '') + '</h2>';
    else if (/^#{3,} /.test(l)) html += '<h3>' + s.replace(/^#+ /, '') + '</h3>';
    else if (l.trim()) html += '<p>' + s + '</p>';
  }
  if (list) html += '</ul>';
  return el('<section class="sec"><div class="wrap"><div class="prose">' + html + '</div></div></section>');
}

async function listBlock(b, t, page, state) {
  const fields = (b.fields ? b.fields.map((x) => t.fields.find((f) => f.id === x)).filter(Boolean) : visible(t)).filter((f) => !f.manager_only);
  const label = labelOf(t), imgF = firstOf(t, 'image'), descF = fields.find((f) => f.type === 'longtext'), catF = fields.find((f) => f.type === 'choice');
  const priceF = fields.find((f) => f.type === 'money' && !SALE.test(f.id)) || fields.find((f) => f.type === 'money'), saleF = fields.find((f) => f.type === 'money' && SALE.test(f.id) && f !== priceF);
  const pick = page.blocks.some((o) => o.type === 'form' && table(o.table)?.fields.some((f) => f.type === 'links' && f.qty && f.link === t.id));
  let all = await rows(t.id, true);
  const links = await linkMaps(t);
  // Only the ones ticked (e.g. popular dishes); closed days that are over aren't shown.
  if (b.only) all = all.filter((r) => r[b.only] === true);
  if (isClosures(t)) { const ds = t.fields.filter((f) => f.type === 'date'); all = all.filter((r) => String(r[ds[1]?.id] || r[ds[0].id] || '') >= todayISO()); }
  // Events that are over aren't shown (a list whose date must be given: shows, events), soonest first.
  const whenF = t.fields.find((f) => f.type === 'date' && f.required);
  if (whenF && !isClosures(t)) all = all.filter((r) => !r[whenF.id] || String(r[whenF.id]) >= todayISO()).sort((x, y) => String(x[whenF.id] || '').localeCompare(String(y[whenF.id] || '')));
  const places = await placesOf(t);
  if (b.layout === 'menu') return menuBlock(b, t, all, pick, state);
  if (b.layout === 'timetable') return timetableBlock(b, t, all, places, page, state, links);
  // A form on this page that books one of these (a class, a course, an event, a home): "Book" fills it in.
  const formB = page.blocks.find((o) => o.type === 'form' && table(o.table)?.fields.some((f) => f.type === 'link' && f.link === t.id && !f.manager_only));
  const formT = formB && table(formB.table), formF = formT && formT.fields.find((f) => f.type === 'link' && f.link === t.id && !f.manager_only);
  const n = el('<section class="sec"><div class="wrap"><div class="sec-head"><h2>' + esc(b.title || t.title) + '</h2>' + (SPEC.manager ? '<div class="sec-actions"><button class="btn sm" data-a="photo">' + icon('image') + ' Add from a photo</button><button class="btn primary sm" data-a="add">' + icon('plus') + ' Add</button></div>' : '') + '</div><div class="toolbar"></div><div class="grid' + (imgF ? '' : ' compact') + '"></div></div></section>');
  if (SPEC.manager) {
    $('[data-a=add]', n).onclick = () => drawer(t, null, () => site());
    $('[data-a=photo]', n).onclick = () => importPhoto(t, () => site());
  }
  const bar = $('.toolbar', n), grid = $('.grid', n);
  let q = '', cat = '';
  if (b.search !== false && all.length > 4) { const s = el('<div class="search">' + icon('search') + '<input placeholder="Search ' + esc(t.title.toLowerCase()) + '"></div>'); $('input', s).oninput = (e) => { q = e.target.value.toLowerCase(); draw(); }; bar.append(s); }
  if (catF) {
    const cats = catF.options.filter((o) => all.some((r) => r[catF.id] === o));
    if (cats.length > 1) {
      const c = el('<div class="chips"></div>');
      for (const o of ['', ...cats]) { const btn = el('<button class="pill-opt' + (o === '' ? ' on' : '') + '">' + esc(o || 'All') + '</button>'); btn.onclick = () => { cat = o; $$('.pill-opt', c).forEach((x) => x.classList.toggle('on', x === btn)); draw(); }; c.append(btn); }
      bar.append(c);
    }
  }
  if (!bar.children.length) bar.remove();
  const draw = () => {
    const list = all.filter((r) => (!cat || r[catF.id] === cat) && (!q || JSON.stringify(r).toLowerCase().includes(q)));
    grid.innerHTML = list.length ? '' : '<div class="empty" style="grid-column:1/-1">' + icon('search') + '<div>' + (all.length ? 'Nothing found.' : 'Nothing here yet.') + '</div></div>';
    list.forEach((r, i) => {
      const tags = fields.filter((f) => ![label, priceF?.id, saleF?.id, descF?.id].includes(f.id) && f.type !== 'image' && !(f.id === 'status' && goneOf(t, r)) && r[f.id] !== undefined && r[f.id] !== '' && r[f.id] !== null && r[f.id] !== false)
        .slice(0, 4).map((f) => '<span class="tag' + (f === catF ? ' acc' : '') + '">' + (f.type === 'yesno' ? icon('check') + ' ' + esc(f.label) : (f.type === 'choice' ? '' : esc(f.label) + ': ') + esc(fmt(f, r[f.id], links))) + '</span>').join('');
      const q2 = state.sel[t.id]?.[r.id] || 0, full = fullOf(places, r.id), out = soldOut(t, r) || full, gone = goneOf(t, r);
      const flags = (gone ? '<span class="dbadge out">' + esc(gone) + '</span>' : out && !full ? '<span class="dbadge out">Sold out</span>' : '') + (onSale(t, r) ? '<span class="dbadge sale">Sale</span>' : '') + placesBadge(places, r.id);
      const card = el('<article class="item' + (out ? ' out' : '') + '" style="animation-delay:' + Math.min(i, 12) * 40 + 'ms">' + (imgF ? '<div class="media">' + media(r[imgF.id], nameOf(t, r)) + (flags ? '<div class="flags">' + flags + '</div>' : '') + '</div>' : '')
        + '<div class="body"><div class="top"><h3>' + esc(nameOf(t, r)) + '</h3>' + (priceF ? priceHtml(t, r) : '') + '</div>' + (!imgF && flags ? '<div class="meta">' + flags + '</div>' : '')
        + (descF && r[descF.id] ? '<p class="desc">' + esc(r[descF.id]) + '</p>' : '') + (tags ? '<div class="meta">' + tags + '</div>' : '')
        + (pick ? '<div class="foot"><span class="qtybadge">' + (out ? (full ? (places.word === 'tickets' ? 'Sold out' : 'Full') : 'Sold out today') : q2 ? q2 + ' in your ' + esc(state.formName) : '') + '</span>' + (out ? '' : '<button class="btn primary sm">' + icon('plus') + ' Add</button>') + '</div>'
          : formF && !out ? '<div class="foot"><span></span><button class="btn primary sm">' + esc(formB.submit && formB.submit.length < 18 ? formB.submit : 'Choose') + ' ' + icon('arrow') + '</button></div>' : '') + '</div></article>');
      if (pick && !out) $('.foot button', card).onclick = () => state.add(t.id, r.id);
      if (!pick && formF && !out) $('.foot button', card).onclick = () => chooseFor(formT, formF, t, r, state);
      if (SPEC.manager) { const e = el('<button class="edit-btn" title="Edit">✎</button>'); e.onclick = () => drawer(t, r, () => site()); card.prepend(e); }
      grid.append(card);
    });
  };
  state.redrawLists.push(() => { grid.classList.add('settled'); draw(); });
  draw();
  return n;
}

/// The next date of a weekly class ("Tuesday" → the coming Tuesday, today included).
function nextDay(name) {
  const i = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'].indexOf(String(name || '').toLowerCase().slice(0, 3));
  if (i < 0) return '';
  const d = new Date(); d.setHours(12); while ((d.getDay() + 6) % 7 !== i) d.setDate(d.getDate() + 1);
  d.setMinutes(d.getMinutes() - d.getTimezoneOffset()); return d.toISOString().slice(0, 10);
}
const weekdayField = (t) => t.fields.find((f) => f.type === 'choice' && f.options.filter((o) => /^(mon|tue|wed|thu|fri|sat|sun)/i.test(o)).length >= 5);

/// "Book" on a card: the form below gets it (and the class's next date), and the page scrolls to it.
function chooseFor(formT, formF, t, r, state) {
  const form = state.forms && state.forms[formT.id]; if (!form) return;
  form[formF.id]?.set(r.id);
  const wd = weekdayField(t), df = formT.fields.find((f) => f.type === 'date' && !f.manager_only);
  if (wd && df && r[wd.id]) form[df.id]?.set(nextDay(r[wd.id]));
  $('#form-' + formT.id)?.scrollIntoView({behavior: 'smooth', block: 'start'});
  toast(nameOf(t, r) + ' — add your details below');
}

/// A week of classes: a column per day, each class in time order, with its coach, length and places left.
async function timetableBlock(b, t, all, places, page, state, links) {
  const wd = weekdayField(t), timeF = firstOf(t, 'time'), durF = visible(t).find((f) => f.type === 'number' && /duration|minutes|length|mins/.test(f.id));
  const levelF = visible(t).find((f) => f.type === 'choice' && f !== wd), whoF = visible(t).find((f) => f.type === 'link');
  const formB = page.blocks.find((o) => o.type === 'form' && table(o.table)?.fields.some((f) => f.type === 'link' && f.link === t.id && !f.manager_only));
  const formT = formB && table(formB.table), formF = formT && formT.fields.find((f) => f.type === 'link' && f.link === t.id && !f.manager_only);
  const today = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][(new Date().getDay() + 6) % 7];
  const days = wd.options.filter((o) => all.some((r) => r[wd.id] === o));
  const n = el('<section class="sec"><div class="wrap"><div class="sec-head"><h2>' + esc(b.title || t.title) + '</h2>' + (SPEC.manager ? '<button class="btn primary sm" data-a="add">' + icon('plus') + ' Add</button>' : '') + '</div><div class="tt"></div></div></section>');
  if (SPEC.manager) $('[data-a=add]', n).onclick = () => drawer(t, null, () => site());
  const box = $('.tt', n);
  if (!days.length) box.innerHTML = '<div class="empty">Nothing on the timetable yet.</div>';
  for (const d of days) {
    const col = el('<div class="tt-day' + (d === today ? ' today' : '') + '"><h3>' + esc(d) + (d === today ? ' <span>Today</span>' : '') + '</h3></div>');
    const list = all.filter((r) => r[wd.id] === d).sort((x, y) => String(x[timeF?.id] || '').localeCompare(String(y[timeF?.id] || '')));
    for (const r of list) {
      const full = fullOf(places, r.id);
      const c = el('<div class="tt-c' + (full ? ' full' : '') + '"><div class="tt-t">' + esc(r[timeF?.id] || '') + (durF && r[durF.id] ? '<small>' + esc(r[durF.id]) + ' min</small>' : '') + '</div><b>' + esc(nameOf(t, r)) + '</b>'
        + '<small>' + [whoF && r[whoF.id] ? fmt(whoF, r[whoF.id], links) : '', levelF ? r[levelF.id] : ''].filter(Boolean).map(esc).join(' · ') + '</small>'
        + '<div class="tt-f">' + placesBadge(places, r.id) + (formF && !full ? '<button class="btn sm">Book</button>' : '') + '</div></div>');
      if (formF && !full) $('button', c).onclick = () => chooseFor(formT, formF, t, r, state);
      if (SPEC.manager) { const e = el('<button class="edit-btn" title="Edit">✎</button>'); e.onclick = () => drawer(t, r, () => site()); c.prepend(e); }
      col.append(c);
    }
    box.append(col);
  }
  return n;
}

/// A stay: pick check-in and check-out (and how many), see which rooms are free for every night and
/// what the stay costs, and pick one to fill the form. Shows rooms, never who is staying.
async function stayBlock(b, t, state) {
  const ds = t.fields.filter((f) => f.type === 'date'), roomF = t.fields.find((f) => f.type === 'link' && /room|suite|cabin|lodge|apartment|unit|pitch/.test(f.id + ' ' + f.link)) || t.fields.find((f) => f.type === 'link');
  const rt = table(roomF.link), guestsF = t.fields.find((f) => f.type === 'number' && /guest|people|party|person/.test(f.id));
  const rooms = await rows(rt.id).catch(() => []), imgF = firstOf(rt, 'image'), descF = visible(rt).find((f) => f.type === 'longtext');
  const sleepsF = visible(rt).find((f) => f.type === 'number' && /guest|sleep|people|capacity/.test(f.id));
  const add = (iso, k) => { const d = new Date(iso + 'T12:00'); d.setDate(d.getDate() + k); d.setMinutes(d.getMinutes() - d.getTimezoneOffset()); return d.toISOString().slice(0, 10); };
  const n = el('<section class="sec"><div class="wrap"><div class="sec-head"><h2>' + esc(b.title || 'Find a free ' + singular(rt.title).toLowerCase()) + '</h2></div><div class="avail stay">'
    + '<div class="avail-ctl"><div class="field"><label class="lbl">' + esc(ds[0].label) + '</label><input type="date" data-k="from"></div><div class="field"><label class="lbl">' + esc(ds[1].label) + '</label><input type="date" data-k="to"></div>'
    + (guestsF ? '<div class="field"><label class="lbl">' + esc(guestsF.label) + '</label><div class="guests"><button type="button" data-d="-1">' + icon('minus') + '</button><b></b><button type="button" data-d="1">' + icon('plus') + '</button></div></div>' : '')
    + '<div class="stay-sum muted"></div></div><div class="stay-grid"></div></div></div></section>');
  const from = $('[data-k=from]', n), to = $('[data-k=to]', n), grid = $('.stay-grid', n), sum = $('.stay-sum', n);
  from.value = add(todayISO(), 1); from.min = todayISO(); to.value = add(from.value, 2); to.min = add(from.value, 1);
  let guests = 2, picked = null, ans = null;
  const fill = () => {
    const form = state.forms && state.forms[t.id]; if (!form) return;
    form[ds[0].id]?.set(from.value); form[ds[1].id]?.set(to.value); if (guestsF) form[guestsF.id]?.set(guests); if (picked) form[roomF.id]?.set(picked);
  };
  const draw = () => {
    grid.innerHTML = '';
    if (!ans) return;
    if (ans.closed) { grid.innerHTML = '<div class="closed-note">' + icon('cal') + ' We’re closed on ' + esc(dayLabel(ans.closed_on)) + (ans.closed !== 'closed' ? ' (' + esc(ans.closed) + ')' : '') + '. Please choose other dates.</div>'; sum.textContent = ''; return; }
    const nights = ans.nights;
    sum.innerHTML = '<b>' + nights + ' night' + (nights === 1 ? '' : 's') + '</b> · ' + esc(dayLabel(from.value)) + ' → ' + esc(dayLabel(to.value));
    const free = rooms.filter((r) => ans.free.includes(r.id)), rest = rooms.filter((r) => !ans.free.includes(r.id));
    if (!free.length) grid.append(el('<div class="closed-note" style="grid-column:1/-1">' + icon('cal') + ' Nothing is free for all of those nights' + (guestsF ? ' for ' + guests : '') + '. Try other dates.</div>'));
    for (const r of [...free, ...rest]) {
      const ok = ans.free.includes(r.id), min = ans.too_short && ans.too_short[r.id], big = guestsF && sleepsF && r[sleepsF.id] != null && Number(r[sleepsF.id]) < guests;
      const p = priceNow(rt, r), total = p != null ? Number(p) * nights : null;
      const c = el('<article class="room' + (ok ? '' : ' off') + (picked === r.id ? ' picked' : '') + '"><div class="room-img">' + media(imgF && r[imgF.id], nameOf(rt, r)) + '</div><div class="room-b"><div class="top"><h3>' + esc(nameOf(rt, r)) + '</h3>' + (p != null ? '<span class="price">' + money(p) + '<small> / night</small></span>' : '') + '</div>'
        + (descF && r[descF.id] ? '<p class="desc">' + esc(r[descF.id]) + '</p>' : '') + '<div class="meta">' + badgesOf(rt, r) + (sleepsF && r[sleepsF.id] ? '<span class="tag">' + icon('users') + ' ' + esc(sleepsF.label) + ' ' + esc(r[sleepsF.id]) + '</span>' : '') + '</div>'
        + '<div class="foot">' + (ok ? '<span><b>' + (total != null ? money(total) : '') + '</b>' + (total != null ? ' <small class="muted">for ' + nights + ' night' + (nights === 1 ? '' : 's') + '</small>' : '') + '</span><button class="btn primary sm">' + (picked === r.id ? icon('check') + ' Chosen' : 'Choose') + '</button>'
          : '<span class="dbadge out">' + (min ? 'At least ' + min + ' nights' : big ? 'Too small for ' + guests : 'Booked those nights') + '</span>') + '</div></div></article>');
      if (ok) $('button', c).onclick = () => { picked = r.id; draw(); fill(); $('#form-' + t.id)?.scrollIntoView({behavior: 'smooth', block: 'start'}); toast(nameOf(rt, r) + ' · ' + nights + ' night' + (nights === 1 ? '' : 's') + ' — add your details below'); };
      grid.append(c);
    }
  };
  const load = async () => {
    if (to.value <= from.value) to.value = add(from.value, 1);
    to.min = add(from.value, 1);
    try { ans = await api('_stay/' + t.id + '?from=' + from.value + '&to=' + to.value + (guestsF ? '&guests=' + guests : '')); } catch (e) { ans = null; grid.innerHTML = '<div class="err">' + esc(e.message) + '</div>'; return; }
    if (picked && !ans.free.includes(picked)) picked = null;
    draw(); fill();
  };
  from.onchange = load; to.onchange = load;
  $$('.guests button', n).forEach((x) => x.onclick = () => { guests = Math.max(1, Math.min(20, guests + +x.dataset.d)); $('.guests b', n).textContent = guests + (guests === 1 ? ' guest' : ' guests'); load(); });
  if (guestsF) $('.guests b', n).textContent = '2 guests';
  await load();
  return n;
}

async function infoBlock(b, t) {
  const r = (await rows(t.id, true))[0] || {}, links = await linkMaps(t);
  const h = await hours();
  const mine = h && h.table.id === t.id;
  let body = mine ? '<div class="info-row"><div class="info-ic">' + icon('clock') + '</div><div><small>Opening hours</small><b>' + esc(h.open) + ' – ' + esc(h.close) + '</b><div style="font-size:14px;color:var(--muted);display:flex;align-items:center;gap:8px;margin-top:4px"><span class="dot' + (h.isOpen ? '' : ' off') + '"></span>' + (h.isOpen ? 'Open now' : 'Closed now') + '</div></div></div>' : '';
  for (const f of visible(t)) {
    if (mine && (f.id === h.times[0].id || f.id === h.times[1].id)) continue;
    const v = r[f.id]; if (v === undefined || v === null || v === '' || f.type === 'image') continue;
    let val = esc(fmt(f, v, links));
    if (f.type === 'phone') val = '<a href="tel:' + esc(String(v).replace(/\s/g, '')) + '">' + val + '</a>';
    if (f.type === 'email') val = '<a href="mailto:' + esc(v) + '">' + val + '</a>';
    body += '<div class="info-row"><div class="info-ic">' + icon(fieldIcon(f)) + '</div><div><small>' + esc(f.label) + '</small><b>' + val + '</b></div></div>';
  }
  if (!body && !SPEC.manager) return null;
  const n = el('<section class="sec"><div class="wrap"><div class="sec-head"><h2>' + esc(b.title || t.title) + '</h2>' + (SPEC.manager ? '<button class="btn sm">✎ Edit</button>' : '') + '</div><div class="info"><div class="info-card">' + (body || '<div class="muted">Not filled in yet.</div>') + '</div></div></div></section>');
  if (SPEC.manager) $('.sec-head .btn', n).onclick = () => drawer(t, r.id ? r : null, () => site());
  return n;
}

async function formBlock(b, t, page, state) {
  const fields = (b.fields ? b.fields.map((x) => t.fields.find((f) => f.id === x)).filter(Boolean) : t.fields).filter((f) => !f.manager_only);
  const cartF = fields.find((f) => f.type === 'links' && f.qty);
  const hasList = cartF && page.blocks.some((o) => o.type === 'list' && o.table === cartF.link);
  const n = el('<section class="sec" id="form-' + t.id + '"><div class="wrap"><div class="formwrap' + (cartF ? '' : ' single') + '"><form class="panel" novalidate><h2>' + esc(cartF ? 'Your details' : (b.title || t.title)) + '</h2><p class="sub">Fill in the details and we’ll take care of the rest.</p><div class="fgrid"></div><div class="msg"></div><button class="btn primary lg block" type="submit">' + esc(b.submit || 'Send') + '</button></form></div></div></section>');
  const form = $('form', n), grid = $('.fgrid', n), wrap = $('.formwrap', n);
  const inputs = [];
  let aside = null, fc = null, inView = false, cartCtx = null, valuesOf = null;
  const canDeliver = t.fields.some((f) => f.type === 'choice' && !f.manager_only && f.options.some((o) => /^deliver/i.test(o)));
  if (cartF) {
    state.formName = (b.title || t.title).toLowerCase().replace(/^(place |make |book )?(your |an? )?/, '').trim() || 'order';
    aside = el('<aside class="panel aside"><h3>' + esc(b.title || 'Your ' + state.formName) + '</h3><div class="cartbox"></div></aside>');
    wrap.append(aside);
    fc = el('<a class="btn primary lg floatcart" href="#form-' + t.id + '">' + icon('bag') + ' <span></span></a>');
    document.body.append(fc);
  }
  for (const f of fields) {
    if (f === cartF) {
      const ctx = cartCtx = {sel: state.sel[cartF.link] = state.sel[cartF.link] || {}, hasList, extras: () => ({fee: siteNum('delivery_fee'), min: siteNum('min_order'), canDeliver, delivery: canDeliver && !!valuesOf && isDelivery(t, valuesOf())}), onChange: (count, sum) => {
        state.redrawLists.forEach((d) => d());
        $('span', fc).textContent = count ? 'View ' + state.formName + ' · ' + count + ' item' + (count > 1 ? 's' : '') + (sum ? ' · ' + money(sum) : '') : '';
        fc.classList.toggle('show', count > 0 && !inView);
      }};
      const inp = await fieldInput(f, null, ctx);
      $('label', inp.node).remove();
      $('.cartbox', aside).append(inp.node);
      state.add = (tbl, id) => { if (tbl !== cartF.link) return; ctx.sel[id] = (ctx.sel[id] || 0) + 1; ctx.redraw(); toast('Added to your ' + state.formName); };
      inputs.push(inp);
      continue;
    }
    const inp = await fieldInput(f, null, {optional: !f.required});
    grid.append(inp.node); inputs.push(inp);
  }
  state.forms = state.forms || {};
  state.forms[t.id] = Object.fromEntries(inputs.map((i) => [i.f.id, i]));
  if (fc) new IntersectionObserver((e) => { inView = e[0].isIntersecting; fc.classList.toggle('show', !inView && $('span', fc).textContent !== ''); }).observe(n);
  // Fields that only apply in some cases (an address only for delivery) show when they do.
  const applies = (f, body) => !f.when || Object.entries(f.when).every(([k, vals]) => vals.some((v) => String(v).toLowerCase() === String(body[k] ?? '').toLowerCase()));
  const values = valuesOf = () => { const body = {}; for (const i of inputs) body[i.f.id] = i.get(); return body; };
  if (cartCtx && canDeliver) { ['click', 'change'].forEach((ev) => form.addEventListener(ev, () => setTimeout(() => cartCtx.redraw && cartCtx.redraw()))); cartCtx.redraw && cartCtx.redraw(); }
  const showWhen = () => { const body = values(); for (const i of inputs) if (i.f.when) i.node.style.display = applies(i.f, body) ? '' : 'none'; };
  if (inputs.some((i) => i.f.when)) { ['click', 'input', 'change'].forEach((ev) => form.addEventListener(ev, () => setTimeout(showWhen))); showWhen(); }
  form.onsubmit = async (e) => {
    e.preventDefault();
    const body = values();
    for (const i of inputs) if (!applies(i.f, body)) delete body[i.f.id];
    const missing = inputs.find((i) => i.f.required && applies(i.f, body) && (body[i.f.id] === '' || body[i.f.id] === null || body[i.f.id] === undefined || (Array.isArray(body[i.f.id]) && !body[i.f.id].length)));
    const msg = $('.msg', form);
    if (missing) { msg.innerHTML = '<div class="err">Please fill in “' + esc(missing.f.label) + '”.</div>'; return; }
    if (cartF && !body[cartF.id].length) { msg.innerHTML = '<div class="err">Choose at least one item first.</div>'; return; }
    if (cartCtx && isDelivery(t, body) && siteNum('min_order') && (cartCtx.sum || 0) < siteNum('min_order')) { msg.innerHTML = '<div class="err">The minimum order for delivery is ' + money(siteNum('min_order')) + '. Add something more, or choose collection.</div>'; return; }
    const btn = $('button[type=submit]', form); btn.disabled = true; msg.innerHTML = '';
    try {
      await api('t/' + t.id, {method: 'POST', body: JSON.stringify(body)});
      if (fc) fc.remove();
      if (aside) aside.remove();
      wrap.classList.add('single');
      form.innerHTML = '<div class="success"><div class="ok">' + icon('check') + '</div><h2>Thank you!</h2><p>' + esc(b.thanks || 'We’ve received it and will be in touch soon.') + '</p><a class="btn" href="' + location.pathname + '">Start again</a></div>';
      form.scrollIntoView({behavior: 'smooth', block: 'center'});
    } catch (err) { msg.innerHTML = '<div class="err">' + esc(err.message) + '</div>'; btn.disabled = false; }
  };
  return n;
}

async function site() {
  const app = document.getElementById('app');
  const pages = SPEC.pages.filter((p) => !p.manager);
  const id = location.pathname.startsWith('/p/') ? decodeURIComponent(location.pathname.slice(3)) : (pages[0] || {}).id;
  const page = pages.find((p) => p.id === id);
  app.innerHTML = '';
  // Signed in as the manager: edit right here on the website.
  document.body.classList.toggle('has-admin', !!SPEC.manager);
  if (SPEC.manager) {
    const bar = el('<div class="adminbar"><div class="wrap"><b>' + icon('palette') + ' Manager view — edit anything with ✎ or + Add</b><a href="/manage">Dashboard</a><a href="/manage#website">Design & texts</a><button>Sign out</button></div></div>');
    $('button', bar).onclick = () => { localStorage.removeItem(KEY_NAME); KEY = ''; start(); };
    app.append(bar);
  }
  app.append(navbar(pages, id));
  const main = el('<main></main>'); app.append(main);
  if (!page) { main.append(el('<section class="sec"><div class="wrap"><div class="empty">This page doesn’t exist. <a href="/">Go to the home page</a></div></div></section>')); app.append(await footer(pages)); return; }
  document.title = page.title + ' · ' + SPEC.name;
  const state = {sel: {}, redrawLists: [], add: () => {}, formName: 'order'};
  const blocks = page.blocks.map((b) => ({...b}));
  const first = page === pages[0];
  // Every page opens with a big heading; the home page with a welcome.
  if (!blocks.some((b) => b.type === 'hero')) {
    if (blocks[0]?.type === 'text' && /^#/.test(blocks[0].text)) {
      const [h, ...rest] = blocks[0].text.split('\n');
      blocks[0] = {type: 'hero', title: h.replace(/^#+\s*/, ''), text: rest.join(' ').replace(/[#*]/g, '').trim()};
    } else if (first) blocks.unshift({type: 'hero', title: SPEC.name, text: (SPEC.site || {}).tagline || SPEC.summary});
  }
  if (first && blocks[0]?.type === 'hero' && !blocks[0].link && pages.length > 1) { const fp = pages.find((p) => p !== page && p.blocks.some((x) => x.type === 'form')) || pages[1]; blocks[0].link = fp.id; blocks[0].button = blocks[0].button || ctaText(fp); }
  const pg = {blocks};
  // Forms first, so lists know where "Add" goes; then show everything in order.
  const nodes = new Array(blocks.length);
  const fail = (e) => el('<div class="wrap"><div class="err">' + esc(e.message) + '</div></div>');
  for (const [i, b] of blocks.entries()) if (b.type === 'form' && table(b.table)) nodes[i] = await formBlock(b, table(b.table), pg, state).catch(fail);
  for (const [i, b] of blocks.entries()) {
    try {
      if (b.type === 'hero') nodes[i] = await heroBlock(b, first && i === 0);
      else if (b.type === 'text') nodes[i] = textBlock(b);
      else if (b.type === 'list' && table(b.table)) nodes[i] = await listBlock(b, table(b.table), pg, state);
      else if (b.type === 'info' && table(b.table)) nodes[i] = await infoBlock(b, table(b.table));
      else if (b.type === 'availability' && table(b.table)) nodes[i] = await availabilityBlock(b, table(b.table), state);
      else if (b.type === 'stay' && table(b.table)) nodes[i] = await stayBlock(b, table(b.table), state);
      else if (b.type === 'gallery') nodes[i] = await galleryBlock(b);
      else if (b.type === 'testimonials' && table(b.table)) nodes[i] = await testimonialsBlock(b, table(b.table));
      else if (b.type === 'contact') nodes[i] = await contactBlock(b);
      else if (b.type === 'features') nodes[i] = featuresBlock(b);
    } catch (e) { nodes[i] = fail(e); }
  }
  nodes.filter(Boolean).forEach((n) => main.append(n));
  app.append(await footer(pages));
  const acts = actionPages(pages).filter((p) => p.id !== id).slice(0, 2), ph2 = (SPEC.site || {}).phone;
  if (acts.length || ph2) {
    app.append(el('<nav class="mbar">' + (ph2 ? '<a class="btn call" aria-label="Call us" href="tel:' + esc(ph2.replace(/\s/g, '')) + '">' + icon('phone') + '</a>' : '') + acts.map((p, k) => '<a class="btn' + (k === 0 ? ' primary' : '') + '" href="/p/' + p.id + '">' + esc(p.title) + '</a>').join('') + '</nav>'));
    document.body.classList.add('has-mbar');
  }
}

// ================= manager =================
async function login() {
  const app = document.getElementById('app');
  app.innerHTML = '';
  const s = SPEC.site || {};
  const n = el('<div class="login"><form class="panel">' + (s.logo ? '<img src="' + esc(s.logo) + '" style="height:64px;margin:0 auto 18px" alt="">' : '<div class="monogram lg">' + esc((SPEC.name[0] || '?').toUpperCase()) + '</div>')
    + '<h1>' + esc(SPEC.name) + '</h1><p class="muted">Manager sign-in. Your PIN is shown in LocalAILine.</p><input inputmode="numeric" autocomplete="one-time-code" maxlength="12" placeholder="••••••" autofocus><button class="btn primary lg block">Sign in</button><div class="msg" style="margin-top:12px"></div><p style="margin-top:14px"><a class="muted" href="/" style="font-size:14px">← Back to the website</a></p></form></div>');
  $('form', n).onsubmit = async (e) => {
    e.preventDefault();
    const pin = $('input', n).value.trim();
    const r = await fetch('/api/_login', {method: 'POST', body: JSON.stringify({pin})});
    if (!r.ok) { $('.msg', n).innerHTML = '<div class="err">That PIN isn’t right.</div>'; return; }
    KEY = pin; localStorage.setItem(KEY_NAME, KEY); start();
  };
  app.append(n);
}

let VIEW = '', TIMER = null;
const SEEN = {};
const addTables = () => SPEC.tables.filter((t) => t.access.includes('add') && t.kind !== 'single');
// The status: the choice called "status", else the first one only the manager sets (payment is never the status).
const statusField = (t) => t.fields.find((f) => f.type === 'choice' && f.id === 'status') || t.fields.find((f) => f.type === 'choice' && f.manager_only) || t.fields.find((f) => f.type === 'choice' && /status|state|stage/.test(f.id));
function beep() { try { const a = new AudioContext(), o = a.createOscillator(), g = a.createGain(); o.connect(g); g.connect(a.destination); o.frequency.value = 880; g.gain.setValueAtTime(.12, a.currentTime); g.gain.exponentialRampToValueAtTime(.001, a.currentTime + .5); o.start(); o.stop(a.currentTime + .5); } catch (_) {} }
const singular = (s) => String(s).replace(/ies$/, 'y').replace(/s$/, '');
const ago = (s) => { const d = new Date(String(s).replace(' ', 'T')); const m = Math.round((Date.now() - d) / 60000); if (isNaN(m)) return ''; if (m < 1) return 'just now'; if (m < 60) return m + ' min ago'; if (m < 1440) return Math.round(m / 60) + ' h ago'; return Math.round(m / 1440) + ' d ago'; };
const nowMins = () => { const d = new Date(); return d.getHours() * 60 + d.getMinutes(); };
const dayLabel = (iso, opts = {weekday: 'short', day: 'numeric', month: 'short'}) => { const d = new Date(String(iso).slice(0, 10) + 'T12:00'); return isNaN(d) ? String(iso) : d.toLocaleDateString(undefined, opts); };

async function admin() {
  const app = document.getElementById('app');
  app.innerHTML = '';
  const people = addTables().some((t) => phoneOf(t));
  const shell = el('<div class="admin"><aside class="side"><a class="brand" href="/manage">' + monogram() + '<span>' + esc(SPEC.name) + '</span></a>'
    + '<button class="nav-btn" data-v="overview">' + icon('home') + 'Dashboard</button>' + (people ? '<button class="nav-btn" data-v="customers">' + icon('users') + 'Customers</button>' : '') + '<div class="grp">Your data</div>'
    + SPEC.tables.map((t) => '<button class="nav-btn" data-v="t:' + t.id + '">' + icon(t.kind === 'single' ? 'file' : (t.access.includes('add') ? 'bell' : (t.fields.some((f) => f.type === 'image') ? 'image' : 'list'))) + '<span class="nb-t">' + esc(t.title) + '</span><b class="nb-n" data-n="' + t.id + '"></b></button>').join('')
    + '<div class="grp">Website</div><button class="nav-btn" data-v="website">' + icon('palette') + 'Design & texts</button>'
    + '<div class="spacer"></div><a class="nav-btn" href="/" target="_blank">' + icon('ext') + 'View website</a><button class="nav-btn" data-v="logout">' + icon('out') + 'Sign out</button></aside><section class="content"></section></div>');
  app.append(shell);
  $$('.nav-btn[data-v]', shell).forEach((b) => b.onclick = () => go(b.dataset.v));
  window.onhashchange = () => { const v = decodeURIComponent(location.hash.slice(1)); if (v && v !== VIEW) go(v); };
  go(decodeURIComponent(location.hash.slice(1)) || 'overview');
}

/// The little numbers in the menu: what is waiting in each table (new orders, requests).
async function badges() {
  for (const t of addTables()) {
    const sf = statusField(t), n = $('[data-n="' + t.id + '"]'); if (!n || !sf) continue;
    const first = sf.options[0];
    const k = tone(first) === 'blue' ? (await rows(t.id).catch(() => [])).filter((r) => r[sf.id] === first).length : 0;
    n.textContent = k ? String(k) : '';
  }
}

async function go(v) {
  if (v === 'logout') { localStorage.removeItem(KEY_NAME); KEY = ''; return start(); }
  if (v.startsWith('t:') && !table(v.slice(2))) v = 'overview';
  VIEW = v; history.replaceState(null, '', '#' + v); clearInterval(TIMER);
  $$('.nav-btn[data-v]').forEach((b) => b.classList.toggle('on', b.dataset.v === v));
  const c = $('.content'); c.innerHTML = '<div class="boot" style="min-height:40vh"><div class="spinner"></div></div>';
  try {
    if (v === 'overview') await overview(c);
    else if (v === 'website') await website(c);
    else if (v === 'customers') await customers(c);
    else await manageTable(table(v.slice(2)), c);
  } catch (e) { c.innerHTML = '<div class="err">' + esc(e.message) + '</div>'; }
  badges().catch(() => {});
}

// ---------- charts ----------
/// Bars for the last 14 days (today last, in the main colour); hover a bar for its number.
function bars(counts, days) {
  const w = 300, h = 84, n = counts.length, gap = 3, bw = (w - gap * (n - 1)) / n, max = Math.max(1, ...counts);
  let s = '<svg class="bars" viewBox="0 0 ' + w + ' ' + (h + 20) + '" role="img" aria-label="Last 14 days">';
  s += '<line class="base" x1="0" x2="' + w + '" y1="' + (h + .5) + '" y2="' + (h + .5) + '"/>';
  counts.forEach((v, i) => {
    const x = i * (bw + gap), bh = v ? Math.max(4, v / max * (h - 6)) : 0, y = h - bh, r = Math.min(4, bw / 2, bh);
    s += '<g class="b' + (i === n - 1 ? ' today' : '') + '"><title>' + esc(dayLabel(days[i])) + ': ' + v + '</title><rect class="hit" x="' + x + '" y="0" width="' + (bw + gap) + '" height="' + h + '"/>'
      + (v ? '<path d="M' + x + ' ' + h + 'V' + (y + r) + 'Q' + x + ' ' + y + ' ' + (x + r) + ' ' + y + 'H' + (x + bw - r) + 'Q' + (x + bw) + ' ' + y + ' ' + (x + bw) + ' ' + (y + r) + 'V' + h + 'Z"/>' : '') + '</g>';
  });
  s += '<text x="0" y="' + (h + 16) + '">' + esc(dayLabel(days[0], {day: 'numeric', month: 'short'})) + '</text><text x="' + w + '" y="' + (h + 16) + '" text-anchor="end">Today</text>';
  return s + '</svg>';
}

/// When it is busy: one cell per hour, darker = busier.
function hourStrip(hours) {
  const max = Math.max(1, ...hours);
  let lo = hours.findIndex((v) => v > 0), hi = 23 - [...hours].reverse().findIndex((v) => v > 0);
  if (lo < 0) { lo = 9; hi = 21; }
  lo = Math.max(0, Math.min(lo - 1, 9)); hi = Math.min(23, Math.max(hi + 1, lo + 9));
  const peak = hours.indexOf(Math.max(...hours));
  let h = '<div class="hours">';
  for (let i = lo; i <= hi; i++) {
    const v = hours[i], k = v / max;
    h += '<div class="hcell' + (i === peak && v ? ' peak' : '') + '" title="' + String(i).padStart(2, '0') + ':00 – ' + v + '"><i style="background:color-mix(in srgb,var(--accent) ' + Math.round(6 + k * 84) + '%,var(--surface))"></i><small>' + (i % 2 === lo % 2 ? String(i).padStart(2, '0') : '') + '</small></div>';
  }
  return h + '</div>' + (hours[peak] ? '<p class="muted small">Busiest around <b>' + String(peak).padStart(2, '0') + ':00</b>.</p>' : '<p class="muted small">Nothing yet: this fills in as orders and bookings come in.</p>');
}

async function overview(c) {
  const st = await api('_stats');
  const hr = new Date().getHours();
  const hello = hr < 12 ? 'Good morning' : hr < 18 ? 'Good afternoon' : 'Good evening';
  for (const t of addTables()) await rows(t.id, true);
  const kinds = Object.values(st.tables || {}).map((x) => x.kind);
  c.innerHTML = '';
  c.append(el('<div class="head"><h1>' + hello + '</h1><a class="btn sm" href="/" target="_blank">' + icon('ext') + ' View website</a><p class="sub">' + esc(dayLabel(todayISO(), {weekday: 'long', day: 'numeric', month: 'long'})) + ' · here’s what’s happening at ' + esc(SPEC.name) + '.</p></div>'));
  const tiles = [];
  if (kinds.includes('bookings')) tiles.push(['cal', 'Bookings today', st.bookings_today, 'Not counting cancellations']);
  if (kinds.includes('orders')) tiles.push(['bag', 'Open orders', st.open_orders, 'Not done or cancelled yet'], ['tag', 'Takings today', money(st.revenue_today), st.orders_today + ' order' + (st.orders_today === 1 ? '' : 's') + ' today'], ['chart', 'Last 7 days', money(st.revenue_7d), 'Orders, by when they came in']);
  tiles.push(['bell', 'New today', st.new_today, 'Everything that came in today']);
  // Who didn't turn up (the last 30 days), where bookings can be marked "No-show".
  const ns = Object.values(st.no_shows || {});
  if (ns.length) { const k2 = ns.reduce((a, x) => a + x.count, 0), of = ns.reduce((a, x) => a + x.of, 0); tiles.push(['x', 'No-shows · 30 days', k2, of ? (Math.round(k2 * 1000 / of) / 10) + '% of ' + of + ' booking' + (of === 1 ? '' : 's') : 'No bookings in the last 30 days']); }
  const k = el('<div class="kpis">' + tiles.map(([ic, l, v, sub]) => '<div class="kpi"><small>' + icon(ic) + esc(l) + '</small><b>' + esc(String(v)) + '</b><span>' + esc(sub) + '</span></div>').join('') + '</div>');
  c.append(k);
  const dash = el('<div class="dash"><div class="dcol"></div><div class="dcol"></div></div>'); c.append(dash);
  const [left, right] = $$('.dcol', dash);
  // Last 14 days, one small chart per kind of record.
  const charts = el('<div class="card"><div class="card-h"><h3>Last 14 days</h3><span class="muted small">By the day they came in</span></div><div class="card-b"><div class="minis"></div></div></div>');
  for (const [id, x] of Object.entries(st.tables || {})) {
    const m = el('<div class="mini"><div class="mini-h"><b>' + esc(x.title) + '</b><span>' + x.counts.reduce((a, b) => a + b, 0) + ' in 14 days</span></div>' + bars(x.counts, st.days) + '</div>');
    m.onclick = () => go('t:' + id); $('.minis', charts).append(m);
  }
  left.append(charts);
  // What each service brought in (bookings in the last 30 days, not cancelled).
  for (const [id, x] of Object.entries(st.by_service || {})) {
    const max = Math.max(1, ...x.items.map((i) => i.revenue)), total = x.items.reduce((a, i) => a + i.revenue, 0);
    const card = el('<div class="card"><div class="card-h"><h3>' + esc(x.what) + ' · last 30 days</h3><span class="muted small">' + esc(money(total)) + ' booked</span></div><div class="card-b svc">'
      + x.items.map((i) => '<div class="svc-r"><div class="svc-n"><b>' + esc(i.name) + '</b><span class="muted small">' + i.count + ' booked</span></div><div class="svc-bar"><i style="width:' + Math.max(3, Math.round(i.revenue / max * 100)) + '%"></i></div><b class="num">' + esc(money(i.revenue)) + '</b></div>').join('') + '</div></div>');
    card.onclick = () => go('t:' + id);
    left.append(card);
  }
  left.append(el('<div class="card"><div class="card-h"><h3>Busiest hours</h3><span class="muted small">Booked times, and when orders come in</span></div><div class="card-b">' + hourStrip(st.hours || []) + '</div></div>'));
  right.append(await todayCard());
  right.append(await attentionCard());
  for (const t of addTables()) {
    const box = el('<div class="card" style="margin-top:22px"><div class="card-h"><h3>Latest ' + esc(t.title.toLowerCase()) + '</h3><button class="btn sm">See all</button></div><div class="tablewrap"></div></div>');
    $('button', box).onclick = () => go('t:' + t.id);
    c.append(box);
    await dataTable(t, $('.tablewrap', box), {limit: 6, fresh: false});
  }
  // New orders and bookings show up by themselves, with a soft ping.
  for (const t of addTables()) SEEN[t.id] = SEEN[t.id] ?? (await rows(t.id)).length;
  TIMER = setInterval(async () => {
    if (VIEW !== 'overview') return;
    let grew = false;
    for (const t of addTables()) { const n = (await rows(t.id, true)).length; if (n > (SEEN[t.id] || 0)) grew = true; SEEN[t.id] = n; }
    if (grew) { beep(); toast('Something new just came in'); go('overview'); }
  }, 15000);
}

/// Today, in time order, with a line at "now".
async function todayCard() {
  const items = [];
  for (const t of addTables()) {
    const df = dateOf(t), tf = timeOf(t), sf = statusField(t), sh = shapeOf(t);
    if (!df) continue;
    const links = await linkMaps(t);
    for (const r of await rows(t.id)) {
      if (!String(r[df.id] || '').startsWith(todayISO()) || (sf && tone(r[sf.id]) === 'red')) continue;
      const at = tf ? r[tf.id] : (df.type === 'datetime' ? String(r[df.id]).slice(11, 16) : '');
      const g = sh && sh.guests && r[sh.guests.id] ? r[sh.guests.id] + ' people' : '';
      const where = sh && r[sh.link.id] ? sh.res.title.replace(/s$/, '') + ' ' + fmt(sh.link, r[sh.link.id], links) : '';
      items.push({t, r, at: at || '', sub: [singular(t.title), g, where].filter(Boolean).join(' · '), st: sf ? r[sf.id] : ''});
    }
  }
  items.sort((a, b) => String(a.at).localeCompare(String(b.at)));
  const box = el('<div class="card"><div class="card-h"><h3>Today</h3><span class="muted small">' + items.length + ' booked</span></div><div class="card-b tline"></div></div>');
  const body = $('.tline', box), now = nowMins();
  let lined = false;
  const line = () => { if (lined) return; lined = true; body.append(el('<div class="nowrow"><span>' + toHHMM(now) + '</span><i></i></div>')); };
  if (!items.length) body.innerHTML = '<div class="muted">Nothing booked for today yet.</div>';
  for (const it of items) {
    if (toMin(it.at) !== null && toMin(it.at) > now) line();
    const n = el('<button class="trow' + (toMin(it.at) !== null && toMin(it.at) + 60 < now ? ' past' : '') + '"><b>' + esc(it.at || '–') + '</b><div><div class="tn">' + esc(nameOf(it.t, it.r)) + '</div><small>' + esc(it.sub) + '</small></div>' + pill(it.st) + '</button>');
    n.onclick = () => record(it.t, it.r, () => go(VIEW));
    body.append(n);
  }
  if (items.length) line();
  return box;
}

/// New things nobody has looked at: orders still "New", requests, enquiries.
async function attentionCard() {
  const list = [];
  for (const t of addTables()) {
    const sf = statusField(t); if (!sf) continue;
    const first = sf.options[0]; if (tone(first) !== 'blue') continue;
    const df = dateOf(t);
    for (const r of await rows(t.id)) if ((r[sf.id] || first) === first && (!df || !r[df.id] || String(r[df.id]).slice(0, 10) >= todayISO())) list.push({t, r, sf});
  }
  list.sort((a, b) => String(b.r.created_at).localeCompare(String(a.r.created_at)));
  const box = el('<div class="card"><div class="card-h"><h3>Needs attention</h3><span class="muted small">' + list.length + ' waiting</span></div><div class="card-b att"></div></div>');
  const body = $('.att', box);
  if (!list.length) body.innerHTML = '<div class="allgood">' + icon('check') + '<div><b>All caught up</b><div class="muted small">New orders and requests show here.</div></div></div>';
  for (const {t, r, sf} of list.slice(0, 8)) {
    const next = sf.options[1];
    const n = el('<div class="arow"><div class="a-ic">' + icon(isOrders(t) ? 'bag' : 'bell') + '</div><div class="a-b"><b>' + esc(nameOf(t, r)) + '</b><small>' + esc(singular(t.title)) + ' · ' + esc(ago(r.created_at)) + (r.via === 'phone' ? ' · by phone' : '') + '</small></div>' + (next ? '<button class="btn sm">' + esc(next) + '</button>' : '') + '</div>');
    n.onclick = () => record(t, r, () => go(VIEW));
    const b = $('button', n);
    if (b) b.onclick = async (e) => { e.stopPropagation(); await api('t/' + t.id + '/' + r.id, {method: 'PUT', body: JSON.stringify({[sf.id]: next})}); delete cache[t.id]; toast(sf.label + ': ' + next); go(VIEW); };
    body.append(n);
  }
  return box;
}

/// A table of records: sortable columns, status you can change in place, totals for orders.
async function dataTable(t, box, o = {}) {
  const {limit = 0, q = '', filter = '', when = '', fresh = true} = o;
  let all = [...await rows(t.id, fresh)].reverse();
  const links = await linkMaps(t), sf = statusField(t), imgF = t.fields.find((f) => f.type === 'image'), df = dateOf(t), orders = isOrders(t);
  const label = labelOf(t);
  if (q) all = all.filter((r) => JSON.stringify(r).toLowerCase().includes(q) || t.fields.some((f) => f.link && fmt(f, r[f.id], links).toLowerCase().includes(q)));
  if (filter && sf) all = all.filter((r) => r[sf.id] === filter);
  if (when && df) { const d0 = todayISO(); all = all.filter((r) => { const d = String(r[df.id] || '').slice(0, 10); return when === 'today' ? d === d0 : when === 'upcoming' ? d >= d0 : (d && d < d0); }); }
  const sort = box._sort || (box._sort = {k: '', dir: 1});
  if (sort.k) {
    const f = t.fields.find((x) => x.id === sort.k);
    const key = (r) => sort.k === '_total' ? (orderCalc(t, r, links)?.total ?? -1) : sort.k === '_added' ? String(r.created_at || '') : f && (f.type === 'number' || f.type === 'money') ? Number(r[f.id] ?? -1e15) : (f && f.link ? fmt(f, r[f.id], links) : String(r[sort.k] ?? '')).toLowerCase();
    all.sort((a, b) => { const x = key(a), y = key(b); return (x > y ? 1 : x < y ? -1 : 0) * sort.dir; });
  }
  if (o.out) { o.out.rows = all; o.out.links = links; }
  if (o.onCount) o.onCount(all.length);
  if (limit) all = all.slice(0, limit);
  const totalF = t.fields.find((f) => f.type === 'money' && /^(order_)?total$/.test(f.id));
  const cols = t.fields.filter((f) => f.id !== label && f !== sf && f !== totalF && f.type !== 'image' && f.type !== 'longtext' && !(f.when && limit)).slice(0, limit ? 3 : 5);
  if (!all.length) { box.innerHTML = '<div class="empty" style="margin:20px;border:0">' + icon(q ? 'search' : 'list') + '<div>' + (q || filter || when ? 'Nothing matches.' : 'Nothing here yet.') + '</div></div>'; return; }
  const th = (k, l, cls = '') => '<th data-k="' + esc(k) + '" class="' + cls + (sort.k === k ? ' sorted' : '') + '">' + esc(l) + (limit ? '' : '<i class="sort-ic">' + (sort.k === k ? (sort.dir > 0 ? '▲' : '▼') : '') + '</i>') + '</th>';
  box.innerHTML = '<table class="data' + (limit ? '' : ' sortable') + '"><thead><tr>' + th(label, t.fields.find((f) => f.id === label)?.label || 'Name') + cols.map((f) => th(f.id, f.label, f.type === 'money' || f.type === 'number' ? 'num' : '')).join('')
    + (orders ? th('_total', 'Total', 'num') : '') + (sf ? th(sf.id, sf.label) : '') + th('_added', 'Added · from') + '</tr></thead><tbody></tbody></table>';
  if (!limit) $$('th[data-k]', box).forEach((h) => h.onclick = () => { const k = h.dataset.k; sort.dir = sort.k === k ? -sort.dir : (k === '_added' || k === '_total' ? -1 : 1); sort.k = k; dataTable(t, box, {...o, fresh: false}); });
  const tb = $('tbody', box);
  const cell = (f, v) => {
    if (v === null || v === undefined || v === '') return '<td class="muted">–</td>';
    if (f.type === 'choice') return '<td>' + (f.manager_only ? pill(v) : '<span class="tag">' + esc(v) + '</span>') + '</td>';
    if (f.type === 'yesno') return '<td>' + (v ? '<span class="yes">' + icon('check') + '</span>' : '<span class="muted">–</span>') + '</td>';
    if (f.type === 'phone') return '<td><a class="tel" href="tel:' + esc(String(v).replace(/\s/g, '')) + '">' + esc(v) + '</a></td>';
    return '<td class="' + (f.type === 'money' || f.type === 'number' ? 'num' : '') + '">' + esc(fmt(f, v, links)) + '</td>';
  };
  for (const r of all) {
    const fresh10 = Date.now() - new Date(String(r.created_at).replace(' ', 'T')).getTime() < 600000;
    const calc = orders ? orderCalc(t, r, links) : null;
    const tr = el('<tr' + (fresh10 && t.access.includes('add') ? ' class="new"' : '') + '><td><div class="cell-main">' + (imgF ? '<div class="thumb-sm">' + media(r[imgF.id], nameOf(t, r), 'sm') + '</div>' : '') + '<span>' + esc(nameOf(t, r)) + '</span></div></td>'
      + cols.map((f) => cell(f, r[f.id])).join('')
      + (orders ? '<td class="num"><b>' + (calc ? esc(money(calc.total)) : '–') + '</b>' + (calc && calc.fee ? '<small class="muted"> incl. delivery</small>' : '') + '</td>' : '')
      + (sf ? '<td><select class="status t-' + tone(r[sf.id]) + '">' + sf.options.map((x) => '<option' + (x === r[sf.id] ? ' selected' : '') + '>' + esc(x) + '</option>').join('') + '</select></td>' : '')
      + '<td class="muted" style="white-space:nowrap">' + esc(r.created_at || '') + (r.via === 'phone' ? ' <span class="tag acc">' + icon('phone') + ' Phone</span>' : (r.via === 'website' ? ' <span class="tag">Website</span>' : '')) + '</td></tr>');
    if (sf) { const s = $('select', tr); s.onclick = (e) => e.stopPropagation(); s.onchange = async () => { await api('t/' + t.id + '/' + r.id, {method: 'PUT', body: JSON.stringify({[sf.id]: s.value})}); s.className = 'status t-' + tone(s.value); r[sf.id] = s.value; delete cache[t.id]; toast(sf.label + ': ' + s.value); badges().catch(() => {}); }; }
    $$('a.tel', tr).forEach((a) => a.onclick = (e) => e.stopPropagation());
    tr.onclick = () => record(t, r, () => go(VIEW));
    tb.append(tr);
  }
}

/// Columns per status; drag a card (or press its arrow) to move it on.
async function boardView(t, box, {q = '', when = ''} = {}) {
  const sf = statusField(t), links = await linkMaps(t), df = dateOf(t), tf = timeOf(t), orders = isOrders(t);
  let all = [...await rows(t.id)].reverse();
  if (q) all = all.filter((r) => JSON.stringify(r).toLowerCase().includes(q) || t.fields.some((f) => f.link && fmt(f, r[f.id], links).toLowerCase().includes(q)));
  if (when && df) { const d0 = todayISO(); all = all.filter((r) => { const d = String(r[df.id] || '').slice(0, 10); return when === 'today' ? d === d0 : when === 'upcoming' ? d >= d0 : (d && d < d0); }); }
  box.innerHTML = '<div class="board">' + sf.options.map((o) => '<div class="col" data-s="' + esc(o) + '"><div class="col-h">' + pill(o) + '<span class="muted small">' + all.filter((r) => (r[sf.id] || sf.options[0]) === o).length + '</span></div><div class="col-b"></div></div>').join('') + '</div>';
  const move = async (r, to) => { if (r[sf.id] === to) return; await api('t/' + t.id + '/' + r.id, {method: 'PUT', body: JSON.stringify({[sf.id]: to})}); r[sf.id] = to; delete cache[t.id]; toast(nameOf(t, r) + ': ' + to); boardView(t, box, {q, when}); badges().catch(() => {}); };
  for (const r of all) {
    const st = r[sf.id] || sf.options[0], i = sf.options.indexOf(st), next = sf.options[i + 1];
    const calc = orders ? orderCalc(t, r, links) : null;
    const when2 = df && r[df.id] ? dayLabel(r[df.id]) + (tf && r[tf.id] ? ' · ' + r[tf.id] : '') : '';
    const items = calc ? calc.lines.map((l) => l.qty + '× ' + l.name).join(', ') : '';
    // What it is about at a glance (the car and its registration, say).
    const about = t.fields.filter((f) => f.type === 'text' && f.required && !f.when && !f.manager_only && f.id !== labelOf(t) && r[f.id]).slice(0, 2).map((f) => r[f.id]).join(' · ');
    const card = el('<div class="kcard" draggable="true"><div class="k-top"><b>' + esc(nameOf(t, r)) + '</b>' + (calc ? '<span class="price">' + esc(money(calc.total)) + '</span>' : '') + '</div>'
      + (about ? '<small>' + icon('tag') + ' ' + esc(about) + '</small>' : '') + (when2 ? '<small>' + icon('cal') + ' ' + esc(when2) + '</small>' : '') + (items ? '<small class="k-items">' + esc(items) + '</small>' : '')
      + '<div class="k-foot"><span class="muted small">' + esc(ago(r.created_at)) + (r.via === 'phone' ? ' · phone' : '') + '</span>' + (next && tone(next) !== 'red' ? '<button class="btn sm" title="Move to ' + esc(next) + '">' + esc(next) + ' ' + icon('arrow') + '</button>' : '') + '</div></div>');
    card.ondragstart = (e) => { e.dataTransfer.setData('text/plain', String(r.id)); card.classList.add('drag'); };
    card.ondragend = () => card.classList.remove('drag');
    card.onclick = () => record(t, r, () => boardView(t, box, {q, when}));
    const b = $('.k-foot button', card); if (b) b.onclick = (e) => { e.stopPropagation(); move(r, next); };
    $('.col[data-s="' + CSS.escape(st) + '"] .col-b', box)?.append(card);
  }
  $$('.col', box).forEach((col) => {
    col.ondragover = (e) => { e.preventDefault(); col.classList.add('over'); };
    col.ondragleave = () => col.classList.remove('over');
    col.ondrop = (e) => { e.preventDefault(); col.classList.remove('over'); const r = all.find((x) => String(x.id) === e.dataTransfer.getData('text/plain')); if (r) move(r, col.dataset.s); };
  });
}

/// The records as a spreadsheet file (opens in Excel or Numbers).
function exportCsv(t, list, links) {
  const orders = isOrders(t);
  const fs = t.fields.filter((f) => f.type !== 'image');
  const head = ['id', ...fs.map((f) => f.label), ...(orders ? ['Total'] : []), 'Added', 'From'];
  const q = (v) => { const s = String(v ?? ''); return /[",\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s; };
  const lines = [head.map(q).join(',')];
  for (const r of list) lines.push([r.id, ...fs.map((f) => f.type === 'money' || f.type === 'number' ? (r[f.id] ?? '') : fmt(f, r[f.id], links)), ...(orders ? [orderCalc(t, r, links)?.total ?? ''] : []), r.created_at || '', r.via || ''].map(q).join(','));
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob(['﻿' + lines.join('\n')], {type: 'text/csv'}));
  a.download = t.id + '-' + todayISO() + '.csv'; document.body.append(a); a.click(); a.remove();
}

async function manageTable(t, c) {
  c.innerHTML = '';
  if (t.kind === 'single') {
    const r = (await rows(t.id, true))[0] || {};
    c.append(el('<div class="head"><h1>' + esc(t.title) + '</h1><p class="sub">' + esc(t.purpose || '') + '</p></div>'));
    const card = el('<div class="card" style="max-width:760px"><div class="card-b"><div class="fgrid"></div><button class="btn primary lg">Save</button></div></div>');
    const inputs = []; for (const f of t.fields) { const i = await fieldInput(f, r[f.id]); $('.fgrid', card).append(i.node); inputs.push(i); }
    $('button.primary', card).onclick = async () => { const b = {}; for (const i of inputs) b[i.f.id] = i.get(); try { await api('t/' + t.id, {method: 'PUT', body: JSON.stringify(b)}); delete cache[t.id]; toast('Saved'); } catch (e) { toast(e.message); } };
    c.append(card);
    return;
  }
  const sf = statusField(t), df = dateOf(t), canBoard = sf && sf.options.length >= 3;
  // A month calendar for records on a day (cars booked in, viewings, events): timed bookings have the day plan instead.
  const canCal = df && df.type === 'date' && !shapeOf(t) && !stayShape(t);
  const modes = [['table', 'list', 'Table'], ...(canBoard ? [['board', 'board', 'Board']] : []), ...(canCal ? [['calendar', 'cal', 'Calendar']] : [])];
  const modeKey = 'view_' + location.port + '_' + t.id, saved = localStorage.getItem(modeKey);
  // A job that moves along (in the workshop, preparing, packing) opens as a board.
  let mode = modes.some(([m]) => m === saved) ? saved : canBoard && /workshop|progress|prepar|packing/i.test(sf.options.join(' ')) ? 'board' : 'table';
  const head = el('<div class="head"><h1>' + esc(t.title) + ' <span class="count"></span></h1>'
    + (modes.length > 1 ? '<div class="seg">' + modes.map(([m, ic, l]) => '<button data-m="' + m + '">' + icon(ic) + ' ' + l + '</button>').join('') + '</div>' : '')
    + '<button class="btn" data-a="csv">' + icon('download') + ' Export</button><button class="btn" data-a="photo">' + icon('image') + ' Add from a photo</button><button class="btn primary" data-a="add">' + icon('plus') + ' Add</button><p class="sub">' + esc(t.purpose || '') + '</p></div>');
  $('[data-a=add]', head).onclick = () => drawer(t, null, () => go(VIEW));
  $('[data-a=photo]', head).onclick = () => importPhoto(t, () => go(VIEW));
  c.append(head);
  const bar = el('<div class="toolbar"><div class="search">' + icon('search') + '<input placeholder="Search"></div></div>');
  let q = '', filter = '', when = '';
  const chips = (opts, onPick) => { const box = el('<div class="chips"></div>'); for (const [v, l] of opts) { const b = el('<button class="pill-opt' + (v ? '' : ' on') + '">' + esc(l) + '</button>'); b.onclick = () => { onPick(v); $$('.pill-opt', box).forEach((x) => x.classList.toggle('on', x === b)); draw(); }; box.append(b); } bar.append(box); return box; };
  if (df) chips([['', 'All dates'], ['today', 'Today'], ['upcoming', 'Upcoming'], ['past', 'Past']], (v) => when = v);
  const stChips = sf ? chips([['', 'All'], ...sf.options.map((o) => [o, o])], (v) => filter = v) : null;
  c.append(bar);
  const box = el('<div class="card"><div class="tablewrap"></div></div>'); c.append(box);
  const out = {};
  const count = (n) => { $('.count', head).textContent = n + ' ' + (n === 1 ? singular(t.title).toLowerCase() : t.title.toLowerCase()); };
  const draw = async () => {
    $$('.seg button', head).forEach((b) => b.classList.toggle('on', b.dataset.m === mode));
    if (stChips) stChips.style.display = mode === 'table' ? '' : 'none';
    box.classList.toggle('plain', mode === 'board');
    if (mode === 'board') { await boardView(t, $('.tablewrap', box), {q, when}); const n = $$('.kcard', box).length; count(n); }
    else if (mode === 'calendar') { await monthView(t, $('.tablewrap', box), {q}); count((await rows(t.id)).length); }
    else await dataTable(t, $('.tablewrap', box), {q, filter, when, fresh: false, out, onCount: count});
  };
  $$('.seg button', head).forEach((b) => b.onclick = () => { mode = b.dataset.m; localStorage.setItem(modeKey, mode); draw(); });
  $('[data-a=csv]', head).onclick = async () => { if (!out.rows) await dataTable(t, el('<div></div>'), {q, filter, when, fresh: false, out}); exportCsv(t, out.rows || [], out.links || {}); };
  $('input', bar).oninput = (e) => { q = e.target.value.toLowerCase(); draw(); };
  // Bookings of tables, stylists, rooms…: a day plan as well as the list.
  if (shapeOf(t)) {
    const plan = el('<div class="card" style="margin-bottom:22px"></div>');
    c.insertBefore(plan, bar);
    await (localStorage.getItem(modeKey + '_plan') === 'week' ? weekView(t, plan) : dayPlanView(t, plan));
  }
  // Stays (rooms by night): who is in which room, two weeks at a time.
  if (stayShape(t)) {
    const occ = el('<div class="card" style="margin-bottom:22px"></div>');
    c.insertBefore(occ, bar);
    await occupancyView(t, occ);
  }
  await rows(t.id, true); await draw();
}

/// The manager's day: every table (stylist, room…) across the opening hours, bookings by name, a line at now.
async function dayPlanView(t, box, date) {
  const sh = shapeOf(t);
  date = date || todayISO();
  const plan = await api('_plan/' + t.id + '?date=' + date);
  const ss = slotsOf(plan);
  const shift = (d) => { const x = new Date(date + 'T12:00'); x.setDate(x.getDate() + d); return x.toISOString().slice(0, 10); };
  const label = new Date(date + 'T12:00').toLocaleDateString(undefined, {weekday: 'long', day: 'numeric', month: 'long'});
  const count = new Set(plan.busy.map((h) => h.id)).size;
  let h = '<div class="card-h"><h3>Day plan · ' + esc(label) + '</h3><div class="seg"><button class="on">Day</button><button data-w="1">Week</button></div><div class="daynav"><button class="btn sm" data-d="-1">←</button><input type="date" style="width:auto" value="' + date + '"><button class="btn sm" data-d="1">→</button><button class="btn sm" data-d="0">Today</button></div></div>'
    + '<div class="card-b">' + (plan.closed ? '<div class="closed-note">' + icon('cal') + ' Closed this day' + (plan.closed !== 'closed' ? ': ' + esc(plan.closed) : '') + '. Customers can’t book it.</div>' : '')
    + '<div class="muted" style="margin-bottom:8px">' + count + ' booking' + (count === 1 ? '' : 's') + ' · each holds a ' + esc(sh.res.title.toLowerCase().replace(/s$/, '')) + ' for ' + plan.minutes + ' minutes (change it in Design & texts). Click an empty slot to add a booking.</div><div class="tl"><table><tr><th class="rn">' + esc(sh.res.title) + '</th>' + ss.map((m) => '<th>' + toHHMM(m) + '</th>').join('') + '</tr>';
  for (const r of plan.resources) {
    h += '<tr><th class="rn">' + esc(r.name) + (r.seats ? ' <span style="color:var(--muted);font-weight:400">· ' + r.seats + '</span>' : '') + '</th>';
    for (let i = 0; i < ss.length; i++) {
      const b = plan.busy.find((x) => x.resource === r.id && ss[i] >= toMin(x.from) && ss[i] < toMin(x.from) + plan.minutes);
      if (b) {
        let k = 1; while (i + k < ss.length && ss[i + k] < toMin(b.from) + plan.minutes) k++;
        h += '<td class="b" colspan="' + k + '" data-id="' + b.id + '" title="' + esc(b.who + (b.guests ? ' · ' + b.guests + ' people' : '') + ' · ' + b.from + '–' + b.to) + '">' + esc(b.who) + (b.guests ? ' · ' + b.guests : '') + ' <span style="opacity:.75;font-weight:500">' + esc(b.from) + '</span></td>';
        i += k - 1;
      } else h += '<td class="f' + (date === todayISO() && ss[i] + 30 <= nowMins() ? ' past' : '') + '" data-r="' + r.id + '" data-m="' + ss[i] + '"></td>';
    }
    h += '</tr>';
  }
  box.innerHTML = h + '</table></div></div>';
  // Now, as a line across the plan.
  if (date === todayISO()) {
    const now = nowMins(), i = ss.findIndex((m) => now >= m && now < m + 30), ths = $$('.tl tr:first-child th', box).slice(1);
    if (i >= 0 && ths[i]) { const x = ths[i].offsetLeft + (now - ss[i]) / 30 * ths[i].offsetWidth; $('.tl', box).append(el('<div class="nowline" style="left:' + x + 'px"><span>' + toHHMM(now) + '</span></div>')); }
  }
  $$('[data-d]', box).forEach((b) => b.onclick = () => dayPlanView(t, box, +b.dataset.d === 0 ? todayISO() : shift(+b.dataset.d)));
  $('input[type=date]', box).onchange = (e) => dayPlanView(t, box, e.target.value);
  $('[data-w]', box).onclick = () => { localStorage.setItem('view_' + location.port + '_' + t.id + '_plan', 'week'); weekView(t, box, date); };
  $('table', box).onclick = async (e) => {
    const c = e.target.closest('td'); if (!c) return;
    if (c.dataset.id) { const r = (await rows(t.id, true)).find((x) => String(x.id) === c.dataset.id); if (r) record(t, r, () => go(VIEW)); return; }
    if (c.dataset.r) drawer(t, null, () => go(VIEW), {[sh.date.id]: date, [sh.time.id]: toHHMM(+c.dataset.m), [sh.link.id]: +c.dataset.r});
  };
}

const isoOf = (d) => { const x = new Date(d); x.setMinutes(x.getMinutes() - x.getTimezoneOffset()); return x.toISOString().slice(0, 10); };
const plusDays = (iso, k) => { const d = new Date(iso + 'T12:00'); d.setDate(d.getDate() + k); return isoOf(d); };

/// The manager's week: a column per day, the opening hours down the side, each booking with who and with whom.
async function weekView(t, box, date) {
  const sh = shapeOf(t), sf = statusField(t);
  const d0 = new Date((date || todayISO()) + 'T12:00'); d0.setDate(d0.getDate() - (d0.getDay() + 6) % 7);
  const days = [...Array(7)].map((_, i) => plusDays(isoOf(d0), i));
  const plans = await Promise.all(days.map((d) => api('_plan/' + t.id + '?date=' + d)));
  const all = await rows(t.id, true), links = await linkMaps(t);
  const o = toMin(plans[0].open) ?? 540, cl = toMin(plans[0].close) ?? 1080, c2 = cl <= o ? cl + 1440 : cl;
  const hours = []; for (let k = Math.floor(o / 60); k * 60 < c2; k++) hours.push(k % 24);
  const by = {}; let n = 0;
  for (const r of all) {
    const d = String(r[sh.date.id] || ''), m = toMin(r[sh.time.id]);
    if (!days.includes(d) || m === null || (sf && tone(r[sf.id]) === 'red')) continue;
    let k = Math.floor(m / 60); if (!hours.includes(k)) k = m < o ? hours[0] : hours[hours.length - 1];
    (by[d + '|' + k] = by[d + '|' + k] || []).push(r); n++;
  }
  for (const l of Object.values(by)) l.sort((x, y) => String(x[sh.time.id]).localeCompare(String(y[sh.time.id])));
  const label = dayLabel(days[0], {day: 'numeric', month: 'long'}) + ' – ' + dayLabel(days[6], {day: 'numeric', month: 'long'});
  let h = '<div class="card-h"><h3>Week · ' + esc(label) + '</h3><div class="seg"><button data-w="0">Day</button><button class="on">Week</button></div><div class="daynav"><button class="btn sm" data-k="-7">←</button><button class="btn sm" data-k="0">This week</button><button class="btn sm" data-k="7">→</button></div></div>'
    + '<div class="card-b"><div class="muted" style="margin-bottom:8px">' + n + ' booking' + (n === 1 ? '' : 's') + ' this week · click a booking to open it, or an empty hour to add one.</div><div class="wk"><table><tr><th></th>'
    + days.map((d, i) => '<th class="' + (d === todayISO() ? 'today' : '') + (plans[i].closed ? ' shut' : '') + '">' + esc(dayLabel(d)) + (plans[i].closed ? '<small>Closed</small>' : '') + '</th>').join('') + '</tr>';
  for (const k of hours) {
    h += '<tr><th class="hr">' + String(k).padStart(2, '0') + ':00</th>';
    days.forEach((d, i) => {
      const list = by[d + '|' + k] || [];
      h += '<td class="' + (plans[i].closed ? 'shut' : '') + (d < todayISO() ? ' past' : '') + '" data-d="' + d + '" data-h="' + k + '">' + list.map((r) => '<button class="wk-b t-' + tone(sf ? r[sf.id] : '') + '" data-id="' + r.id + '"><b>' + esc(r[sh.time.id]) + '</b> ' + esc(nameOf(t, r)) + '<small>' + esc(fmt(sh.link, r[sh.link.id], links)) + '</small></button>').join('') + '</td>';
    });
    h += '</tr>';
  }
  box.innerHTML = h + '</table></div></div>';
  $$('[data-k]', box).forEach((b) => b.onclick = () => weekView(t, box, +b.dataset.k === 0 ? todayISO() : plusDays(days[0], +b.dataset.k)));
  $('[data-w]', box).onclick = () => { localStorage.setItem('view_' + location.port + '_' + t.id + '_plan', 'day'); dayPlanView(t, box, days.includes(todayISO()) ? todayISO() : days[0]); };
  $('table', box).onclick = (e) => {
    const b = e.target.closest('.wk-b');
    if (b) { const r = all.find((x) => String(x.id) === b.dataset.id); if (r) record(t, r, () => go(VIEW)); return; }
    const c = e.target.closest('td[data-d]');
    if (c && !c.classList.contains('shut')) drawer(t, null, () => go(VIEW), {[sh.date.id]: c.dataset.d, [sh.time.id]: String(c.dataset.h).padStart(2, '0') + ':00'});
  };
}

/// A month at a glance: each record on its day (cars booked in, viewings, events), today marked.
async function monthView(t, box, o = {}) {
  const df = dateOf(t), sf = statusField(t);
  let all = await rows(t.id);
  if (o.q) { const links = await linkMaps(t); all = all.filter((r) => JSON.stringify(r).toLowerCase().includes(o.q) || t.fields.some((f) => f.link && fmt(f, r[f.id], links).toLowerCase().includes(o.q))); }
  const m0 = box._month || todayISO().slice(0, 7);
  const first = new Date(m0 + '-01T12:00'), start = new Date(first); start.setDate(1 - (first.getDay() + 6) % 7);
  const cells = []; for (let i = 0; i < 42; i++) { const d = new Date(start); d.setDate(start.getDate() + i); cells.push(isoOf(d)); if (i % 7 === 6 && cells[i].slice(0, 7) > m0) break; }
  const by = {}; for (const r of all) { const d = String(r[df.id] || '').slice(0, 10); (by[d] = by[d] || []).push(r); }
  const shown = all.filter((r) => String(r[df.id] || '').startsWith(m0) && !(sf && tone(r[sf.id]) === 'red')).length;
  const title = first.toLocaleDateString(undefined, {month: 'long', year: 'numeric'});
  let h = '<div class="cal"><div class="cal-h"><button class="btn sm" data-m="-1">←</button><h3>' + esc(title) + '</h3><button class="btn sm" data-m="1">→</button><button class="btn sm" data-m="0">Today</button><span class="muted small">' + shown + ' this month · click a day to add one</span></div><div class="cal-g">'
    + ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].map((d) => '<div class="cal-dn">' + d + '</div>').join('');
  for (const d of cells) {
    const list = (by[d] || []).sort((x, y) => String(x[df.id]).localeCompare(String(y[df.id])));
    h += '<div class="cal-d' + (d.slice(0, 7) !== m0 ? ' other' : '') + (d === todayISO() ? ' today' : '') + (d < todayISO() ? ' past' : '') + '" data-d="' + d + '"><span class="cal-n">' + Number(d.slice(8)) + '</span>'
      + list.slice(0, 3).map((r) => '<button class="cal-b t-' + tone(sf ? r[sf.id] : '') + '" data-id="' + r.id + '">' + esc(nameOf(t, r)) + '</button>').join('')
      + (list.length > 3 ? '<button class="cal-more" data-more="' + d + '">+' + (list.length - 3) + ' more</button>' : '') + '</div>';
  }
  box.innerHTML = h + '</div></div>';
  $$('[data-m]', box).forEach((b) => b.onclick = () => { const k = +b.dataset.m; if (!k) box._month = todayISO().slice(0, 7); else { const d = new Date(m0 + '-15T12:00'); d.setMonth(d.getMonth() + k); box._month = isoOf(d).slice(0, 7); } monthView(t, box, o); });
  $('.cal-g', box).onclick = (e) => {
    const b = e.target.closest('.cal-b');
    if (b) { const r = all.find((x) => String(x.id) === b.dataset.id); if (r) record(t, r, () => monthView(t, box, o)); return; }
    const more = e.target.closest('.cal-more');
    if (more) { const c = more.parentElement; c.classList.add('open'); c.innerHTML = '<span class="cal-n">' + Number(more.dataset.more.slice(8)) + '</span>' + by[more.dataset.more].map((r) => '<button class="cal-b t-' + tone(sf ? r[sf.id] : '') + '" data-id="' + r.id + '">' + esc(nameOf(t, r)) + '</button>').join(''); return; }
    const c = e.target.closest('.cal-d');
    if (c) drawer(t, null, () => monthView(t, box, o), {[df.id]: c.dataset.d});
  };
}

/// Stays (a room from one date to another): the dates and the room.
function stayShape(t) {
  const ds = t.fields.filter((f) => f.type === 'date'), room = t.fields.find((f) => f.type === 'link' && /room|suite|cabin|lodge|apartment|unit|pitch/.test(f.id + ' ' + f.link)) || t.fields.find((f) => f.type === 'link');
  return t.kind !== 'single' && ds.length >= 2 && room && !t.fields.some((f) => f.type === 'time') ? {from: ds[0], to: ds[1], room} : null;
}

/// Rooms by night: who is staying where, two weeks at a time, today marked; click a free night to add a stay.
async function occupancyView(t, box, from) {
  const st = stayShape(t);
  from = from || todayISO();
  const o = await api('_occupancy/' + t.id + '?from=' + from + '&days=14');
  const nights = o.nights, last = plusDays(nights[nights.length - 1], 1);
  let booked = 0;
  for (const s of o.stays) for (const d of nights) if (s.from <= d && d < s.to) booked++;
  const rate = o.rooms.length ? Math.round(booked * 100 / (o.rooms.length * nights.length)) : 0;
  let h = '<div class="card-h"><h3>Rooms by night · ' + esc(dayLabel(nights[0], {day: 'numeric', month: 'short'})) + ' – ' + esc(dayLabel(last, {day: 'numeric', month: 'short'})) + '</h3><span class="occ-rate"><b>' + rate + '%</b> full</span><div class="daynav"><button class="btn sm" data-k="-7">←</button><button class="btn sm" data-k="0">Today</button><button class="btn sm" data-k="7">→</button></div></div>'
    + '<div class="card-b"><div class="muted" style="margin-bottom:8px">' + o.stays.length + ' stay' + (o.stays.length === 1 ? '' : 's') + ' in these two weeks · click a stay to open it, or a free night to add one.</div><div class="tl occ"><table><tr><th class="rn">' + esc(table(st.room.link)?.title || 'Rooms') + '</th>'
    + nights.map((d) => '<th class="' + (d === todayISO() ? 'today' : '') + (o.closed[d] ? ' shut' : '') + '">' + esc(dayLabel(d, {weekday: 'short'})) + '<small>' + Number(d.slice(8)) + '</small></th>').join('') + '</tr>';
  for (const r of o.rooms) {
    h += '<tr><th class="rn">' + esc(r.name) + '</th>';
    for (let i = 0; i < nights.length; i++) {
      const s = o.stays.find((x) => x.room === r.id && x.from <= nights[i] && nights[i] < x.to);
      if (s) {
        let k = 1; while (i + k < nights.length && nights[i + k] < s.to) k++;
        h += '<td class="b t-' + tone(s.status) + '" colspan="' + k + '" data-id="' + s.id + '" title="' + esc(s.who + (s.guests ? ' · ' + s.guests + ' guests' : '') + ' · ' + s.from + ' → ' + s.to) + '">' + (s.from < nights[0] ? '← ' : '') + esc(s.who) + (s.to > last ? ' →' : '') + '</td>';
        i += k - 1;
      } else h += '<td class="' + (o.closed[nights[i]] ? 'shut' : 'f') + (nights[i] < todayISO() ? ' past' : '') + '" data-r="' + r.id + '" data-d="' + nights[i] + '"></td>';
    }
    h += '</tr>';
  }
  box.innerHTML = h + '</table></div><div class="legend"><span><i style="background:var(--accent)"></i>Booked</span><span><i style="background:var(--soft);border:1px solid var(--line)"></i>Free</span>' + (Object.keys(o.closed).length ? '<span><i style="background:#fde2e2"></i>Closed</span>' : '') + '</div></div>';
  $$('[data-k]', box).forEach((b) => b.onclick = () => occupancyView(t, box, +b.dataset.k === 0 ? todayISO() : plusDays(from, +b.dataset.k)));
  $('table', box).onclick = async (e) => {
    const c = e.target.closest('td'); if (!c) return;
    if (c.dataset.id) { const r = (await rows(t.id, true)).find((x) => String(x.id) === c.dataset.id); if (r) record(t, r, () => go(VIEW)); return; }
    if (c.dataset.r) drawer(t, null, () => go(VIEW), {[st.from.id]: c.dataset.d, [st.to.id]: plusDays(c.dataset.d, 1), [st.room.id]: +c.dataset.r});
  };
}

/// One record, to read first: its status, the order as a receipt, how to reach them, what else they have.
async function record(t, r, done) {
  $$('.drawer,.drawer-bg').forEach((x) => x.remove());
  const links = await linkMaps(t), sf = statusField(t), pf = phoneOf(t), calc = isOrders(t) ? orderCalc(t, r, links) : null;
  const imgF = t.fields.find((f) => f.type === 'image'), totalF = t.fields.find((f) => f.type === 'money' && /^(order_)?total$/.test(f.id)), label = labelOf(t);
  const bg = el('<div class="drawer-bg"></div>'), d = el('<div class="drawer"><div class="dh"><div class="dh-t"><small>' + esc(singular(t.title)) + ' · #' + r.id + '</small><h3>' + esc(nameOf(t, r)) + '</h3></div><span class="dh-pill">' + (sf ? pill(r[sf.id]) : '') + '</span><button class="iconbtn">' + icon('x') + '</button></div><div class="db"></div><div class="df"><button class="btn danger">' + icon('trash') + ' Delete</button><span class="sp"></span><button class="btn cancel">Close</button><button class="btn primary">' + icon('edit') + ' Edit</button></div></div>');
  document.body.append(bg, d);
  requestAnimationFrame(() => requestAnimationFrame(() => { bg.classList.add('show'); d.classList.add('show'); }));
  const close = () => { bg.classList.remove('show'); d.classList.remove('show'); setTimeout(() => { bg.remove(); d.remove(); }, 300); };
  bg.onclick = close; $('.dh .iconbtn', d).onclick = close; $('.df .cancel', d).onclick = close;
  const body = $('.db', d);
  let h = imgF && r[imgF.id] ? '<div class="rec-img"><img src="' + esc(r[imgF.id]) + '" alt=""></div>' : '';
  if (sf) h += '<div class="seg wide st-seg">' + sf.options.map((o) => '<button class="' + (o === r[sf.id] ? 'on ' : '') + 't-' + tone(o) + '" data-s="' + esc(o) + '">' + esc(o) + '</button>').join('') + '</div>';
  const contact = [];
  if (pf && r[pf.id]) contact.push('<a class="btn" href="tel:' + esc(String(r[pf.id]).replace(/\s/g, '')) + '">' + icon('phone') + ' ' + esc(r[pf.id]) + '</a>');
  for (const f of t.fields.filter((f) => f.type === 'email' && r[f.id])) contact.push('<a class="btn" href="mailto:' + esc(r[f.id]) + '">' + icon('mail') + ' ' + esc(r[f.id]) + '</a>');
  if (contact.length) h += '<div class="rec-contact">' + contact.join('') + '</div>';
  const skip = new Set([label, sf?.id, imgF?.id, totalF?.id, pf?.id, ...t.fields.filter((f) => f.type === 'email').map((f) => f.id), ...(calc ? t.fields.filter((f) => f.type === 'links' && f.qty).map((f) => f.id) : [])]);
  const dl = t.fields.filter((f) => !skip.has(f.id) && r[f.id] !== null && r[f.id] !== undefined && r[f.id] !== '' && (!f.when || Object.entries(f.when).every(([k, vals]) => vals.some((v) => String(v).toLowerCase() === String(r[k] ?? '').toLowerCase()))));
  h += '<dl class="rec-dl">' + dl.map((f) => '<div class="' + (f.type === 'longtext' ? 'full' : '') + '"><dt>' + esc(f.label) + (f.manager_only ? ' <span class="mo" title="Only you see this">' + icon('lock') + '</span>' : '') + '</dt><dd>' + (f.type === 'choice' && f.manager_only ? pill(r[f.id]) : esc(fmt(f, r[f.id], links))) + '</dd></div>').join('') + '</dl>';
  if (calc) {
    h += '<div class="receipt"><h4>' + icon('bag') + ' Order</h4>' + calc.lines.map((l) => '<div class="rl"><span><b>' + l.qty + '×</b> ' + esc(l.name) + '</span><span>' + esc(money(l.price * l.qty)) + '</span></div>').join('')
      + (calc.fee ? '<div class="rl sub"><span>Items</span><span>' + esc(money(calc.items)) + '</span></div><div class="rl sub"><span>Delivery</span><span>' + esc(money(calc.fee)) + '</span></div>' : '')
      + '<div class="rl tot"><span>Total</span><span>' + esc(money(calc.total)) + '</span></div></div>';
  }
  h += '<p class="rec-meta muted small">Added ' + esc(r.created_at || '') + ' (' + esc(ago(r.created_at)) + ')' + (r.via ? ' · from ' + esc(r.via === 'phone' ? 'a phone call' : r.via === 'website' ? 'the website' : 'you') : '') + '</p>';
  body.innerHTML = h;
  // Everything else from the same phone number.
  if (pf && digits9(r[pf.id])) {
    const others = [];
    for (const ot of addTables()) { const op = phoneOf(ot); if (!op) continue; for (const x of await rows(ot.id).catch(() => [])) if (!(ot.id === t.id && x.id === r.id) && digits9(x[op.id]) === digits9(r[pf.id])) others.push({t: ot, r: x}); }
    if (others.length) {
      const box = el('<div class="rec-others"><h4>Also from this number <span class="muted">(' + others.length + ')</span></h4></div>');
      for (const o of others.sort((a, b) => String(b.r.created_at).localeCompare(String(a.r.created_at))).slice(0, 12)) {
        const osf = statusField(o.t), odf = dateOf(o.t);
        const n = el('<button class="orow"><div><b>' + esc(nameOf(o.t, o.r)) + '</b><small>' + esc(singular(o.t.title)) + ' · ' + esc(odf && o.r[odf.id] ? dayLabel(o.r[odf.id]) : String(o.r.created_at || '').slice(0, 10)) + '</small></div>' + (osf ? pill(o.r[osf.id]) : '') + '</button>');
        n.onclick = () => record(o.t, o.r, done);
        box.append(n);
      }
      body.append(box);
    }
  }
  $$('.st-seg button', d).forEach((b) => b.onclick = async () => {
    await api('t/' + t.id + '/' + r.id, {method: 'PUT', body: JSON.stringify({[sf.id]: b.dataset.s})});
    r[sf.id] = b.dataset.s; delete cache[t.id];
    $$('.st-seg button', d).forEach((x) => x.classList.toggle('on', x === b)); $('.dh-pill', d).innerHTML = pill(b.dataset.s);
    toast(sf.label + ': ' + b.dataset.s); done(); badges().catch(() => {});
  });
  $('.df .primary', d).onclick = () => { close(); drawer(t, r, done); };
  $('.df .danger', d).onclick = async () => { if (!confirm('Delete “' + nameOf(t, r) + '”?')) return; await api('t/' + t.id + '/' + r.id, {method: 'DELETE'}); delete cache[t.id]; close(); toast('Deleted'); done(); };
}

/// Everyone who has ordered or booked, by phone number: how often, how much, when last.
async function customers(c) {
  const people = new Map(), d0 = todayISO();
  for (const t of addTables()) {
    const pf = phoneOf(t); if (!pf) continue;
    const links = await linkMaps(t), df = dateOf(t), sf = statusField(t), orders = isOrders(t);
    for (const r of await rows(t.id, true)) {
      const k = digits9(r[pf.id]); if (!k) continue;
      const p = people.get(k) || {key: k, phone: r[pf.id], name: '', visits: 0, spend: 0, last: '', next: '', added: '', recs: [], kinds: new Set()};
      const cancelled = sf && tone(r[sf.id]) === 'red';
      p.recs.push({t, r}); p.kinds.add(singular(t.title));
      if (!cancelled) { p.visits++; if (orders) p.spend += orderCalc(t, r, links)?.total || 0; }
      const made = String(r.created_at || '').slice(0, 10), on = df ? String(r[df.id] || '').slice(0, 10) : '';
      const seen = on && on <= d0 ? (on > made ? on : made) : made;
      if (seen > p.last) p.last = seen;
      if (on && on > d0 && !cancelled && (!p.next || on < p.next)) p.next = on;
      if (String(r.created_at) >= p.added) { p.added = String(r.created_at); p.name = nameOf(t, r); p.phone = r[pf.id]; }
      people.set(k, p);
    }
  }
  const all = [...people.values()];
  const back = all.filter((p) => p.visits > 1).length, spend = all.reduce((a, p) => a + p.spend, 0);
  c.innerHTML = '';
  c.append(el('<div class="head"><h1>Customers <span class="count">' + all.length + '</span></h1><p class="sub">Everyone who has ordered or booked, by their phone number. Only you see this.</p></div>'));
  c.append(el('<div class="kpis"><div class="kpi"><small>' + icon('users') + 'Customers</small><b>' + all.length + '</b><span>With a phone number</span></div><div class="kpi"><small>' + icon('heart') + 'Came back</small><b>' + back + '</b><span>' + (all.length ? Math.round(back / all.length * 100) : 0) + '% more than once</span></div>'
    + (spend ? '<div class="kpi"><small>' + icon('tag') + 'Average spend</small><b>' + esc(money(Math.round(spend / Math.max(1, all.filter((p) => p.spend).length) * 100) / 100)) + '</b><span>Per customer who ordered</span></div>' : '') + '</div>'));
  const bar = el('<div class="toolbar"><div class="search">' + icon('search') + '<input placeholder="Search by name or number"></div></div>'); c.append(bar);
  const box = el('<div class="card"><div class="tablewrap"></div></div>'); c.append(box);
  let q = '', sort = {k: 'last', dir: -1};
  const draw = () => {
    let list = all.filter((p) => !q || (p.name + ' ' + p.phone).toLowerCase().includes(q) || String(p.phone).replace(/\D/g, '').includes(q.replace(/\D/g, '') || '§'));
    list.sort((a, b) => { const x = a[sort.k], y = b[sort.k]; return (typeof x === 'number' ? x - y : String(x).localeCompare(String(y))) * sort.dir; });
    const tb = $('.tablewrap', box);
    if (!list.length) { tb.innerHTML = '<div class="empty" style="margin:20px;border:0">' + icon('users') + '<div>' + (all.length ? 'Nobody matches.' : 'Nobody yet: customers show here once they order or book.') + '</div></div>'; return; }
    const th = (k, l, cls = '') => '<th data-k="' + k + '" class="' + cls + (sort.k === k ? ' sorted' : '') + '">' + l + '<i class="sort-ic">' + (sort.k === k ? (sort.dir > 0 ? '▲' : '▼') : '') + '</i></th>';
    tb.innerHTML = '<table class="data sortable"><thead><tr>' + th('name', 'Name') + th('phone', 'Phone') + th('visits', 'Visits', 'num') + (spend ? th('spend', 'Spend', 'num') : '') + th('last', 'Last seen') + th('next', 'Next booking') + '<th>What</th></tr></thead><tbody></tbody></table>';
    $$('th[data-k]', tb).forEach((h) => h.onclick = () => { const k = h.dataset.k; sort = {k, dir: sort.k === k ? -sort.dir : (k === 'name' || k === 'phone' ? 1 : -1)}; draw(); });
    for (const p of list) {
      const tr = el('<tr><td><div class="cell-main"><div class="avatar" style="--h:' + hue(p.name) + '">' + esc((p.name.trim()[0] || '?').toUpperCase()) + '</div><span>' + esc(p.name) + '</span>' + (p.visits > 2 ? '<span class="tag acc">Regular</span>' : '') + '</div></td><td><a class="tel" href="tel:' + esc(String(p.phone).replace(/\s/g, '')) + '">' + esc(p.phone) + '</a></td><td class="num">' + p.visits + '</td>'
        + (spend ? '<td class="num">' + (p.spend ? esc(money(Math.round(p.spend * 100) / 100)) : '–') + '</td>' : '') + '<td>' + (p.last ? esc(dayLabel(p.last)) : '–') + '</td><td>' + (p.next ? esc(dayLabel(p.next)) : '<span class="muted">–</span>') + '</td><td>' + [...p.kinds].map((k) => '<span class="tag">' + esc(k) + '</span>').join(' ') + '</td></tr>');
      $('a.tel', tr).onclick = (e) => e.stopPropagation();
      tr.onclick = () => person(p);
      $('tbody', tb).append(tr);
    }
  };
  $('input', bar).oninput = (e) => { q = e.target.value.toLowerCase().trim(); draw(); };
  draw();
}

/// One customer: everything they have booked or ordered.
function person(p) {
  $$('.drawer,.drawer-bg').forEach((x) => x.remove());
  const bg = el('<div class="drawer-bg"></div>'), d = el('<div class="drawer"><div class="dh"><div class="dh-t"><small>Customer</small><h3>' + esc(p.name) + '</h3></div><button class="iconbtn">' + icon('x') + '</button></div><div class="db"><div class="rec-contact"><a class="btn" href="tel:' + esc(String(p.phone).replace(/\s/g, '')) + '">' + icon('phone') + ' ' + esc(p.phone) + '</a></div>'
    + '<dl class="rec-dl"><div><dt>Visits</dt><dd>' + p.visits + '</dd></div>' + (p.spend ? '<div><dt>Spend</dt><dd>' + esc(money(Math.round(p.spend * 100) / 100)) + '</dd></div>' : '') + '<div><dt>Last seen</dt><dd>' + esc(p.last ? dayLabel(p.last) : '–') + '</dd></div><div><dt>Next booking</dt><dd>' + esc(p.next ? dayLabel(p.next) : '–') + '</dd></div></dl><div class="rec-others"><h4>Everything from them</h4></div></div></div>');
  document.body.append(bg, d);
  requestAnimationFrame(() => requestAnimationFrame(() => { bg.classList.add('show'); d.classList.add('show'); }));
  const close = () => { bg.classList.remove('show'); d.classList.remove('show'); setTimeout(() => { bg.remove(); d.remove(); }, 300); };
  bg.onclick = close; $('.dh .iconbtn', d).onclick = close;
  for (const o of p.recs.sort((a, b) => String(b.r.created_at).localeCompare(String(a.r.created_at)))) {
    const osf = statusField(o.t), odf = dateOf(o.t);
    const n = el('<button class="orow"><div><b>' + esc(singular(o.t.title)) + '</b><small>' + esc(odf && o.r[odf.id] ? dayLabel(o.r[odf.id]) : String(o.r.created_at || '').slice(0, 10)) + '</small></div>' + (osf ? pill(o.r[osf.id]) : '') + '</button>');
    n.onclick = () => record(o.t, o.r, () => go(VIEW));
    $('.rec-others', d).append(n);
  }
}

/// Add or edit one record in a side panel.
async function drawer(t, r, done, prefill = {}) {
  const bg = el('<div class="drawer-bg"></div>'), d = el('<div class="drawer"><div class="dh"><h3>' + (r ? esc(nameOf(t, r)) : 'Add to ' + esc(t.title.toLowerCase())) + '</h3><button class="iconbtn">' + icon('x') + '</button></div><div class="db"><div class="fgrid"></div><div class="msg"></div></div><div class="df">' + (r ? '<button class="btn danger">' + icon('trash') + ' Delete</button>' : '') + '<span class="sp"></span><button class="btn cancel">Cancel</button><button class="btn primary">Save</button></div></div>');
  document.body.append(bg, d);
  requestAnimationFrame(() => requestAnimationFrame(() => { bg.classList.add('show'); d.classList.add('show'); }));
  const close = () => { bg.classList.remove('show'); d.classList.remove('show'); setTimeout(() => { bg.remove(); d.remove(); }, 300); };
  bg.onclick = close; $('.dh .iconbtn', d).onclick = close; $('.df .cancel', d).onclick = close;
  const inputs = [];
  for (const f of t.fields) { const i = await fieldInput(f, r ? r[f.id] : prefill[f.id], {full: f.id === labelOf(t), optional: !f.required}); $('.fgrid', d).append(i.node); inputs.push(i); }
  $('.df .primary', d).onclick = async () => {
    const b = {}; for (const i of inputs) b[i.f.id] = i.get();
    try { await api('t/' + t.id + (r ? '/' + r.id : ''), {method: r ? 'PUT' : 'POST', body: JSON.stringify(b)}); delete cache[t.id]; close(); toast('Saved'); done(); }
    catch (e) { $('.msg', d).innerHTML = '<div class="err">' + esc(e.message) + '</div>'; }
  };
  const del = $('.df .danger', d);
  if (del) del.onclick = async () => { if (!confirm('Delete “' + nameOf(t, r) + '”?')) return; await api('t/' + t.id + '/' + r.id, {method: 'DELETE'}); delete cache[t.id]; close(); toast('Deleted'); done(); };
}

/// Add records from a photo of a menu, price list…: the AI reads it, you tick what to keep.
function importPhoto(t, done) {
  const input = el('<input type="file" accept="image/*" hidden>');
  document.body.append(input);
  input.onchange = async () => {
    const file = input.files[0]; input.remove(); if (!file) return;
    const bg = el('<div class="drawer-bg"></div>'), d = el('<div class="drawer"><div class="dh"><h3>Add ' + esc(t.title.toLowerCase()) + ' from a photo</h3><button class="iconbtn">' + icon('x') + '</button></div><div class="db"><div class="reading"><div class="spinner"></div><b>Reading your picture…</b><div class="hint">Your AI is reading every item. This can take a minute.</div></div></div><div class="df"><span class="sp"></span><button class="btn cancel">Cancel</button><button class="btn primary" disabled>Add</button></div></div>');
    document.body.append(bg, d);
    requestAnimationFrame(() => requestAnimationFrame(() => { bg.classList.add('show'); d.classList.add('show'); }));
    let closed = false;
    const close = () => { closed = true; bg.classList.remove('show'); d.classList.remove('show'); setTimeout(() => { bg.remove(); d.remove(); }, 300); };
    bg.onclick = close; $('.dh .iconbtn', d).onclick = close; $('.df .cancel', d).onclick = close;
    let found;
    try {
      const blob = await shrink(file);
      const r = await fetch('/api/_import/' + t.id, {method: 'POST', body: blob, headers: {'Content-Type': blob.type || 'image/jpeg', 'X-Key': KEY}});
      const j = await r.json().catch(() => ({}));
      if (!r.ok) throw new Error(j.error || 'Could not read the picture');
      found = j.rows || [];
    } catch (e) { if (!closed) $('.db', d).innerHTML = '<div class="err">' + esc(e.message) + '</div>'; return; }
    if (closed) return;
    if (!found.length) { $('.db', d).innerHTML = '<div class="empty">Nothing readable was found. Try a sharper, straighter photo.</div>'; return; }
    const label = labelOf(t), others = t.fields.filter((f) => f.id !== label && found.some((r) => r[f.id] !== undefined));
    const list = el('<div><p class="muted" style="margin-bottom:8px">Found ' + found.length + '. Untick anything wrong — you can edit details and add photos afterwards.</p></div>');
    found.forEach((r, i) => list.append(el('<label class="imp-row"><input type="checkbox" checked data-i="' + i + '"><div><div class="nm">' + esc(r[label] ?? '(no name)') + '</div><div class="kv">' + others.map((f) => r[f.id] === undefined ? '' : esc(f.label) + ': ' + esc(f.type === 'money' ? money(r[f.id]) : r[f.id])).filter(Boolean).join(' · ') + '</div></div></label>')));
    $('.db', d).innerHTML = ''; $('.db', d).append(list);
    const add = $('.df .primary', d);
    const count = () => { const n = $$('input:checked', list).length; add.disabled = !n; add.textContent = 'Add ' + n; };
    list.onchange = count; count();
    add.onclick = async () => {
      add.disabled = true;
      let ok = 0, bad = 0;
      for (const c of $$('input:checked', list)) { try { await api('t/' + t.id, {method: 'POST', body: JSON.stringify(found[Number(c.dataset.i)])}); ok++; } catch (_) { bad++; } }
      delete cache[t.id]; close(); toast('Added ' + ok + (bad ? ' (' + bad + ' could not be added)' : '')); done();
    };
  };
  input.click();
}

/// Website: name, details, pictures, style, colour and every text on the pages.
async function website(c) {
  const s = {...(SPEC.site || {})};
  let theme = SPEC.theme || '', name = SPEC.name;
  const pages = {};
  c.innerHTML = '';
  c.append(el('<div class="head"><h1>Design & texts</h1><a class="btn sm" href="/" target="_blank">' + icon('ext') + ' View website</a><p class="sub">Everything your customers see. Changes go live as soon as you save.</p></div>'));
  const txt = (key, label, multi, hint) => { const f = el('<div class="field' + (multi ? ' full' : '') + '"><label class="lbl">' + esc(label) + '</label>' + (multi ? '<textarea style="min-height:80px"></textarea>' : '<input>') + (hint ? '<div class="hint">' + esc(hint) + '</div>' : '') + '</div>'); const i = $('input,textarea', f); i.value = key === 'name' ? name : (s[key] || ''); i.oninput = () => key === 'name' ? (name = i.value) : (s[key] = i.value); return f; };
  const imgField = (key, label, hint) => { const f = el('<div class="field full"><label class="lbl">' + esc(label) + '</label></div>'); f.append(imageInput(s[key], (v) => s[key] = v)); if (hint) f.append(el('<div class="hint">' + esc(hint) + '</div>')); return f; };
  const card = (title) => { const k = el('<div class="card" style="margin-bottom:22px"><div class="card-h"><h3>' + esc(title) + '</h3></div><div class="card-b"><div class="fgrid"></div></div></div>'); c.append(k); return $('.fgrid', k); };

  card('Your business').append(txt('name', 'Name'), txt('tagline', 'Tagline', false, 'One short line, e.g. “Wood-fired pizza since 1998”.'), txt('about', 'About you', true, 'A few sentences, shown in the footer.'),
    txt('currency', 'Currency', false, 'e.g. £, €, $ or AED'),
    ...(SPEC.tables.some((t) => isOrders(t) && t.fields.some((f) => f.type === 'choice' && f.options.some((o) => /^deliver/i.test(o)))) ? [txt('delivery_fee', 'Delivery fee', false, 'Added to every delivery order, e.g. 2.50. Empty = free delivery.'), txt('min_order', 'Minimum order for delivery', false, 'Delivery orders below this are refused, e.g. 15. Empty = no minimum.')] : []),
    ...(SPEC.tables.some((t) => shapeOf(t)) ? [txt('booking_minutes', 'How long a booking lasts (minutes)', false, 'A table (or stylist, room…) stays booked this long. Default 120.')] : []), txt('footer', 'Footer note', false, 'e.g. “Free parking at the back”'), imgField('logo', 'Logo', 'A PNG with a clear background looks best.'), imgField('hero', 'Cover picture', 'The big photo at the top of your home page.'));
  card('Contact').append(txt('address', 'Address', true), txt('phone', 'Phone'), txt('email', 'Email'));

  const look = el('<div class="card" style="margin-bottom:22px"><div class="card-h"><h3>Style</h3></div><div class="card-b"><div class="styles"></div><div class="colorrow"><label class="lbl" style="margin:0">Main colour</label><input type="color"><button class="btn sm">Use the style’s colour</button><span class="hint" style="margin:0">Buttons, links and highlights.</span></div></div></div>');
  const drawStyles = () => {
    const box = $('.styles', look); box.innerHTML = '';
    for (const st of window.STYLES) {
      const on = (s.style || 'modern') === st.id;
      const b = el('<button type="button" class="stylecard' + (on ? ' on' : '') + '"><div class="sw" style="background:' + st.bg + ';color:' + st.ink + '"><b style="font-family:' + esc(st.head) + '">Aa</b><i style="background:' + (on && theme ? theme : st.accent) + '"></i></div><div class="tx"><strong>' + esc(st.name) + '</strong><span>' + esc(st.about) + '</span><span><b>Good for:</b> ' + esc(st.goodFor) + '</span></div></button>');
      b.onclick = () => { s.style = st.id; drawStyles(); };
      box.append(b);
    }
    $('input[type=color]', look).value = theme || window.STYLES.find((x) => x.id === (s.style || 'modern')).accent;
  };
  $('input[type=color]', look).oninput = (e) => { theme = e.target.value; drawStyles(); };
  $('.colorrow .btn', look).onclick = () => { theme = ''; drawStyles(); };
  drawStyles();
  c.append(look);

  c.append(el('<h2 class="sectitle">Page texts</h2>'));
  for (const p of SPEC.pages.filter((p) => !p.manager)) {
    const pe = pages[p.id] = {blocks: {}};
    const box = el('<div class="pagebox"><h4>' + icon('file') + esc(p.title) + '</h4><div class="field"><label class="lbl">Name in the menu</label><input></div></div>');
    $('input', box).value = p.title; $('input', box).oninput = (e) => pe.title = e.target.value;
    p.blocks.forEach((b, i) => {
      const e = pe.blocks[i] = {};
      if (b.type === 'hero') {
        const k = el('<div class="blk"><div class="fgrid"><div class="field full"><label class="lbl">Big heading</label><input data-k="title"></div><div class="field full"><label class="lbl">Text under it</label><textarea data-k="text" style="min-height:70px"></textarea></div><div class="field"><label class="lbl">Button text</label><input data-k="button"></div></div></div>');
        $$('[data-k]', k).forEach((x) => { x.value = b[x.dataset.k] || ''; x.oninput = () => e[x.dataset.k] = x.value; });
        const pf = el('<div class="field full"><label class="lbl">Picture behind it</label></div>'); pf.append(imageInput(b.image, (v) => e.image = v)); $('.fgrid', k).append(pf);
        box.append(k);
      } else if (b.type === 'text') {
        const k = el('<div class="blk"><div class="field"><label class="lbl">Text</label><textarea></textarea><div class="hint">Start a line with # for a heading, or - for a list.</div></div></div>');
        $('textarea', k).value = b.text; $('textarea', k).oninput = (x) => e.text = x.target.value;
        box.append(k);
      } else if (b.type === 'features' || b.type === 'contact') {
        const k = el('<div class="blk"><div class="fgrid"><div class="field full"><label class="lbl">' + (b.type === 'features' ? 'Heading above the highlights' : 'Heading above your contact details') + '</label><input data-k="title"></div><div class="field full"><label class="lbl">' + (b.type === 'features' ? 'Highlights' : 'A line under it (optional)') + '</label><textarea data-k="text" style="min-height:90px"></textarea><div class="hint">' + (b.type === 'features' ? 'One per line, as “Title: what it means”. Each gets its own card and icon.' : 'Address, phone, email and hours come from Your business and Contact above.') + '</div></div></div></div>');
        $$('[data-k]', k).forEach((x) => { x.value = b[x.dataset.k] || ''; x.oninput = () => e[x.dataset.k] = x.value; });
        box.append(k);
      } else if (b.type === 'gallery') {
        const k = el('<div class="blk"><div class="field"><label class="lbl">Heading above the photos</label><input></div><label class="lbl">Photos</label><div class="gal-edit"></div>' + (b.table ? '<div class="hint">The photos of your ' + esc((table(b.table)?.title || '').toLowerCase()) + ' show here too.</div>' : '') + '</div>');
        $('input', k).value = b.title || ''; $('input', k).oninput = (x) => e.title = x.target.value;
        let imgs = [...(b.images || [])];
        const gal = $('.gal-edit', k);
        const drawG = () => {
          gal.innerHTML = '';
          imgs.forEach((u, j) => { const it = el('<div class="gal-th"><img src="' + esc(u) + '" alt=""><button type="button" class="iconbtn" title="Remove">' + icon('x') + '</button></div>'); $('button', it).onclick = () => { imgs.splice(j, 1); e.images = [...imgs]; drawG(); }; gal.append(it); });
          const add = imageInput('', (v) => { if (v) { imgs.push(v); e.images = [...imgs]; drawG(); } }); add.classList.add('gal-add'); gal.append(add);
        };
        drawG();
        box.append(k);
      } else {
        const what = b.type === 'form' ? 'form' : b.type === 'testimonials' ? 'reviews' : b.type === 'stay' ? 'room finder' : b.type === 'availability' ? 'free times' : b.layout === 'menu' ? 'menu' : b.layout === 'timetable' ? 'timetable' : 'list';
        const k = el('<div class="blk"><div class="field"><label class="lbl">Heading above the ' + what + ' of ' + esc((table(b.table)?.title || '').toLowerCase()) + '</label><input></div></div>');
        $('input', k).value = b.title || ''; $('input', k).oninput = (x) => e.title = x.target.value;
        box.append(k);
      }
    });
    c.append(box);
  }
  const save = el('<div class="savebar"><button class="btn primary lg">' + icon('check') + ' Save changes</button></div>');
  $('button', save).onclick = async () => {
    try {
      await api('_site', {method: 'PUT', body: JSON.stringify({name, site: s, theme, pages})});
      toast('Saved — your website is updated');
      setTimeout(() => location.reload(), 800);
    } catch (e) { toast(e.message); }
  };
  c.append(save);
}

async function start() {
  // LocalAILine opens /manage#pin=… to sign you in straight away.
  if (location.hash.startsWith('#pin=')) {
    const h = new URLSearchParams(location.hash.slice(1));
    KEY = h.get('pin') || ''; localStorage.setItem(KEY_NAME, KEY);
    history.replaceState(null, '', location.pathname + (h.get('v') ? '#' + h.get('v') : ''));
  }
  try { SPEC = await api('_spec'); } catch (e) { document.getElementById('app').innerHTML = '<div class="wrap" style="padding:60px 24px"><div class="err">' + esc(e.message) + '</div></div>'; return; }
  if (MANAGER) return SPEC.manager ? admin() : login();
  if (!SPEC.pages.some((p) => !p.manager)) { location.replace('/manage'); return; }
  await site();
}
start();
''';
