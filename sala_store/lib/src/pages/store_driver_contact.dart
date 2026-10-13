part of sala_store;

/// Uses only the phone already disclosed by the authorized order projection.
class StoreDriverContact extends StatefulWidget {
  const StoreDriverContact({super.key, required this.phone, this.openLink});
  final String phone;
  final Future<bool> Function(Uri)? openLink;

  @override
  State<StoreDriverContact> createState() => _StoreDriverContactState();
}

class _StoreDriverContactState extends State<StoreDriverContact> {
  bool _opening = false;
  String _error = '';

  Future<void> _open(Uri uri) async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _error = '';
    });
    try {
      final opened =
          await (widget.openLink?.call(uri) ??
              launchUrl(uri, mode: LaunchMode.externalApplication));
      if (mounted && !opened) {
        setState(
          () => _error = 'تعذر فتح التطبيق. يمكنك نسخ رقم السائق أدناه.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'تعذر فتح التطبيق. يمكنك نسخ رقم السائق أدناه.',
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  void didUpdateWidget(covariant StoreDriverContact oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phone != widget.phone) _error = '';
  }

  @override
  Widget build(BuildContext context) {
    final phone = normalizeIraqiPhone(widget.phone);
    if (!RegExp(r'^\+9647[0-9]{9}$').hasMatch(phone)) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: _opening
                  ? null
                  : () => _open(Uri(scheme: 'tel', path: phone)),
              icon: const Icon(Icons.call_outlined, size: 18),
              label: Text(phone, textDirection: TextDirection.ltr),
            ),
            TextButton.icon(
              onPressed: _opening
                  ? null
                  : () => _open(Uri.https('wa.me', '/${phone.substring(1)}')),
              icon: const Icon(Icons.chat_outlined, size: 18),
              label: const Text('واتساب السائق'),
            ),
          ],
        ),
        if (_opening) const LinearProgressIndicator(minHeight: 2),
        if (_error.isNotEmpty) ...[
          Text(_error, style: const TextStyle(color: Colors.red)),
          SelectableText(phone, textDirection: TextDirection.ltr),
        ],
      ],
    );
  }
}
