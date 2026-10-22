import 'package:flutter/material.dart';

import '../../core/url_utils.dart';
import '../../state/browser_tab.dart';

/// Barre d'adresse : affiche le site, permet de taper une adresse ou une recherche.
class AddressBar extends StatefulWidget {
  const AddressBar({
    super.key,
    required this.tab,
    required this.onSubmit,
    required this.onReloadOrStop,
  });

  final BrowserTab tab;
  final ValueChanged<String> onSubmit;
  final VoidCallback onReloadOrStop;

  @override
  State<AddressBar> createState() => _AddressBarState();
}

class _AddressBarState extends State<AddressBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
    widget.tab.addListener(_onTabChanged);
    _controller.text = _shortUrl(widget.tab.url);
  }

  @override
  void didUpdateWidget(AddressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tab != widget.tab) {
      oldWidget.tab.removeListener(_onTabChanged);
      widget.tab.addListener(_onTabChanged);
      _focus.unfocus();
      _controller.text = _shortUrl(widget.tab.url);
    }
  }

  @override
  void dispose() {
    widget.tab.removeListener(_onTabChanged);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Sans focus : adresse courte (« site.com/page ») ; avec focus : adresse complète.
  static String _shortUrl(String url) => url.isEmpty ? '' : UrlUtils.displayUrl(url);

  /// L'onglet a changé (URL, chargement, compteur de pubs…).
  void _onTabChanged() {
    if (!mounted) return;
    setState(() {
      // Ne pas écraser ce que l'utilisateur est en train de taper
      if (!_focus.hasFocus) _controller.text = _shortUrl(widget.tab.url);
    });
  }

  void _onFocusChanged() {
    setState(() {
      if (_focus.hasFocus) {
        _controller.text = widget.tab.url;
        _controller.selection =
            TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
      } else {
        _controller.text = _shortUrl(widget.tab.url);
      }
    });
  }

  void _submit(String value) {
    _focus.unfocus();
    if (value.trim().isNotEmpty) widget.onSubmit(value);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final BrowserTab tab = widget.tab;
    final bool secure = tab.url.startsWith('https://');

    final Widget leading = tab.isPrivate
        ? Icon(Icons.privacy_tip_outlined, size: 20, color: scheme.tertiary)
        : Icon(
            tab.url.isEmpty ? Icons.search : (secure ? Icons.lock_outline : Icons.lock_open),
            size: 18,
            color: tab.url.isEmpty || secure ? scheme.onSurfaceVariant : scheme.error,
          );

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              autocorrect: false,
              onSubmitted: _submit,
              decoration: InputDecoration(
                hintText: 'Rechercher ou saisir une adresse',
                prefixIcon: Padding(padding: const EdgeInsets.all(10), child: leading),
                prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                suffixIcon: _focus.hasFocus
                    ? IconButton(
                        tooltip: 'Effacer',
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: _controller.clear,
                      )
                    : null,
              ),
            ),
          ),
          if (!_focus.hasFocus && !tab.isStartPage) ...[
            if (tab.blockedCount > 0) _BlockedBadge(count: tab.blockedCount),
            IconButton(
              tooltip: tab.isLoading ? 'Arrêter' : 'Actualiser',
              icon: Icon(tab.isLoading ? Icons.close : Icons.refresh),
              onPressed: widget.onReloadOrStop,
            ),
          ],
        ],
      ),
    );
  }
}

/// Bouclier indiquant le nombre de publicités bloquées sur la page.
class _BlockedBadge extends StatelessWidget {
  const _BlockedBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: '$count publicités et traqueurs bloqués',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('🛡️ $count publicités et traqueurs bloqués sur cette page')),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.shield_outlined, size: 18, color: scheme.primary),
              const SizedBox(width: 2),
              Text(
                count > 99 ? '99+' : '$count',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
