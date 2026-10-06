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
    return {open: o, close: c, isOpen: open, table: t, times};
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
        const priceF = firstOf(t, 'money'), imgF = firstOf(t, 'image');
        const box = add(el('<div></div>')), adder = el('<select style="margin-top:14px"><option value="">+ Add ' + esc(t.title.toLowerCase()) + '…</option>' + list.map((r) => '<option value="' + r.id + '">' + esc(nameOf(t, r)) + (priceF ? ' — ' + money(r[priceF.id]) : '') + '</option>').join('') + '</select>');
        const draw = () => {
          const items = Object.entries(sel).filter(([, q]) => q > 0);
          let h = items.length ? '' : '<div class="cart-empty">' + (ctx.hasList ? 'Tap “Add” on anything above, or choose here.' : 'Nothing chosen yet.') + '</div>', sum = 0;
          for (const [id, q] of items) {
            const r = list.find((x) => String(x.id) === id); if (!r) continue;
            const p = priceF ? Number(r[priceF.id] || 0) : 0; sum += p * q;
            h += '<div class="cart-line"><div class="thumb">' + media(imgF && r[imgF.id], nameOf(t, r), 'sm') + '</div><div class="nm">' + esc(nameOf(t, r)) + (priceF ? '<small>' + money(p) + '</small>' : '') + '</div><div class="stepper"><button type="button" data-d="-1" data-id="' + id + '">' + icon('minus') + '</button><b>' + q + '</b><button type="button" data-d="1" data-id="' + id + '">' + icon('plus') + '</button></div></div>';
          }
          if (priceF && items.length) h += '<div class="total"><span>Total</span><span class="price">' + money(sum) + '</span></div>';
          box.innerHTML = h; box.append(adder);
          ctx.onChange && ctx.onChange(items.reduce((a, [, q]) => a + q, 0), sum);
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
  const load = async () => { plan = await api('_plan/' + t.id + '?date=' + day.value); if (at != null && (at <= nowMin())) at = null; drawSlots(); drawRes(); drawDay(); fill(); };
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
  const n = el('<header class="topnav"><div class="wrap"><a class="brand" href="/">' + monogram() + '<span>' + esc(SPEC.name) + '</span></a>'
    + '<nav class="links">' + pages.map((p) => '<a href="/p/' + p.id + '"' + (p.id === current ? ' class="on"' : '') + '>' + esc(p.title) + '</a>').join('') + '</nav>'
    + (formPage && formPage.id !== current ? '<a class="btn primary sm cta" href="/p/' + formPage.id + '">' + esc(formPage.title) + '</a>' : '')
    + '<button class="iconbtn burger" aria-label="Menu">' + icon('menu') + '</button></div></header>');
  $('.burger', n).onclick = () => $('.links', n).classList.toggle('open');
  return n;
}

async function footer(pages) {
  const s = SPEC.site || {}, h = await hours();
  const col = (title, body) => body ? '<div><h4>' + esc(title) + '</h4>' + body + '</div>' : '';
  return el('<footer class="footer"><div class="wrap cols">'
    + '<div><a class="brand" href="/">' + monogram() + '<span>' + esc(SPEC.name) + '</span></a>' + (s.about || s.tagline ? '<p class="about">' + esc(s.about || s.tagline) + '</p>' : '') + '</div>'
    + col('Visit us', (s.address ? '<p>' + esc(s.address) + '</p>' : '') + (s.phone ? '<a href="tel:' + esc(s.phone.replace(/\s/g, '')) + '">' + esc(s.phone) + '</a>' : '') + (s.email ? '<a href="mailto:' + esc(s.email) + '">' + esc(s.email) + '</a>' : ''))
    + col('Hours', h ? '<p>' + esc(h.open) + ' – ' + esc(h.close) + '</p><p style="color:var(--muted)">' + (h.isOpen ? 'Open now' : 'Closed now') + '</p>' : '')
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
  const label = labelOf(t), imgF = firstOf(t, 'image'), priceF = fields.find((f) => f.type === 'money'), descF = fields.find((f) => f.type === 'longtext'), catF = fields.find((f) => f.type === 'choice');
  const pick = page.blocks.some((o) => o.type === 'form' && table(o.table)?.fields.some((f) => f.type === 'links' && f.qty && f.link === t.id));
  const all = await rows(t.id, true), links = await linkMaps(t);
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
      const tags = fields.filter((f) => ![label, priceF?.id, descF?.id].includes(f.id) && f.type !== 'image' && r[f.id] !== undefined && r[f.id] !== '' && r[f.id] !== null && r[f.id] !== false)
        .slice(0, 4).map((f) => '<span class="tag' + (f === catF ? ' acc' : '') + '">' + (f.type === 'yesno' ? icon('check') + ' ' + esc(f.label) : (f.type === 'choice' ? '' : esc(f.label) + ': ') + esc(fmt(f, r[f.id], links))) + '</span>').join('');
      const q2 = state.sel[t.id]?.[r.id] || 0;
      const card = el('<article class="item" style="animation-delay:' + Math.min(i, 12) * 40 + 'ms">' + (imgF ? '<div class="media">' + media(r[imgF.id], nameOf(t, r)) + '</div>' : '')
        + '<div class="body"><div class="top"><h3>' + esc(nameOf(t, r)) + '</h3>' + (priceF && r[priceF.id] !== undefined && r[priceF.id] !== null ? '<span class="price">' + money(r[priceF.id]) + '</span>' : '') + '</div>'
        + (descF && r[descF.id] ? '<p class="desc">' + esc(r[descF.id]) + '</p>' : '') + (tags ? '<div class="meta">' + tags + '</div>' : '')
        + (pick ? '<div class="foot"><span class="qtybadge">' + (q2 ? q2 + ' in your ' + esc(state.formName) : '') + '</span><button class="btn primary sm">' + icon('plus') + ' Add</button></div>' : '') + '</div></article>');
      if (pick) $('.foot button', card).onclick = () => state.add(t.id, r.id);
      if (SPEC.manager) { const e = el('<button class="edit-btn" title="Edit">✎</button>'); e.onclick = () => drawer(t, r, () => site()); card.prepend(e); }
      grid.append(card);
    });
  };
  state.redrawLists.push(() => { grid.classList.add('settled'); draw(); });
  draw();
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
  let aside = null, fc = null, inView = false;
  if (cartF) {
    state.formName = (b.title || t.title).toLowerCase().replace(/^(place |make |book )?(your |an? )?/, '').trim() || 'order';
    aside = el('<aside class="panel aside"><h3>' + esc(b.title || 'Your ' + state.formName) + '</h3><div class="cartbox"></div></aside>');
    wrap.append(aside);
    fc = el('<a class="btn primary lg floatcart" href="#form-' + t.id + '">' + icon('bag') + ' <span></span></a>');
    document.body.append(fc);
  }
  for (const f of fields) {
    if (f === cartF) {
      const ctx = {sel: state.sel[cartF.link] = state.sel[cartF.link] || {}, hasList, onChange: (count, sum) => {
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
  const values = () => { const body = {}; for (const i of inputs) body[i.f.id] = i.get(); return body; };
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
    } catch (e) { nodes[i] = fail(e); }
  }
  nodes.filter(Boolean).forEach((n) => main.append(n));
  app.append(await footer(pages));
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
const statusField = (t) => t.fields.find((f) => f.type === 'choice' && f.manager_only) || t.fields.find((f) => f.type === 'choice' && /status|state|stage/.test(f.id));
function beep() { try { const a = new AudioContext(), o = a.createOscillator(), g = a.createGain(); o.connect(g); g.connect(a.destination); o.frequency.value = 880; g.gain.setValueAtTime(.12, a.currentTime); g.gain.exponentialRampToValueAtTime(.001, a.currentTime + .5); o.start(); o.stop(a.currentTime + .5); } catch (_) {} }

async function admin() {
  const app = document.getElementById('app');
  app.innerHTML = '';
  const shell = el('<div class="admin"><aside class="side"><a class="brand" href="/manage">' + monogram() + '<span>' + esc(SPEC.name) + '</span></a>'
    + '<button class="nav-btn" data-v="overview">' + icon('home') + 'Overview</button><div class="grp">Your data</div>'
    + SPEC.tables.map((t) => '<button class="nav-btn" data-v="t:' + t.id + '">' + icon(t.kind === 'single' ? 'file' : (t.access.includes('add') ? 'bell' : (t.fields.some((f) => f.type === 'image') ? 'image' : 'list'))) + esc(t.title) + '</button>').join('')
    + '<div class="grp">Website</div><button class="nav-btn" data-v="website">' + icon('palette') + 'Design & texts</button>'
    + '<div class="spacer"></div><a class="nav-btn" href="/" target="_blank">' + icon('ext') + 'View website</a><button class="nav-btn" data-v="logout">' + icon('out') + 'Sign out</button></aside><section class="content"></section></div>');
  app.append(shell);
  $$('.nav-btn[data-v]', shell).forEach((b) => b.onclick = () => go(b.dataset.v));
  window.onhashchange = () => { const v = decodeURIComponent(location.hash.slice(1)); if (v && v !== VIEW) go(v); };
  go(decodeURIComponent(location.hash.slice(1)) || 'overview');
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
    else await manageTable(table(v.slice(2)), c);
  } catch (e) { c.innerHTML = '<div class="err">' + esc(e.message) + '</div>'; }
}

async function overview(c) {
  const hr = new Date().getHours();
  const hello = hr < 12 ? 'Good morning' : hr < 18 ? 'Good afternoon' : 'Good evening';
  const counts = {}; for (const t of SPEC.tables) if (t.kind !== 'single') counts[t.id] = (await rows(t.id, true)).length;
  c.innerHTML = '';
  c.append(el('<div class="head"><h1>' + hello + '</h1><a class="btn sm" href="/" target="_blank">' + icon('ext') + ' View website</a><p class="sub">Here’s what’s happening at ' + esc(SPEC.name) + '.</p></div>'));
  const st = el('<div class="stats"></div>');
  for (const t of SPEC.tables.filter((t) => t.kind !== 'single')) { const n = el('<div class="stat"><small>' + icon(t.access.includes('add') ? 'bell' : 'list') + esc(t.title) + '</small><b>' + counts[t.id] + '</b></div>'); n.onclick = () => go('t:' + t.id); st.append(n); }
  c.append(st);
  for (const t of addTables()) {
    const box = el('<div class="card" style="margin-bottom:22px"><div class="card-h"><h3>Latest ' + esc(t.title.toLowerCase()) + '</h3><button class="btn sm">See all</button></div><div class="tablewrap"></div></div>');
    $('button', box).onclick = () => go('t:' + t.id);
    c.append(box);
    await dataTable(t, $('.tablewrap', box), {limit: 8, fresh: false});
  }
  // New orders and bookings show up by themselves, with a soft ping.
  for (const t of addTables()) SEEN[t.id] = SEEN[t.id] ?? counts[t.id];
  TIMER = setInterval(async () => {
    if (VIEW !== 'overview') return;
    let grew = false;
    for (const t of addTables()) { const n = (await rows(t.id, true)).length; if (n > (SEEN[t.id] || 0)) grew = true; SEEN[t.id] = n; }
    if (grew) { beep(); toast('Something new just came in'); go('overview'); }
  }, 15000);
}

/// A table of records: picture + name, a few columns, and a status you can change in place.
async function dataTable(t, box, {limit = 0, q = '', filter = '', fresh = true} = {}) {
  let all = [...await rows(t.id, fresh)].reverse();
  const links = await linkMaps(t), sf = statusField(t), imgF = t.fields.find((f) => f.type === 'image');
  const label = labelOf(t);
  if (q) all = all.filter((r) => JSON.stringify(r).toLowerCase().includes(q) || t.fields.some((f) => f.link && fmt(f, r[f.id], links).toLowerCase().includes(q)));
  if (filter && sf) all = all.filter((r) => r[sf.id] === filter);
  if (limit) all = all.slice(0, limit);
  const cols = t.fields.filter((f) => f.id !== label && f !== sf && f.type !== 'image' && f.type !== 'longtext').slice(0, 4);
  if (!all.length) { box.innerHTML = '<div class="empty" style="margin:20px;border:0">' + icon(q ? 'search' : 'list') + '<div>' + (q || filter ? 'Nothing matches.' : 'Nothing here yet.') + '</div></div>'; return; }
  box.innerHTML = '<table class="data"><thead><tr><th>' + esc(t.fields.find((f) => f.id === label)?.label || 'Name') + '</th>' + cols.map((f) => '<th>' + esc(f.label) + '</th>').join('') + (sf ? '<th>' + esc(sf.label) + '</th>' : '') + '<th>Added · from</th></tr></thead><tbody></tbody></table>';
  const tb = $('tbody', box);
  for (const r of all) {
    const fresh10 = Date.now() - new Date(String(r.created_at).replace(' ', 'T')).getTime() < 600000;
    const tr = el('<tr' + (fresh10 && t.access.includes('add') ? ' class="new"' : '') + '><td><div class="cell-main">' + (imgF ? '<div class="thumb-sm">' + media(r[imgF.id], nameOf(t, r), 'sm') + '</div>' : '') + esc(nameOf(t, r)) + '</div></td>'
      + cols.map((f) => '<td>' + esc(fmt(f, r[f.id], links)) + '</td>').join('')
      + (sf ? '<td><select class="status s' + Math.max(0, sf.options.indexOf(r[sf.id])) % 5 + '">' + sf.options.map((o) => '<option' + (o === r[sf.id] ? ' selected' : '') + '>' + esc(o) + '</option>').join('') + '</select></td>' : '')
      + '<td class="muted" style="white-space:nowrap">' + esc(r.created_at || '') + (r.via === 'phone' ? ' <span class="tag acc">' + icon('phone') + ' Phone</span>' : (r.via === 'website' ? ' <span class="tag">Website</span>' : '')) + '</td></tr>');
    if (sf) { const s = $('select', tr); s.onclick = (e) => e.stopPropagation(); s.onchange = async () => { await api('t/' + t.id + '/' + r.id, {method: 'PUT', body: JSON.stringify({[sf.id]: s.value})}); s.className = 'status s' + sf.options.indexOf(s.value) % 5; delete cache[t.id]; toast(sf.label + ': ' + s.value); }; }
    tr.onclick = () => drawer(t, r, () => go(VIEW));
    tb.append(tr);
  }
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
  const sf = statusField(t);
  const head = el('<div class="head"><h1>' + esc(t.title) + '</h1><button class="btn" data-a="photo">' + icon('image') + ' Add from a photo</button><button class="btn primary" data-a="add">' + icon('plus') + ' Add</button><p class="sub">' + esc(t.purpose || '') + '</p></div>');
  $('[data-a=add]', head).onclick = () => drawer(t, null, () => go(VIEW));
  $('[data-a=photo]', head).onclick = () => importPhoto(t, () => go(VIEW));
  c.append(head);
  const bar = el('<div class="toolbar"><div class="search">' + icon('search') + '<input placeholder="Search"></div></div>');
  let q = '', filter = '';
  if (sf) { const chips = el('<div class="chips"></div>'); for (const o of ['', ...sf.options]) { const b = el('<button class="pill-opt' + (o ? '' : ' on') + '">' + esc(o || 'All') + '</button>'); b.onclick = () => { filter = o; $$('.pill-opt', chips).forEach((x) => x.classList.toggle('on', x === b)); draw(); }; chips.append(b); } bar.append(chips); }
  c.append(bar);
  const box = el('<div class="card"><div class="tablewrap"></div></div>'); c.append(box);
  const draw = () => dataTable(t, $('.tablewrap', box), {q, filter, fresh: false});
  $('input', bar).oninput = (e) => { q = e.target.value.toLowerCase(); draw(); };
  // Bookings of tables, stylists, rooms…: a day plan as well as the list.
  if (shapeOf(t)) {
    const plan = el('<div class="card" style="margin-bottom:22px"></div>');
    c.insertBefore(plan, bar);
    await dayPlanView(t, plan);
  }
  await rows(t.id, true); await draw();
}

/// The manager's day: every table (stylist, room…) across the opening hours, bookings by name.
async function dayPlanView(t, box, date) {
  const sh = shapeOf(t);
  date = date || todayISO();
  const plan = await api('_plan/' + t.id + '?date=' + date);
  const ss = slotsOf(plan);
  const shift = (d) => { const x = new Date(date + 'T12:00'); x.setDate(x.getDate() + d); return x.toISOString().slice(0, 10); };
  const label = new Date(date + 'T12:00').toLocaleDateString(undefined, {weekday: 'long', day: 'numeric', month: 'long'});
  const count = new Set(plan.busy.map((h) => h.id)).size;
  let h = '<div class="card-h"><h3>Day plan · ' + esc(label) + '</h3><div class="daynav"><button class="btn sm" data-d="-1">←</button><input type="date" style="width:auto" value="' + date + '"><button class="btn sm" data-d="1">→</button><button class="btn sm" data-d="0">Today</button></div></div>'
    + '<div class="card-b"><div class="muted" style="margin-bottom:8px">' + count + ' booking' + (count === 1 ? '' : 's') + ' · each holds a ' + esc(sh.res.title.toLowerCase().replace(/s$/, '')) + ' for ' + plan.minutes + ' minutes (change it in Design & texts). Click an empty slot to add a booking.</div><div class="tl"><table><tr><th class="rn">' + esc(sh.res.title) + '</th>' + ss.map((m) => '<th>' + toHHMM(m) + '</th>').join('') + '</tr>';
  for (const r of plan.resources) {
    h += '<tr><th class="rn">' + esc(r.name) + (r.seats ? ' <span style="color:var(--muted);font-weight:400">· ' + r.seats + '</span>' : '') + '</th>';
    for (let i = 0; i < ss.length; i++) {
      const b = plan.busy.find((x) => x.resource === r.id && ss[i] >= toMin(x.from) && ss[i] < toMin(x.from) + plan.minutes);
      if (b) {
        let k = 1; while (i + k < ss.length && ss[i + k] < toMin(b.from) + plan.minutes) k++;
        h += '<td class="b" colspan="' + k + '" data-id="' + b.id + '" title="' + esc(b.who + (b.guests ? ' · ' + b.guests + ' people' : '') + ' · ' + b.from + '–' + b.to) + '">' + esc(b.who) + (b.guests ? ' · ' + b.guests : '') + ' <span style="opacity:.75;font-weight:500">' + esc(b.from) + '</span></td>';
        i += k - 1;
      } else h += '<td class="f" data-r="' + r.id + '" data-m="' + ss[i] + '"></td>';
    }
    h += '</tr>';
  }
  box.innerHTML = h + '</table></div></div>';
  $$('[data-d]', box).forEach((b) => b.onclick = () => dayPlanView(t, box, +b.dataset.d === 0 ? todayISO() : shift(+b.dataset.d)));
  $('input[type=date]', box).onchange = (e) => dayPlanView(t, box, e.target.value);
  $('table', box).onclick = async (e) => {
    const c = e.target.closest('td'); if (!c) return;
    if (c.dataset.id) { const r = (await rows(t.id, true)).find((x) => String(x.id) === c.dataset.id); if (r) drawer(t, r, () => go(VIEW)); return; }
    if (c.dataset.r) drawer(t, null, () => go(VIEW), {[sh.date.id]: date, [sh.time.id]: toHHMM(+c.dataset.m), [sh.link.id]: +c.dataset.r});
  };
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
    txt('currency', 'Currency', false, 'e.g. £, €, $ or AED'), ...(SPEC.tables.some((t) => shapeOf(t)) ? [txt('booking_minutes', 'How long a booking lasts (minutes)', false, 'A table (or stylist, room…) stays booked this long. Default 120.')] : []), txt('footer', 'Footer note', false, 'e.g. “Free parking at the back”'), imgField('logo', 'Logo', 'A PNG with a clear background looks best.'), imgField('hero', 'Cover picture', 'The big photo at the top of your home page.'));
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
      } else {
        const k = el('<div class="blk"><div class="field"><label class="lbl">Heading above the ' + (b.type === 'form' ? 'form' : 'list') + ' of ' + esc((table(b.table)?.title || '').toLowerCase()) + '</label><input></div></div>');
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
