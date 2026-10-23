import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../core/url_utils.dart';
import '../../services/adblock/adblock_service.dart';
import '../../services/settings_service.dart';
import '../../state/browser_tab.dart';
import 'adblock_sheet.dart';

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
            _ShieldButton(tab: tab),
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

/// Bouclier : nombre de publicités bloquées sur la page ; barré si le site
/// est autorisé. Toucher ouvre [AdblockSheet].
class _ShieldButton extends StatelessWidget {
  const _ShieldButton({required this.tab});

  final BrowserTab tab;

  @override
  Widget build(BuildContext context) {
    final AppScope scope = AppScope.of(context);
    final SettingsService settings = scope.settings;
    final AdblockService adblock = scope.adblock;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: Listenable.merge([settings, adblock.exceptions]),
      builder: (BuildContext context, _) {
        if (!settings.adblockEnabled || tab.site.isEmpty) return const SizedBox.shrink();
        final bool active = adblock.isActiveOn(tab.site);
        final int count = tab.blockedCount;
        final Color color = active ? scheme.primary : scheme.outline;
        return Tooltip(
          message: active ? '$count publicités et traqueurs bloqués' : 'Bloqueur désactivé sur ce site',
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => AdblockSheet.show(context, tab),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(active ? Icons.shield_outlined : Icons.remove_moderator_outlined, size: 18, color: color),
                  if (active && count > 0) ...[
                    const SizedBox(width: 2),
                    Text(
                      count > 99 ? '99+' : '$count',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
