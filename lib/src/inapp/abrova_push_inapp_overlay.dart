import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';

import '../inapp_message.dart';
import '../abrova_push.dart';

/// Optional hook fired after the overlay records the button-click impression.
/// Use this for deep-link routing that needs BuildContext.
typedef AbrovaPushInAppButtonTap = void Function(
  BuildContext context,
  InAppMessage message,
  InAppButton button,
);

/// Callback wired into every button/dismiss action passed to a custom builder.
class AbrovaPushInAppActions {
  AbrovaPushInAppActions({
    required this.onButtonTap,
    required this.onDismiss,
  });

  /// Records the button-click impression, fires [AbrovaPushInAppOverlay.onButtonTap],
  /// then removes the overlay. Call this from custom buttons in [AbrovaPushInAppBuilders].
  final void Function(InAppButton button) onButtonTap;

  /// Records the dismiss impression and removes the overlay.
  /// Call from custom close buttons or backdrop taps.
  final VoidCallback onDismiss;
}

/// Signature for a custom renderer. Return any widget — the overlay takes care
/// of insertion, animation, and impression bookkeeping via [actions].
typedef AbrovaPushInAppRendererBuilder = Widget Function(
  BuildContext context,
  InAppMessage message,
  InAppMessageContent content,
  AbrovaPushInAppActions actions,
);

/// Per-type overrides. Any null builder falls back to the default renderer.
class AbrovaPushInAppBuilders {
  const AbrovaPushInAppBuilders({
    this.modal,
    this.banner,
    this.fullscreen,
    this.card,
  });

  final AbrovaPushInAppRendererBuilder? modal;
  final AbrovaPushInAppRendererBuilder? banner;
  final AbrovaPushInAppRendererBuilder? fullscreen;
  final AbrovaPushInAppRendererBuilder? card;

  AbrovaPushInAppRendererBuilder? forType(InAppMessageType type) {
    switch (type) {
      case InAppMessageType.modal:
        return modal;
      case InAppMessageType.banner:
        return banner;
      case InAppMessageType.fullscreen:
        return fullscreen;
      case InAppMessageType.card:
        return card;
    }
  }
}

/// Styling knobs for the built-in renderers. Anything null uses the default.
/// For deeper changes, pass [AbrovaPushInAppBuilders] instead.
class AbrovaPushInAppTheme {
  const AbrovaPushInAppTheme({
    this.backdropColor,
    this.modalBackgroundColor,
    this.modalTextColor,
    this.modalBorderRadius,
    this.modalElevation,
    this.modalMaxWidth,
    this.bannerBackgroundColor,
    this.bannerTextColor,
    this.bannerBorderRadius,
    this.bannerElevation,
    this.fullscreenBackgroundColor,
    this.fullscreenTextColor,
    this.cardBackgroundColor,
    this.cardTextColor,
    this.cardBorderRadius,
    this.cardElevation,
    this.cardMaxWidth,
    this.animationDuration,
  });

  final Color? backdropColor;

  final Color? modalBackgroundColor;
  final Color? modalTextColor;
  final double? modalBorderRadius;
  final double? modalElevation;
  final double? modalMaxWidth;

  final Color? bannerBackgroundColor;
  final Color? bannerTextColor;
  final double? bannerBorderRadius;
  final double? bannerElevation;

  final Color? fullscreenBackgroundColor;
  final Color? fullscreenTextColor;

  final Color? cardBackgroundColor;
  final Color? cardTextColor;
  final double? cardBorderRadius;
  final double? cardElevation;
  final double? cardMaxWidth;

  final Duration? animationDuration;

  static const AbrovaPushInAppTheme defaults = AbrovaPushInAppTheme();
}

/// Wrap your app with this widget to render Abrova Push in-app messages.
///
/// The native SDKs skip their own UI once a callback is set, and the Flutter
/// plugin always sets that callback. Without this overlay, messages fetch,
/// match, and get silently dropped. Drop this widget above your MaterialApp
/// (or inside it, in `builder`) and messages render for free.
///
/// ```dart
/// AbrovaPushInAppOverlay(
///   onButtonTap: (context, message, button) {
///     if (button.action == InAppButtonAction.deepLink && button.value != null) {
///       context.go(button.value!);
///     }
///   },
///   child: MaterialApp.router(...),
/// )
/// ```
class AbrovaPushInAppOverlay extends StatefulWidget {
  const AbrovaPushInAppOverlay({
    super.key,
    required this.child,
    this.onButtonTap,
    this.theme = AbrovaPushInAppTheme.defaults,
    this.builders = const AbrovaPushInAppBuilders(),
  });

  final Widget child;
  final AbrovaPushInAppButtonTap? onButtonTap;

  /// Style overrides for the built-in renderers.
  final AbrovaPushInAppTheme theme;

  /// Per-type builder overrides. Use to fully replace any renderer.
  final AbrovaPushInAppBuilders builders;

  @override
  State<AbrovaPushInAppOverlay> createState() => _AbrovaPushInAppOverlayState();
}

class _AbrovaPushInAppOverlayState extends State<AbrovaPushInAppOverlay> {
  final GlobalKey<OverlayState> _overlayKey = GlobalKey<OverlayState>();
  OverlayEntry? _currentEntry;
  InAppMessage? _currentMessage;
  Timer? _delayTimer;

  @override
  void initState() {
    super.initState();
    AbrovaPush.onInAppMessageReady(_handleMessageReady);
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _removeCurrent();
    super.dispose();
  }

  void _handleMessageReady(InAppMessage message) {
    // Coalesce duplicates and let the newest message win.
    if (_currentMessage?.id == message.id) return;
    _delayTimer?.cancel();

    final delay = Duration(seconds: message.delaySeconds);
    if (delay > Duration.zero) {
      _delayTimer = Timer(delay, () => _present(message));
    } else {
      _present(message);
    }
  }

  void _present(InAppMessage message) {
    final overlay = _overlayKey.currentState;
    if (overlay == null) return;

    _removeCurrent();
    _currentMessage = message;

    final entry = OverlayEntry(
      builder: (context) => _AbrovaInAppRoot(
        message: message,
        theme: widget.theme,
        builders: widget.builders,
        onButtonTap: (button) => _onButtonTap(context, message, button),
        onDismiss: () => _onDismiss(message),
      ),
    );
    _currentEntry = entry;
    overlay.insert(entry);
  }

  void _removeCurrent() {
    _currentEntry?.remove();
    _currentEntry = null;
    _currentMessage = null;
  }

  void _onButtonTap(BuildContext context, InAppMessage message, InAppButton button) {
    AbrovaPush.recordInAppButtonClick(message.id, button.id);
    widget.onButtonTap?.call(context, message, button);
    _removeCurrent();
  }

  void _onDismiss(InAppMessage message) {
    AbrovaPush.recordInAppDismissed(message.id);
    _removeCurrent();
  }

  @override
  Widget build(BuildContext context) {
    // Placed above MaterialApp (as documented) there is no text direction yet; the overlay needs one.
    // Each message sets its own direction from its words and the app's language.
    final direction = Directionality.maybeOf(context) ??
        (_rtlLanguages.contains(PlatformDispatcher.instance.locale.languageCode.toLowerCase())
            ? TextDirection.rtl
            : TextDirection.ltr);
    // The messages' Overlay sits BESIDE the app, not around it: around it, it was the app's root Overlay, and a
    // text field's Copy/Paste toolbar (which goes to the root Overlay) found no localizations above MaterialApp and
    // failed (a grey box in release). Empty, it lets every tap through to the app.
    return Directionality(
      textDirection: direction,
      child: Stack(
        children: [
          widget.child,
          Positioned.fill(child: Overlay(key: _overlayKey)),
        ],
      ),
    );
  }
}

class _AbrovaInAppRoot extends StatelessWidget {
  const _AbrovaInAppRoot({
    required this.message,
    required this.theme,
    required this.builders,
    required this.onButtonTap,
    required this.onDismiss,
  });

  final InAppMessage message;
  final AbrovaPushInAppTheme theme;
  final AbrovaPushInAppBuilders builders;
  final ValueChanged<InAppButton> onButtonTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final locale = _resolveLocale(context);
    final content = message.getLocalizedContent(locale);
    final direction = _resolveDirection(context, locale, content);

    final custom = builders.forType(message.type);
    final Widget renderer;
    if (custom != null) {
      renderer = custom(
        context,
        message,
        content,
        AbrovaPushInAppActions(
          onButtonTap: onButtonTap,
          onDismiss: onDismiss,
        ),
      );
    } else {
      switch (message.type) {
        case InAppMessageType.banner:
          renderer = _BannerRenderer(
            content: content,
            theme: theme,
            onButtonTap: onButtonTap,
            onDismiss: onDismiss,
          );
          break;
        case InAppMessageType.fullscreen:
          renderer = _FullscreenRenderer(
            content: content,
            theme: theme,
            onButtonTap: onButtonTap,
            onDismiss: onDismiss,
          );
          break;
        case InAppMessageType.card:
          renderer = _CardRenderer(
            content: content,
            theme: theme,
            onButtonTap: onButtonTap,
            onDismiss: onDismiss,
          );
          break;
        case InAppMessageType.modal:
          renderer = _ModalRenderer(
            content: content,
            theme: theme,
            onButtonTap: onButtonTap,
            onDismiss: onDismiss,
          );
          break;
      }
    }

    return Directionality(
      textDirection: direction,
      child: renderer,
    );
  }

  static String _resolveLocale(BuildContext context) {
    final locale = Localizations.maybeLocaleOf(context) ??
        PlatformDispatcher.instance.locale;
    return locale.countryCode == null || locale.countryCode!.isEmpty
        ? locale.languageCode
        : '${locale.languageCode}-${locale.countryCode}';
  }

  static TextDirection _resolveDirection(BuildContext context, String locale, InAppMessageContent content) {
    // Right-to-left words (a Farsi app's own text) read right-to-left whatever the app's language.
    if (RegExp(r'[\u0590-\u08FF]').hasMatch(content.title + content.body)) return TextDirection.rtl;
    final direction = Directionality.maybeOf(context);
    if (direction != null) return direction;
    return _rtlLanguages.contains(locale.split('-').first.toLowerCase())
        ? TextDirection.rtl
        : TextDirection.ltr;
  }
}

// ==================== Shared helpers ====================

const Set<String> _rtlLanguages = {'fa', 'ar', 'he', 'ur', 'ps', 'sd', 'ku'};

/// "Close" in the app's language when MaterialApp's localizations are there (not above MaterialApp).
String _closeLabel(BuildContext context) =>
    Localizations.of<MaterialLocalizations>(context, MaterialLocalizations)?.closeButtonTooltip ?? 'Close';

/// Image width : height, as in the Console (Push › In-app).
const double kInAppModalImageRatio = 2;
const double kInAppFullscreenImageRatio = 2;
const double kInAppCardImageRatio = 3;

const Color _primary = Color(0xFF1C72C8);
const Color _destructive = Color(0xFFDC2626);
const Color _defaultText = Color(0xFF18181B);

Color? _parseColor(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  var normalized = hex.replaceFirst('#', '');
  if (normalized.length == 6) normalized = 'FF$normalized';
  final value = int.tryParse(normalized, radix: 16);
  return value == null ? null : Color(value);
}

Widget _image(String url, double ratio) => AspectRatio(
      aspectRatio: ratio,
      child: Container(
        color: const Color(0x14000000),
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      ),
    );

/// Title and body, as the Console's preview: bold title, body slightly faded.
Widget _texts(BuildContext context, InAppMessageContent c, Color fg,
    {required double titleSize, required double bodySize, double top = 12}) {
  return Padding(
    padding: EdgeInsetsDirectional.fromSTEB(14, top, 14, 4),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (c.title.isNotEmpty)
          Text(c.title, style: TextStyle(color: fg, fontSize: titleSize, fontWeight: FontWeight.w700, height: 1.3)),
        if (c.title.isNotEmpty && c.body.isNotEmpty) const SizedBox(height: 4),
        if (c.body.isNotEmpty)
          Text(c.body, style: TextStyle(color: fg.withValues(alpha: 0.85), fontSize: bodySize, height: 1.35)),
      ],
    ),
  );
}

/// One button in the Console's styles: primary filled blue, secondary outlined, text plain, destructive red.
Widget _button(InAppButton b, Color fg, ValueChanged<InAppButton> onTap, {bool compact = false}) {
  final size = compact ? 12.5 : 14.0;
  final pad = EdgeInsets.symmetric(horizontal: 10, vertical: compact ? 4 : 8);
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(9));
  final min = Size(0, compact ? 30 : 40);
  final label = Text(b.text, maxLines: 1, overflow: TextOverflow.ellipsis);
  switch (b.style) {
    case InAppButtonStyle.primary:
      return FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: _primary,
          foregroundColor: Colors.white,
          padding: pad,
          minimumSize: min,
          shape: shape,
          textStyle: TextStyle(fontSize: size, fontWeight: FontWeight.w700),
        ),
        onPressed: () => onTap(b),
        child: label,
      );
    case InAppButtonStyle.secondary:
      return OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: fg.withValues(alpha: 0.85),
          side: BorderSide(color: fg.withValues(alpha: 0.85)),
          padding: pad,
          minimumSize: min,
          shape: shape,
          textStyle: TextStyle(fontSize: size, fontWeight: FontWeight.w700),
        ),
        onPressed: () => onTap(b),
        child: label,
      );
    case InAppButtonStyle.text:
    case InAppButtonStyle.destructive:
      return TextButton(
        style: TextButton.styleFrom(
          foregroundColor: b.style == InAppButtonStyle.destructive ? _destructive : fg.withValues(alpha: 0.8),
          padding: pad,
          minimumSize: Size(0, compact ? 30 : 32),
          shape: shape,
          textStyle: TextStyle(fontSize: size, fontWeight: FontWeight.w500),
        ),
        onPressed: () => onTap(b),
        child: label,
      );
  }
}

/// Buttons stacked (modal, full screen) or side by side (card); null without buttons.
Widget? _buttons(InAppMessageContent c, Color fg, ValueChanged<InAppButton> onTap, {required bool row}) {
  if (c.buttons.isEmpty) return null;
  final items = [for (final b in c.buttons) _button(b, fg, onTap)];
  return Padding(
    padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
    child: row
        ? Row(children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(child: items[i]),
            ],
          ])
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(height: 6),
              items[i],
            ],
          ]),
  );
}

/// Round close button for the panel's top corner (end side: left in right-to-left).
Widget _roundClose(BuildContext context, VoidCallback onDismiss) => Semantics(
      button: true,
      label: _closeLabel(context),
      child: GestureDetector(
        onTap: onDismiss,
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: Color(0x59000000), shape: BoxShape.circle),
          child: const Icon(Icons.close, size: 16, color: Colors.white),
        ),
      ),
    );

Widget _panel({required Color bg, required double radius, required double elevation, required Widget child}) => Material(
      color: bg,
      elevation: elevation,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: Clip.antiAlias,
      child: child,
    );

// ==================== Renderers ====================

class _ModalRenderer extends StatelessWidget {
  const _ModalRenderer({
    required this.content,
    required this.theme,
    required this.onButtonTap,
    required this.onDismiss,
  });

  final InAppMessageContent content;
  final AbrovaPushInAppTheme theme;
  final ValueChanged<InAppButton> onButtonTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final bg = _parseColor(content.backgroundColor) ?? theme.modalBackgroundColor ?? Colors.white;
    final fg = _parseColor(content.textColor) ?? theme.modalTextColor ?? _defaultText;
    final backdrop = theme.backdropColor ?? Colors.black.withValues(alpha: 0.45);

    return _FadeIn(
      duration: theme.animationDuration,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(onTap: onDismiss, child: ColoredBox(color: backdrop)),
          ),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: theme.modalMaxWidth ?? 420),
                  child: _panel(
                    bg: bg,
                    radius: theme.modalBorderRadius ?? 16,
                    elevation: theme.modalElevation ?? 12,
                    child: Stack(children: [
                      SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (content.imageUrl != null) _image(content.imageUrl!, kInAppModalImageRatio),
                            _texts(context, content, fg, titleSize: 16, bodySize: 13.5),
                            _buttons(content, fg, onButtonTap, row: false) ?? const SizedBox(height: 12),
                          ],
                        ),
                      ),
                      PositionedDirectional(top: 8, end: 8, child: _roundClose(context, onDismiss)),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BannerRenderer extends StatelessWidget {
  const _BannerRenderer({
    required this.content,
    required this.theme,
    required this.onButtonTap,
    required this.onDismiss,
  });

  final InAppMessageContent content;
  final AbrovaPushInAppTheme theme;
  final ValueChanged<InAppButton> onButtonTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final bg = _parseColor(content.backgroundColor) ?? theme.bannerBackgroundColor ?? Colors.white;
    final fg = _parseColor(content.textColor) ?? theme.bannerTextColor ?? _defaultText;
    final bottom = content.position == 'bottom';

    final bar = _panel(
      bg: bg,
      radius: theme.bannerBorderRadius ?? 14,
      elevation: theme.bannerElevation ?? 8,
      child: InkWell(
        onTap: content.buttons.isEmpty ? onDismiss : null,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(10, 10, 4, 10),
          child: Row(children: [
            if (content.imageUrl != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(width: 40, height: 40, child: _image(content.imageUrl!, 1)),
                ),
              ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (content.title.isNotEmpty)
                    Text(content.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: fg, fontSize: 14, fontWeight: FontWeight.w700)),
                  if (content.body.isNotEmpty)
                    Text(content.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: fg.withValues(alpha: 0.8), fontSize: 12)),
                ],
              ),
            ),
            for (final b in content.buttons)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 6),
                child: _button(b, fg, onButtonTap, compact: true),
              ),
            IconButton(
              icon: Icon(Icons.close, size: 18, color: fg.withValues(alpha: 0.7)),
              onPressed: onDismiss,
              tooltip: _closeLabel(context),
              visualDensity: VisualDensity.compact,
            ),
          ]),
        ),
      ),
    );

    return Align(
      alignment: bottom ? Alignment.bottomCenter : Alignment.topCenter,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(8, bottom ? 0 : 8, 8, bottom ? 12 : 0),
          child: Dismissible(
            key: const ValueKey('abrova_push_banner'),
            direction: bottom ? DismissDirection.down : DismissDirection.up,
            onDismissed: (_) => onDismiss(),
            child: _Slide(from: bottom ? 0.4 : -0.4, duration: theme.animationDuration, child: bar),
          ),
        ),
      ),
    );
  }
}

class _FullscreenRenderer extends StatelessWidget {
  const _FullscreenRenderer({
    required this.content,
    required this.theme,
    required this.onButtonTap,
    required this.onDismiss,
  });

  final InAppMessageContent content;
  final AbrovaPushInAppTheme theme;
  final ValueChanged<InAppButton> onButtonTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final bg = _parseColor(content.backgroundColor) ?? theme.fullscreenBackgroundColor ?? Colors.white;
    final fg = _parseColor(content.textColor) ?? theme.fullscreenTextColor ?? _defaultText;
    final insets = MediaQuery.paddingOf(context);

    return _FadeIn(
      duration: theme.animationDuration,
      child: Material(
        color: bg,
        child: Stack(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (content.imageUrl != null)
                    _image(content.imageUrl!, kInAppFullscreenImageRatio)
                  else
                    SizedBox(height: insets.top + 48),
                  _texts(context, content, fg, titleSize: 22, bodySize: 15, top: 18),
                ]),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(bottom: insets.bottom + 8),
              child: _buttons(content, fg, onButtonTap, row: false) ?? const SizedBox(height: 8),
            ),
          ]),
          PositionedDirectional(top: insets.top + 10, end: 8, child: _roundClose(context, onDismiss)),
        ]),
      ),
    );
  }
}

class _CardRenderer extends StatelessWidget {
  const _CardRenderer({
    required this.content,
    required this.theme,
    required this.onButtonTap,
    required this.onDismiss,
  });

  final InAppMessageContent content;
  final AbrovaPushInAppTheme theme;
  final ValueChanged<InAppButton> onButtonTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final bg = _parseColor(content.backgroundColor) ?? theme.cardBackgroundColor ?? Colors.white;
    final fg = _parseColor(content.textColor) ?? theme.cardTextColor ?? _defaultText;

    final card = _panel(
      bg: bg,
      radius: theme.cardBorderRadius ?? 16,
      elevation: theme.cardElevation ?? 12,
      child: Stack(children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (content.imageUrl != null) _image(content.imageUrl!, kInAppCardImageRatio),
            _texts(context, content, fg, titleSize: 15, bodySize: 13),
            _buttons(content, fg, onButtonTap, row: true) ?? const SizedBox(height: 12),
          ],
        ),
        PositionedDirectional(top: 8, end: 8, child: _roundClose(context, onDismiss)),
      ]),
    );

    // At the bottom without dimming: the app stays usable around it.
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: theme.cardMaxWidth ?? 480),
            child: Dismissible(
              key: const ValueKey('abrova_push_card'),
              direction: DismissDirection.down,
              onDismissed: (_) => onDismiss(),
              child: _Slide(from: 0.4, duration: theme.animationDuration, child: card),
            ),
          ),
        ),
      ),
    );
  }
}

// ==================== Animations ====================

class _FadeIn extends StatelessWidget {
  const _FadeIn({required this.child, this.duration});
  final Widget child;
  final Duration? duration;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration ?? const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      builder: (_, v, c) => Opacity(opacity: v, child: c),
      child: child,
    );
  }
}

/// Fades in while sliding from [from] (a fraction of its own height; negative = from above).
class _Slide extends StatelessWidget {
  const _Slide({required this.child, required this.from, this.duration});
  final Widget child;
  final double from;
  final Duration? duration;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration ?? const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      builder: (_, v, c) => Opacity(
        opacity: v,
        child: FractionalTranslation(translation: Offset(0, from * (1 - v)), child: c),
      ),
      child: child,
    );
  }
}
