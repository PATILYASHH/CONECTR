import 'package:flutter/material.dart';

/// An offline-first app Connector can be the online half of.
class LinkedApp {
  const LinkedApp({
    required this.id,
    required this.name,
    required this.tagline,
    required this.icon,
    required this.available,
  });

  final String id;
  final String name;
  final String tagline;
  final IconData icon;

  /// False while the app is still on the way — shown as "Coming soon".
  final bool available;
}

class AppCatalog {
  static const xpenc = LinkedApp(
    id: 'xpenc',
    name: 'XPENC',
    tagline: 'Offline money manager',
    icon: Icons.account_balance_wallet_outlined,
    available: true,
  );

  static const fitns = LinkedApp(
    id: 'fitns',
    name: 'FITNS',
    tagline: 'Fitness app',
    icon: Icons.fitness_center,
    available: false,
  );

  static const planr = LinkedApp(
    id: 'planr',
    name: 'PLANR',
    tagline: 'Planner app',
    icon: Icons.event_note_outlined,
    available: false,
  );

  static const all = [xpenc, fitns, planr];
  static final available = [
    for (final a in all)
      if (a.available) a,
  ];
  static final comingSoon = [
    for (final a in all)
      if (!a.available) a,
  ];
}
