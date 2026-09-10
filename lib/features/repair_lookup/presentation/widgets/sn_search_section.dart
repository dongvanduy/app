import 'package:flutter/material.dart';
import '../../../pe_system/presentation/widgets/business_widgets.dart';
import 'lookup_widgets.dart';

class SnSearchSection extends StatefulWidget {
  const SnSearchSection({
    super.key,
    required this.controller,
    required this.onSearch,
    required this.onScan,
  });
  final TextEditingController controller;
  final ValueChanged<String> onSearch;
  final VoidCallback onScan;
  @override
  State<SnSearchSection> createState() => _SnSearchSectionState();
}

class _SnSearchSectionState extends State<SnSearchSection> {
  final _form = GlobalKey<FormState>();
  final _focusNode = FocusNode();

  void _submit() {
    if (!_form.currentState!.validate()) return;
    widget.onSearch(widget.controller.text);
    // The lookup callback can trim the SN and update the controller
    // synchronously. Select its final value so the next scan replaces it.
    _focusNode.requestFocus();
    widget.controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.controller.text.length,
    );
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LookupCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Form(
          key: _form,
          child: TextFormField(
            key: const ValueKey('lookup-sn-input'),
            controller: widget.controller,
            focusNode: _focusNode,
            textInputAction: TextInputAction.search,
            autocorrect: false,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            enableSuggestions: false,
            validator:
                (value) =>
                    value == null || value.trim().isEmpty
                        ? bt(context, 'lookup_sn_required')
                        : null,
            // Keep the input focused when the keyboard submits the SN.
            onEditingComplete: () {},
            onFieldSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              hintText: bt(context, 'lookup_enter_sn'),
              prefixIcon: IconButton(
                key: const ValueKey('lookup-search'),
                tooltip: bt(context, 'lookup_search'),
                onPressed: _submit,
                icon: const Icon(Icons.search),
              ),
              suffixIcon: IconButton(
                key: const ValueKey('lookup-camera'),
                tooltip: bt(context, 'lookup_scan'),
                onPressed: widget.onScan,
                icon: const Icon(Icons.qr_code_scanner),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
