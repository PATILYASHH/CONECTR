import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../core/backup/backup_sync_service.dart';
import '../../core/backup/import_links.dart';
import '../../core/backup/sync_failure.dart';
import '../../core/backup/sync_lock.dart';
import '../../core/providers.dart';
import '../connections/connections_screen.dart';
import '../home/home_tab.dart';
import 'backup_controller.dart';

/// Answers XPENC's "Tell Connector" link (see [ImportLinks]) for as long as
/// the app runs — whether the link opened Connector or found it open — by
/// confirming the import it names, then showing XPENC's connection page and
/// why.
void listenForImportLinks(ProviderContainer container) {
  final links = AppLinks();
  String? last;

  Future<void> handle(Uri uri) async {
    if (!ImportLinks.matches(uri)) return;
    // A link that launched the app may also arrive on the stream.
    if (uri.toString() == last) return;
    last = uri.toString();

    // Cold start: let sign-in settle first, or the account's tabs reset
    // over the one picked below.
    await container.read(authStateProvider.future);
    final sha = ImportLinks.shaOf(uri);
    String message;
    try {
      final result = sha == null
          ? ImportHandoff.differentFile
          : await SyncLock.run(
              () => container
                  .read(backupSyncServiceProvider)
                  .confirmImportedFile(sha),
              wait: const Duration(minutes: 1),
            );
      message = ImportLinks.message(result);
    } catch (e) {
      message = SyncFailure.from(e).message;
    }

    container.read(homeTabProvider.notifier).select(HomeTab.connections);
    _showXpencPage(container);
    if (container.exists(backupControllerProvider)) {
      await container.read(backupControllerProvider.notifier).refresh();
    }
    await WidgetsBinding.instance.endOfFrame;
    appMessengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  links.uriLinkStream.listen(handle, onError: (Object _) {});
  links.getInitialLink().then((uri) {
    if (uri != null) handle(uri);
  }, onError: (Object _) {});
}

/// Opens XPENC's connection page on top of the tabs, unless it's already
/// showing. Only once signed in with a username — before that the tabs
/// aren't there to go back to.
void _showXpencPage(ProviderContainer container) {
  final navigator = appNavigatorKey.currentState;
  if (navigator == null) return;
  if (container.read(myProfileProvider).value == null) return;
  var showing = false;
  navigator.popUntil((route) {
    if (route.settings.name == xpencRouteName) showing = true;
    return showing || route.isFirst;
  });
  if (!showing) openXpencConnection(navigator).ignore();
}
