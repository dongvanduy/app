import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../../../../core/error/exceptions.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/code_provider.dart';
import 'business_widgets.dart';

class BorrowRepairDialog extends StatefulWidget {
  const BorrowRepairDialog({super.key, required this.batch});
  final BorrowBatch batch;

  @override
  State<BorrowRepairDialog> createState() => _BorrowRepairDialogState();
}

class _BorrowRepairDialogState extends State<BorrowRepairDialog> {
  bool _submitting = false;
  String? _error;
  final _borrowerController = TextEditingController();

  @override
  void dispose() {
    _borrowerController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) {
      if (kDebugMode) {
        debugPrint('[PE Borrow][Confirm] ignored: request already in progress');
      }
      return;
    }
    final currentUser =
        context.read<AuthProvider>().user?.username.trim() ?? '';
    if (currentUser.isEmpty) {
      if (kDebugMode) {
        debugPrint(
          '[PE Borrow][Confirm] blocked: current login username is empty',
        );
      }
      setState(() => _error = bt(context, 'pe_borrow_login_required'));
      return;
    }
    final borrower = _borrowerController.text.trim();
    if (borrower.isEmpty || borrower.length > 100) {
      setState(() => _error = bt(context, 'pe_borrower_required'));
      return;
    }
    if (kDebugMode) {
      debugPrint(
        '[PE Borrow][Confirm] submit: searchListId=${widget.batch.searchListId}, '
        'serialCount=${widget.batch.serialNumbers.length}, '
        'serialNumbers=${widget.batch.serialNumbers}, '
        'currentUser=$currentUser',
      );
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await context.read<CodeProvider>().borrowFoundCodes(
        batch: widget.batch,
        borrower: borrower,
      );
      if (!mounted) return;
      if (result != null) {
        if (kDebugMode) {
          debugPrint(
            '[PE Borrow][Confirm] success response mapped: '
            'totalBorrowed=${result.totalBorrowed}, '
            'totalNotFound=${result.totalNotFound}, '
            'totalFailed=${result.totalFailed}, '
            'borrowedSerials=${result.borrowed.map((item) => item.serialNumber).toList()}',
          );
        }
        Navigator.of(context).pop(result);
      } else {
        if (kDebugMode) {
          debugPrint(
            '[PE Borrow][Confirm] no result: batch became unavailable',
          );
        }
        setState(() => _error = bt(context, 'pe_borrow_unavailable'));
      }
    } catch (error) {
      if (!mounted) return;
      if (kDebugMode) {
        if (error is ServerException) {
          debugPrint(
            '[PE Borrow][Confirm] API error: status=${error.statusCode}, '
            'kind=${error.kind}, message=${error.message}, '
            'response=${error.responseData}',
          );
        } else {
          debugPrint('[PE Borrow][Confirm] unexpected error: $error');
        }
      }
      final key =
          error is ServerException
              ? switch (error.kind) {
                ApiFailureKind.network => 'lookup_network_error',
                ApiFailureKind.timeout => 'lookup_timeout',
                ApiFailureKind.invalidResponse => 'lookup_invalid_response',
                ApiFailureKind.unauthorized => 'lookup_unauthorized',
                ApiFailureKind.forbidden => 'lookup_forbidden',
                _ => null,
              }
              : 'pe_borrow_failed';
      setState(
        () => _error = key == null ? error.toString() : bt(context, key),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    watchBusinessLanguage(context);
    final currentUser =
        context.watch<AuthProvider>().user?.username.trim() ?? '';
    return PopScope(
      canPop: !_submitting,
      child: AlertDialog(
        title: Text(bt(context, 'pe_borrow')),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${bt(context, 'Quantity')}: ${widget.batch.serialNumbers.length}',
            ),
            const SizedBox(height: 12),
            Text(
              '${bt(context, 'pe_borrow_operator')}: '
              '${currentUser.isEmpty ? '-' : currentUser}',
              key: const ValueKey('pe_borrow_current_user'),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('pe_borrower_field'),
              controller: _borrowerController,
              autofocus: true,
              enabled: !_submitting,
              maxLength: 100,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: bt(context, 'pe_borrower'),
                hintText: bt(context, 'pe_borrower_required'),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                key: const ValueKey('pe_borrow_error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_submitting) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
          ],
        ),
        actions: [
          TextButton(
            key: const ValueKey('pe_borrow_cancel'),
            onPressed: _submitting ? null : () => Navigator.of(context).pop(),
            child: Text(bt(context, 'pe_borrow_cancel')),
          ),
          FilledButton(
            key: const ValueKey('pe_borrow_confirm'),
            onPressed: _submitting ? null : _submit,
            child: Text(
              bt(context, _submitting ? 'pe_borrow_sending' : 'pe_borrow'),
            ),
          ),
        ],
      ),
    );
  }
}
