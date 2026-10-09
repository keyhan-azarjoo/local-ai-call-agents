/// Ready-made looks for the websites of user-built apps. Each one is a full design:
/// colours, fonts, corner roundness. The user can still pick their own main colour.
class SiteStyle {
  const SiteStyle(this.id, this.name, this.about, this.goodFor,
      {required this.bg, required this.surface, required this.ink, required this.muted, required this.line, required this.accent,
      required this.headFont, required this.bodyFont, required this.fonts, this.radius = 14, this.dark = false, this.headWeight = 700, this.upperNav = false});
  final String id, name, about, goodFor;
  final String bg, surface, ink, muted, line, accent;

  /// CSS font families, and the Google Fonts query that loads them.
  final String headFont, bodyFont, fonts;
  final int radius, headWeight;
  final bool dark, upperNav;

  /// CSS variables for this style ([accent] replaces the style's own colour).
  String css(String? accentOverride) {
    final a = accentOverride ?? accent;
    return ':root{--bg:$bg;--surface:$surface;--ink:$ink;--muted:$muted;--line:$line;--accent:$a;--on-accent:${onColor(a)};'
        '--radius:${radius}px;--head:$headFont;--body:$bodyFont;--head-weight:$headWeight;--nav-case:${upperNav ? 'uppercase' : 'none'};'
        '--soft:${dark ? 'rgba(255,255,255,.06)' : 'rgba(15,23,42,.04)'};--shadow:${dark ? '0 1px 0 rgba(255,255,255,.04)' : '0 1px 2px rgba(16,24,40,.04),0 8px 24px rgba(16,24,40,.06)'};'
        '--shadow-lg:${dark ? '0 20px 50px rgba(0,0,0,.5)' : '0 24px 60px rgba(16,24,40,.14)'}}';
  }

  /// Black or white text, whichever reads better on [hex].
  static String onColor(String hex) {
    final v = int.tryParse(hex.replaceFirst('#', ''), radix: 16) ?? 0;
    double ch(int c) {
      final s = c / 255;
      return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) * ((s + 0.055) / 1.055) * 1.0;
    }

    final l = 0.2126 * ch((v >> 16) & 255) + 0.7152 * ch((v >> 8) & 255) + 0.0722 * ch(v & 255);
    return l > 0.45 ? '#111111' : '#FFFFFF';
  }
}

const siteStyles = <SiteStyle>[
  SiteStyle('modern', 'Modern', 'Clean, bright and confident. Clear type, soft cards, lots of air.', 'Shops, services, garages, most businesses',
      bg: '#F6F7F9', surface: '#FFFFFF', ink: '#0F172A', muted: '#64748B', line: '#E6E8EC', accent: '#2563EB',
      headFont: '"Inter",system-ui,-apple-system,sans-serif', bodyFont: '"Inter",system-ui,-apple-system,sans-serif', fonts: 'Inter:wght@400;500;600;700;800', radius: 14, headWeight: 800),
  SiteStyle('elegant', 'Elegant', 'Refined serif headings on warm ivory, fine lines and a gold accent.', 'Restaurants, hotels, salons, wine bars',
      bg: '#FAF7F2', surface: '#FFFFFF', ink: '#1C1917', muted: '#7A6F66', line: '#E9E2D8', accent: '#9A6B2F',
      headFont: '"Playfair Display",Georgia,serif', bodyFont: '"Lato",system-ui,sans-serif', fonts: 'Playfair+Display:wght@500;600;700&family=Lato:wght@400;700', radius: 6, headWeight: 600, upperNav: true),
  SiteStyle('warm', 'Warm & friendly', 'Rounded, cosy and inviting, with earthy colours.', 'Cafés, bakeries, family places, kids',
      bg: '#FFF8F1', surface: '#FFFFFF', ink: '#3B1F12', muted: '#94705C', line: '#F1E2D3', accent: '#E0612F',
      headFont: '"Fraunces",Georgia,serif', bodyFont: '"Nunito",system-ui,sans-serif', fonts: 'Fraunces:opsz,wght@9..144,600;9..144,700&family=Nunito:wght@400;600;700;800', radius: 20, headWeight: 700),
  SiteStyle('bold', 'Bold & dark', 'Dark, high-contrast and energetic, with a bright accent.', 'Gyms, bars, events, music, tech',
      bg: '#0B0C10', surface: '#15171E', ink: '#F4F4F6', muted: '#A0A3AD', line: '#262935', accent: '#C6F432',
      headFont: '"Space Grotesk",system-ui,sans-serif', bodyFont: '"Inter",system-ui,sans-serif', fonts: 'Space+Grotesk:wght@500;600;700&family=Inter:wght@400;500;600', radius: 12, headWeight: 700, dark: true, upperNav: true),
  SiteStyle('fresh', 'Fresh & calm', 'Light greens and gentle shapes. Calm, clean and trustworthy.', 'Clinics, wellness, tutoring, organic shops',
      bg: '#F2F8F5', surface: '#FFFFFF', ink: '#0E2A20', muted: '#5D7A6E', line: '#DCEBE3', accent: '#0F9D6E',
      headFont: '"DM Sans",system-ui,sans-serif', bodyFont: '"DM Sans",system-ui,sans-serif', fonts: 'DM+Sans:opsz,wght@9..40,400;9..40,500;9..40,700', radius: 18, headWeight: 700),
  SiteStyle('minimal', 'Minimal', 'Black and white, big type, nothing extra. Lets your pictures speak.', 'Real estate, studios, portfolios, fashion',
      bg: '#FFFFFF', surface: '#FFFFFF', ink: '#0A0A0A', muted: '#6B6B6B', line: '#EBEBEB', accent: '#0A0A0A',
      headFont: '"Manrope",system-ui,sans-serif', bodyFont: '"Manrope",system-ui,sans-serif', fonts: 'Manrope:wght@400;500;600;700;800', radius: 2, headWeight: 700, upperNav: true),
];

SiteStyle styleOf(String? id) => siteStyles.firstWhere((s) => s.id == id, orElse: () => siteStyles.first);

/// A sensible first style from what the user wrote.
String suggestStyle(String request) {
  final r = request.toLowerCase();
  if (RegExp(r'restaurant|hotel|guest ?house|b&b|wine|salon|spa|beauty|jewel|wedding|رستوران|هتل').hasMatch(r)) return 'elegant';
  if (RegExp(r'caf[eé]|coffee|bakery|cake|kids|family|pet|ice cream|کافه').hasMatch(r)) return 'warm';
  if (RegExp(r'gym|fitness|bar|club|event|concert|music|ticket|game|esport|باشگاه').hasMatch(r)) return 'bold';
  if (RegExp(r'clinic|doctor|dent|health|therap|yoga|wellness|tutor|school|course|lesson|organic|garden|کلینیک').hasMatch(r)) return 'fresh';
  if (RegExp(r'real estate|property|apartment|studio|photo|architect|fashion|gallery|portfolio').hasMatch(r)) return 'minimal';
  return 'modern';
}
