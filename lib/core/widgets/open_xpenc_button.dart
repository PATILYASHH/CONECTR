import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/xpenc_launcher.dart';
import '../providers.dart';

/// App-bar shortcut to XPENC. Hidden when XPENC isn't on this phone.
class OpenXpencButton extends ConsumerWidget {
  const OpenXpencButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final installed = ref.watch(xpencInstalledProvider).value ?? false;
    if (!installed) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: TextButton.icon(
        onPressed: () => openXpenc(context),
        icon: const Icon(Icons.open_in_new, size: 18),
        label: const Text('Open XPENC'),
      ),
    );
  }
}

Future<void> openXpenc(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final opened = await XpencLauncher.open().catchError((Object _) => false);
  if (opened) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(content: Text("Couldn't open XPENC.")));
}
