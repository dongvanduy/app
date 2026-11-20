import 'package:flutter/material.dart';

import 'dashboard_theme.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({
    super.key,
    required this.title,
    required this.scrollKey,
    required this.child,
    this.trailing,
    this.maxWidth = 1100,
  });

  final String title;
  final String scrollKey;
  final Widget child;
  final Widget? trailing;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return DashboardTheme(
      child: Builder(
        builder: (context) {
          return Scaffold(
            body: SafeArea(
              bottom: false,
              child: SingleChildScrollView(
                key: PageStorageKey<String>(scrollKey),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Semantics(
                                  header: true,
                                  child: Text(
                                    title,
                                    style: const TextStyle(
                                      fontSize: 30,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                ),
                              ),
                              if (trailing != null) trailing!,
                            ],
                          ),
                          const SizedBox(height: 20),
                          child,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class DashboardCard extends StatelessWidget {
  const DashboardCard({
    super.key,
    required this.child,
    this.onTap,
    this.gradient = false,
    this.waves = false,
    this.color,
    this.borderColor,
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool gradient;
  final bool waves;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final colors = DashboardColors.of(context);
    final radius = BorderRadius.circular(22);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: colors.dark ? 0.12 : 0.045),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: color ?? colors.surface,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color:
                  borderColor ?? (colors.dark ? colors.divider : Colors.white),
            ),
            gradient:
                gradient
                    ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [colors.surface, colors.tint],
                    )
                    : null,
          ),
          child: InkWell(
            onTap: onTap,
            child: Stack(
              children: [
                if (waves)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(painter: _CardWaves(colors.accent)),
                    ),
                  ),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CardWaves extends CustomPainter {
  const _CardWaves(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path =
        Path()
          ..moveTo(size.width * .55, size.height)
          ..cubicTo(
            size.width * .73,
            size.height * .2,
            size.width * .83,
            size.height * 1.25,
            size.width,
            size.height * .4,
          )
          ..lineTo(size.width, size.height)
          ..close();
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: .07));
    final second =
        Path()
          ..moveTo(size.width * .7, size.height)
          ..quadraticBezierTo(
            size.width * .9,
            size.height * .9,
            size.width,
            size.height * .25,
          )
          ..lineTo(size.width, size.height)
          ..close();
    canvas.drawPath(second, Paint()..color = color.withValues(alpha: .06));
  }

  @override
  bool shouldRepaint(_CardWaves oldDelegate) => oldDelegate.color != color;
}

class DashboardIcon extends StatelessWidget {
  const DashboardIcon({
    super.key,
    required this.icon,
    this.color,
    this.size = 42,
    this.iconSize = 25,
    this.circular = false,
  });
  final IconData icon;
  final Color? color;
  final double size;
  final double iconSize;
  final bool circular;

  @override
  Widget build(BuildContext context) {
    final colors = DashboardColors.of(context);
    final foreground =
        color == null
            ? colors.accent
            : colors.dark
            ? Color.lerp(color, Colors.white, .3)!
            : color!;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color:
            color == null
                ? colors.tint
                : foreground.withValues(alpha: colors.dark ? .14 : .09),
        borderRadius: BorderRadius.circular(circular ? size / 2 : 14),
      ),
      child: Icon(icon, color: foreground, size: iconSize),
    );
  }
}

class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
  });
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = DashboardColors.of(context);
    return DashboardCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  style: TextStyle(
                    color: colors.muted,
                    fontSize: 14,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 60),
                  child: Divider(height: 1, color: colors.divider),
                ),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.color,
    this.onTap,
    this.selector,
    this.showChevron = true,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Color? color;
  final VoidCallback? onTap;
  final Widget? selector;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final colors = DashboardColors.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
            final stackSelector =
                selector != null &&
                (constraints.maxWidth < 330 || scale > 1.15);
            final labels = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: colors.muted,
                    height: 1.3,
                  ),
                ),
              ],
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    DashboardIcon(icon: icon, color: color),
                    const SizedBox(width: 14),
                    Expanded(child: labels),
                    if (selector != null && !stackSelector) ...[
                      const SizedBox(width: 10),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 108),
                        child: selector!,
                      ),
                    ] else if (selector == null &&
                        showChevron &&
                        onTap != null) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.chevron_right_rounded, color: colors.muted),
                    ],
                  ],
                ),
                if (stackSelector) ...[
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerRight, child: selector),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
