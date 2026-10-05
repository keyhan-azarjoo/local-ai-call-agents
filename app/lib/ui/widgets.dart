import 'package:flutter/material.dart';

import '../theme/tokens.dart';

// ---------- Type ----------
TextStyle displayStyle(BuildContext context, double size) =>
    TextStyle(fontFamily: LL.display, fontSize: size, fontWeight: FontWeight.w700, letterSpacing: -.4, color: context.c.ink);

class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color});
  final String text;
  final Color? color;
  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(),
      style: TextStyle(fontFamily: LL.mono, fontSize: 10.5, letterSpacing: 1.3, color: color ?? context.c.muted));
}

class Muted extends StatelessWidget {
  const Muted(this.text, {super.key, this.size = 12.5, this.mono = false});
  final String text;
  final double size;
  final bool mono;
  @override
  Widget build(BuildContext context) =>
      Text(text, style: TextStyle(fontSize: size, color: context.c.muted, fontFamily: mono ? LL.mono : null));
}

class Mono extends StatelessWidget {
  const Mono(this.text, {super.key, this.size = 12.5});
  final String text;
  final double size;
  @override
  Widget build(BuildContext context) => Text(text, style: TextStyle(fontFamily: LL.mono, fontSize: size));
}

// ---------- Status lamp ----------
enum LampState { on, ring, off, err }

class Lamp extends StatefulWidget {
  const Lamp(this.state, {super.key});
  final LampState state;
  @override
  State<Lamp> createState() => _LampState();
}

class _LampState extends State<Lamp> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));

  @override
  void initState() {
    super.initState();
    if (widget.state == LampState.ring) _c.repeat();
  }

  @override
  void didUpdateWidget(Lamp old) {
    super.didUpdateWidget(old);
    widget.state == LampState.ring ? _c.repeat() : _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = switch (widget.state) {
      LampState.on => LL.green,
      LampState.ring => LL.amber,
      LampState.err => LL.red,
      LampState.off => const Color(0xFF8193A8),
    };
    final dot = Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: widget.state == LampState.off ? null : [BoxShadow(color: color.withValues(alpha: .25), spreadRadius: 3)],
      ),
    );
    if (widget.state != LampState.ring || MediaQuery.of(context).disableAnimations) return dot;
    return AnimatedBuilder(animation: _c, builder: (_, _) => Opacity(opacity: _c.value < .5 ? 1 : .3, child: dot));
  }
}

// ---------- Pill ----------
enum Tone { neutral, green, amber, red, blue }

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.tone = Tone.neutral, this.lamp});
  final String text;
  final Tone tone;
  final LampState? lamp;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (bg, fg) = switch (tone) {
      Tone.green => (c.greenSoft, c.greenInk),
      Tone.amber => (c.amberSoft, c.amberInk),
      Tone.red => (c.redSoft, c.redInk),
      Tone.blue => (c.blueSoft, c.blueInk),
      Tone.neutral => (c.canvas, c.muted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
        border: tone == Tone.neutral ? Border.all(color: c.line) : null,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (lamp != null) ...[Lamp(lamp!), const SizedBox(width: 6)],
        Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: fg)),
      ]),
    );
  }
}

// ---------- Panel ----------
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.fromLTRB(20, 18, 20, 18), this.borderColor});
  final Widget child;
  final EdgeInsets padding;
  final Color? borderColor;
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: context.c.panel,
          borderRadius: BorderRadius.circular(LL.r),
          border: Border.all(color: borderColor ?? context.c.line),
          boxShadow: Theme.of(context).brightness == Brightness.dark
              ? null
              : const [BoxShadow(color: Color(0x0D10233A), blurRadius: 16, offset: Offset(0, 4))],
        ),
        padding: padding,
        child: child,
      );
}

/// A panel with a header row and a body (usually a list of [Tile]s).
class Section extends StatelessWidget {
  const Section({super.key, required this.title, this.trailing, required this.children});
  final String title;
  final Widget? trailing;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Panel(
        padding: EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.c.line))),
            child: Row(children: [
              Text(title, style: const TextStyle(fontFamily: LL.display, fontSize: 17, fontWeight: FontWeight.w600)),
              const Spacer(),
              ?trailing,
            ]),
          ),
          ...children,
        ]),
      );
}

class Tile extends StatelessWidget {
  const Tile({super.key, this.leading, required this.title, this.subtitle, this.trailing, this.onTap, this.last = false});
  final Widget? leading;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool last;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: context.c.line))),
          child: Row(children: [
            if (leading != null) ...[leading!, const SizedBox(width: 14)],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                DefaultTextStyle.merge(style: const TextStyle(fontWeight: FontWeight.w600), child: title),
                if (subtitle != null) ...[const SizedBox(height: 2), subtitle!],
              ]),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          ]),
        ),
      );
}

class LogoBox extends StatelessWidget {
  const LogoBox({super.key, required this.child, this.accent = false});
  final Widget child;
  final bool accent;
  @override
  Widget build(BuildContext context) => Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: accent ? context.c.amberSoft : context.c.canvas,
          borderRadius: BorderRadius.circular(9),
          border: accent ? null : Border.all(color: context.c.line),
        ),
        child: IconTheme(data: IconThemeData(size: 19, color: accent ? context.c.amberInk : context.c.ink), child: child),
      );
}

// ---------- Buttons ----------
enum BtnKind { normal, primary, amber, green, danger, ghost }

class Btn extends StatelessWidget {
  const Btn(this.label, {super.key, this.onPressed, this.icon, this.kind = BtnKind.normal, this.small = false, this.large = false});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final BtnKind kind;
  final bool small, large;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (bg, fg, border) = switch (kind) {
      BtnKind.primary => dark ? (LL.amber, LL.navy, LL.amber) : (LL.navy, Colors.white, LL.navy),
      BtnKind.amber => (LL.amber, LL.navy, LL.amber),
      BtnKind.green => (LL.green, Colors.white, LL.green),
      BtnKind.danger => (LL.red, Colors.white, LL.red),
      BtnKind.ghost => (Colors.transparent, c.ink, Colors.transparent),
      BtnKind.normal => (c.panel, c.ink, c.line),
    };
    final h = small ? 28.0 : large ? 42.0 : 34.0;
    return SizedBox(
      height: h,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: onPressed == null ? bg.withValues(alpha: .5) : bg,
          foregroundColor: fg,
          disabledForegroundColor: fg.withValues(alpha: .6),
          padding: EdgeInsets.symmetric(horizontal: small ? 10 : large ? 20 : 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(LL.rSm), side: BorderSide(color: border)),
          textStyle: TextStyle(fontFamily: LL.body, fontSize: small ? 12.5 : large ? 14 : 13, fontWeight: FontWeight.w600),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: small ? 14 : 16), if (label.isNotEmpty) const SizedBox(width: 7)],
          if (label.isNotEmpty) Text(label),
        ]),
      ),
    );
  }
}

// ---------- Page header ----------
class PageHead extends StatelessWidget {
  const PageHead(this.title, {super.key, this.description, this.actions = const []});
  final String title;
  final String? description;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) {
    final text = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: displayStyle(context, 28)),
      if (description != null) ...[
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 660),
          child: Text(description!, style: TextStyle(color: context.c.muted, fontSize: 14)),
        ),
      ],
    ]);
    final buttons = Wrap(spacing: 8, runSpacing: 8, children: actions);
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: LayoutBuilder(
        builder: (context, box) => box.maxWidth > 760
            ? Row(crossAxisAlignment: CrossAxisAlignment.end, children: [Expanded(child: text), const SizedBox(width: 16), buttons])
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [text, if (actions.isNotEmpty) ...[const SizedBox(height: 12), buttons]]),
      ),
    );
  }
}

// ---------- Inputs ----------
class Field extends StatelessWidget {
  const Field({super.key, required this.label, required this.child, this.hint});
  final String label;
  final Widget child;
  final String? hint;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        child,
        if (hint != null) ...[const SizedBox(height: 5), Muted(hint!, size: 12)],
      ]);
}

class SwitchRow extends StatelessWidget {
  const SwitchRow(this.label, {super.key, required this.value, required this.onChanged});
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13.5))),
          Transform.scale(scale: .8, child: Switch(value: value, onChanged: onChanged)),
        ]),
      );
}

class Dropdown<T> extends StatelessWidget {
  const Dropdown({super.key, required this.value, required this.items, required this.onChanged});
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;
  @override
  Widget build(BuildContext context) => Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
            color: context.c.panel, border: Border.all(color: context.c.line), borderRadius: BorderRadius.circular(LL.rSm)),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: items.containsKey(value) ? value : items.keys.first,
            isExpanded: true,
            borderRadius: BorderRadius.circular(LL.rSm),
            style: TextStyle(fontFamily: LL.body, fontSize: 13.5, color: context.c.ink),
            items: [for (final e in items.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => v == null ? null : onChanged(v),
          ),
        ),
      );
}

class Segmented<T> extends StatelessWidget {
  const Segmented({super.key, required this.value, required this.options, required this.onChanged});
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: c.canvas, border: Border.all(color: c.line), borderRadius: BorderRadius.circular(LL.rSm)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final e in options.entries)
          InkWell(
            onTap: () => onChanged(e.key),
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(color: e.key == value ? c.panel : null, borderRadius: BorderRadius.circular(4)),
              child: Text(e.value,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: e.key == value ? FontWeight.w600 : FontWeight.w400,
                      color: e.key == value ? c.ink : c.muted)),
            ),
          ),
      ]),
    );
  }
}

// ---------- Data ----------
class Meter extends StatelessWidget {
  const Meter(this.value, {super.key, this.color});
  final double value;
  final Color? color;
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: value.clamp(0, 1),
          minHeight: 6,
          backgroundColor: context.c.canvas,
          color: color ?? LL.navy3,
        ),
      );
}

class KV extends StatelessWidget {
  const KV(this.rows, {super.key});
  final List<(String, Widget)> rows;
  @override
  Widget build(BuildContext context) => Column(children: [
        for (final (k, v) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 130, child: Muted(k, size: 13)),
              Expanded(child: DefaultTextStyle.merge(style: const TextStyle(fontSize: 13), child: v)),
            ]),
          ),
      ]);
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.body, this.action});
  final IconData icon;
  final String title, body;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
        child: Column(children: [
          Icon(icon, size: 28, color: context.c.muted),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 4),
          Text(body, textAlign: TextAlign.center, style: TextStyle(color: context.c.muted, fontSize: 13)),
          if (action != null) ...[const SizedBox(height: 14), action!],
        ]),
      );
}

/// Lays children in a responsive grid: [cols] columns, 1 on narrow screens.
class Grid extends StatelessWidget {
  const Grid({super.key, required this.cols, required this.children, this.gap = 16});
  final int cols;
  final double gap;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final n = box.maxWidth < 640 ? 1 : cols;
        final w = (box.maxWidth - gap * (n - 1)) / n;
        return Wrap(spacing: gap, runSpacing: gap, children: [for (final c in children) SizedBox(width: w, child: c)]);
      });
}

/// SIGNATURE: the call drawn as a patch cord through the exchange.
class CallPath extends StatelessWidget {
  const CallPath({super.key, required this.stages, this.hot});
  final List<(String, String, String, LampState)> stages;
  final int? hot;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final items = <Widget>[];
    for (var i = 0; i < stages.length; i++) {
      final (eyebrow, name, ms, lamp) = stages[i];
      if (i > 0) items.add(Container(width: 26, height: 2, color: c.line));
      items.add(Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.panel,
            borderRadius: BorderRadius.circular(LL.r),
            border: Border.all(color: hot == i ? LL.amber : c.line),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Lamp(lamp), const SizedBox(width: 7), Flexible(child: Eyebrow(eyebrow))]),
            const SizedBox(height: 6),
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
            Muted(ms, mono: true, size: 12),
          ]),
        ),
      ));
    }
    return Row(children: items);
  }
}

String ago(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final diff = DateTime.now().difference(d);
  String two(int n) => n.toString().padLeft(2, '0');
  if (diff.inDays == 0) return 'Today ${two(d.hour)}:${two(d.minute)}';
  if (diff.inDays == 1) return 'Yesterday ${two(d.hour)}:${two(d.minute)}';
  return '${d.day}/${d.month} ${two(d.hour)}:${two(d.minute)}';
}
