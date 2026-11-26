/// One `shared_entries` row (see
/// `supabase/migrations/20261105000001_shared_entries.sql`): "[owedBy] owes
/// [owedTo] this much", proposed by [createdBy], accepted or rejected by
/// the other side.
class SharedEntry {
  const SharedEntry({
    required this.id,
    required this.createdBy,
    required this.clientRef,
    required this.owedBy,
    required this.owedTo,
    required this.amountMinor,
    required this.currency,
    required this.entryDate,
    this.dueDate,
    this.note,
    this.isOpening = false,
    required this.status,
    required this.version,
    required this.updatedAt,
  });

  factory SharedEntry.fromJson(Map<String, dynamic> json) => SharedEntry(
    id: json['id'] as String,
    createdBy: json['created_by'] as String,
    clientRef: json['client_ref'] as String,
    owedBy: json['owed_by'] as String,
    owedTo: json['owed_to'] as String,
    amountMinor: (json['amount_minor'] as num).toInt(),
    currency: json['currency'] as String,
    entryDate: json['entry_date'] as String,
    dueDate: json['due_date'] as String?,
    note: json['note'] as String?,
    isOpening: json['is_opening'] as bool? ?? false,
    status: json['status'] as String,
    version: (json['version'] as num).toInt(),
    updatedAt: DateTime.parse(json['updated_at'] as String),
  );

  final String id;
  final String createdBy;
  final String clientRef;
  final String owedBy;
  final String owedTo;
  final int amountMinor;
  final String currency;

  /// `yyyy-mm-dd`, as Postgres sends a `date`.
  final String entryDate;
  final String? dueDate;
  final String? note;
  final bool isOpening;

  /// `pending`, `accepted` or `rejected`.
  final String status;
  final int version;
  final DateTime updatedAt;

  String otherThan(String myId) => owedBy == myId ? owedTo : owedBy;

  /// The shape XPENC reads, seen from [myId]'s side: who the friend is,
  /// whether they owe, and whether this phone's account made it. XPENC
  /// never sees anyone else's ids. Version 1 of
  /// `XPENC/lib/core/connector/shared/shared_snapshot.dart`.
  Map<String, dynamic> toWire(String myId) {
    final byMe = createdBy == myId;
    return {
      'id': id,
      'friendId': otherThan(myId),
      'byMe': byMe,
      // Only the creator's own phone needs it: it names its local entry.
      'clientRef': byMe ? clientRef : null,
      'theyOwe': owedTo == myId,
      'amountMinor': amountMinor,
      'currency': currency,
      'date': entryDate,
      'dueDate': dueDate,
      'note': note,
      'isOpening': isOpening,
      'status': status,
      'version': version,
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    };
  }
}

/// What XPENC asked to have sent, as XpencProvider wrote it down (one file
/// per op in `xpenc/outbox/`). Applied in the order they were made.
sealed class SharedOp {
  const SharedOp(this.opId);

  final String opId;

  /// Null when the file isn't an op this version understands — set aside
  /// as failed rather than retried forever.
  static SharedOp? fromJson(Map<String, dynamic> json) {
    final opId = json['opId'];
    if (opId is! String || opId.isEmpty) return null;
    try {
      return switch (json['type']) {
        'add' => AddOp(
          opId,
          clientRef: json['clientRef'] as String,
          friendId: json['friendId'] as String,
          fields: EntryFields.fromJson(json),
          isOpening: json['isOpening'] as bool? ?? false,
        ),
        'edit' => EditOp(
          opId,
          clientRef: json['clientRef'] as String,
          fields: EntryFields.fromJson(json),
        ),
        'delete' => DeleteOp(opId, clientRef: json['clientRef'] as String),
        'respond' => RespondOp(
          opId,
          entryId: json['entryId'] as String,
          accept: json['accept'] as bool,
          version: (json['version'] as num).toInt(),
        ),
        _ => null,
      };
    } on TypeError {
      return null;
    }
  }

  /// The local entry it's about, for XPENC to show a failure against.
  Map<String, dynamic> describe();
}

/// The fields a creator sets, from their own side.
class EntryFields {
  const EntryFields({
    required this.theyOwe,
    required this.amountMinor,
    required this.currency,
    required this.date,
    this.dueDate,
    this.note,
  });

  factory EntryFields.fromJson(Map<String, dynamic> json) => EntryFields(
    theyOwe: json['theyOwe'] as bool,
    amountMinor: (json['amountMinor'] as num).toInt(),
    currency: json['currency'] as String,
    date: json['date'] as String,
    dueDate: json['dueDate'] as String?,
    note: json['note'] as String?,
  );

  final bool theyOwe;
  final int amountMinor;
  final String currency;
  final String date;
  final String? dueDate;
  final String? note;

  Map<String, dynamic> toParams() => {
    'p_they_owe': theyOwe,
    'p_amount_minor': amountMinor,
    'p_currency': currency,
    'p_entry_date': date,
    'p_due_date': dueDate,
    'p_note': note,
  };
}

class AddOp extends SharedOp {
  const AddOp(
    super.opId, {
    required this.clientRef,
    required this.friendId,
    required this.fields,
    this.isOpening = false,
  });

  final String clientRef;
  final String friendId;
  final EntryFields fields;
  final bool isOpening;

  @override
  Map<String, dynamic> describe() => {'type': 'add', 'clientRef': clientRef};
}

class EditOp extends SharedOp {
  const EditOp(super.opId, {required this.clientRef, required this.fields});

  final String clientRef;
  final EntryFields fields;

  @override
  Map<String, dynamic> describe() => {'type': 'edit', 'clientRef': clientRef};
}

class DeleteOp extends SharedOp {
  const DeleteOp(super.opId, {required this.clientRef});

  final String clientRef;

  @override
  Map<String, dynamic> describe() => {
    'type': 'delete',
    'clientRef': clientRef,
  };
}

class RespondOp extends SharedOp {
  const RespondOp(
    super.opId, {
    required this.entryId,
    required this.accept,
    required this.version,
  });

  final String entryId;
  final bool accept;
  final int version;

  @override
  Map<String, dynamic> describe() => {
    'type': 'respond',
    'entryId': entryId,
    'accept': accept,
  };
}
