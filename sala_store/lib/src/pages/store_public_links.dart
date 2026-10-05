part of '../../main.dart';

/// Fixed public destinations; never attach a session, account ID or order data.
class StorePublicLinks extends StatefulWidget {
  const StorePublicLinks({
    super.key,
    this.compact = false,
    this.openLink,
    this.onRequestDeletion,
  });

  final bool compact;
  final Future<bool> Function(Uri)? openLink;
  final VoidCallback? onRequestDeletion;

  static final privacy = Uri.https('selafood.shop', '/privacy/');
  static final support = Uri.https('selafood.shop', '/support/');
  static final deletion = Uri.https('selafood.shop', '/account-deletion/');
  static final terms = Uri.https('selafood.shop', '/terms/');

  @override
  State<StorePublicLinks> createState() => _StorePublicLinksState();
}

class _StorePublicLinksState extends State<StorePublicLinks> {
  bool _opening = false;
  Uri? _failedLink;

  Future<void> _open(Uri uri) async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _failedLink = null;
    });
    try {
      final opened =
          await (widget.openLink?.call(uri) ??
              launchUrl(uri, mode: LaunchMode.externalApplication));
      if (mounted && !opened) setState(() => _failedLink = uri);
    } catch (_) {
      if (mounted) setState(() => _failedLink = uri);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Widget _link(String label, IconData icon, Uri uri) => TextButton.icon(
    onPressed: _opening ? null : () => _open(uri),
    icon: Icon(icon, size: 19),
    label: Text(label),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      if (!widget.compact) ...[
        const Text(
          'الخصوصية والمساعدة',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text(
          'اطّلع على استخدام بياناتك، وأرسل طلب حذف حسابك إلى الإدارة من التطبيق.',
          style: TextStyle(color: mutedText),
        ),
      ],
      Wrap(
        alignment: widget.compact ? WrapAlignment.center : WrapAlignment.start,
        spacing: 4,
        children: [
          _link(
            'سياسة الخصوصية',
            Icons.privacy_tip_outlined,
            StorePublicLinks.privacy,
          ),
          _link('الدعم', Icons.help_outline_rounded, StorePublicLinks.support),
          if (!widget.compact) ...[
            if (widget.onRequestDeletion != null)
              TextButton.icon(
                onPressed: _opening ? null : widget.onRequestDeletion,
                icon: const Icon(Icons.person_remove_outlined, size: 19),
                label: const Text('طلب حذف الحساب'),
              )
            else
              _link(
                'طلب حذف الحساب',
                Icons.person_remove_outlined,
                StorePublicLinks.deletion,
              ),
            _link(
              'شروط الاستخدام',
              Icons.description_outlined,
              StorePublicLinks.terms,
            ),
          ],
        ],
      ),
      if (_opening) const LinearProgressIndicator(minHeight: 2),
      if (_failedLink != null) ...[
        const Text(
          'تعذر فتح الصفحة. حاول مجدداً أو انسخ الرابط وافتحه في المتصفح.',
          style: TextStyle(color: Colors.red),
        ),
        SelectableText(
          _failedLink.toString(),
          textDirection: TextDirection.ltr,
        ),
        TextButton.icon(
          onPressed: () async {
            try {
              await Clipboard.setData(
                ClipboardData(text: _failedLink.toString()),
              );
            } catch (_) {
              // The selectable URL remains available if clipboard access fails.
            }
          },
          icon: const Icon(Icons.copy_rounded),
          label: const Text('نسخ الرابط'),
        ),
      ],
    ],
  );
}
