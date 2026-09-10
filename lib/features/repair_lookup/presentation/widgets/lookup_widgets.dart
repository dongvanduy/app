import 'package:flutter/material.dart';
import '../../../../core/error/exceptions.dart';
import '../../../pe_system/presentation/widgets/business_widgets.dart';
import '../../../pe_system/presentation/widgets/dashboard_theme.dart';
import '../providers/repair_lookup_provider.dart';

class LookupColors {
  LookupColors(BuildContext context) : base = DashboardColors.of(context);
  final DashboardColors base;
  Color get accent => base.accent;
  Color get background => base.background;
  Color get surface => base.surface;
  Color get tint => base.tint;
  Color get text => base.text;
  Color get muted => base.muted;
  Color get border => base.divider;
}

String lookupValue(String? value) =>
    value == null || value.trim().isEmpty ? '—' : value;

String formatLookupTime(DateTime? value) {
  if (value == null) return '—';
  final date = value.toUtc().add(const Duration(hours: 7));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(date.day)}/${two(date.month)}/${date.year} '
      '${two(date.hour)}:${two(date.minute)}:${two(date.second)}';
}

class LookupCard extends StatelessWidget {
  const LookupCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) {
    final c = LookupColors(context);
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.border),
      ),
      padding: padding,
      child: child,
    );
  }
}

class LookupHeading extends StatelessWidget {
  const LookupHeading({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  @override
  Widget build(BuildContext context) {
    final c = LookupColors(context);
    return Row(
      children: [
        CircleAvatar(
          backgroundColor: c.tint,
          foregroundColor: c.accent,
          child: Icon(icon),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: c.text,
                ),
              ),
              if (subtitle != null)
                Text(subtitle!, style: TextStyle(fontSize: 13, color: c.muted)),
            ],
          ),
        ),
      ],
    );
  }
}

class LookupStatusView extends StatelessWidget {
  const LookupStatusView({
    super.key,
    required this.status,
    this.error,
    this.onRetry,
  });
  final LookupStatus status;
  final ServerException? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = LookupColors(context);
    if (status == LookupStatus.loading) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            CircularProgressIndicator(color: c.accent),
            const SizedBox(height: 12),
            Text(bt(context, 'lookup_loading')),
          ],
        ),
      );
    }
    final key = switch (error?.kind) {
      ApiFailureKind.network => 'lookup_network_error',
      ApiFailureKind.timeout => 'lookup_timeout',
      ApiFailureKind.unauthorized => 'lookup_unauthorized',
      ApiFailureKind.forbidden => 'lookup_forbidden',
      ApiFailureKind.invalidResponse => 'lookup_invalid_response',
      ApiFailureKind.server => 'lookup_server_error',
      ApiFailureKind.notFound => 'lookup_resource_not_found',
      ApiFailureKind.business => 'lookup_business_error',
      _ => 'lookup_unknown_error',
    };
    final message =
        status == LookupStatus.idle
            ? bt(context, 'lookup_prompt')
            : status == LookupStatus.empty
            ? bt(context, 'lookup_empty')
            : bt(context, key);
    final backendMessage =
        error?.kind == ApiFailureKind.business && error!.message != key
            ? error!.message
            : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
      child: Column(
        children: [
          Icon(
            status == LookupStatus.error
                ? Icons.error_outline
                : Icons.manage_search,
            size: 36,
            color: status == LookupStatus.error ? c.base.danger : c.accent,
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: c.text),
          ),
          if (backendMessage != null) ...[
            const SizedBox(height: 8),
            Text(backendMessage, textAlign: TextAlign.center),
          ],
          if (status == LookupStatus.error && onRetry != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(bt(context, 'retry')),
            ),
          ],
        ],
      ),
    );
  }
}
