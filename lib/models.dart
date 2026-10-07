const kAccountIds = ['acc1', 'acc2', 'acc3'];

class AccountResult {
  AccountResult({
    required this.id,
    required this.name,
    required this.status, // success | timeout | failed | relogin
    required this.step,
    this.note,
    required this.at,
  });

  final String id;
  final String name;
  final String status;
  final String step;
  final String? note;
  final DateTime at;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'status': status,
        'step': step,
        'note': note,
        'at': at.toIso8601String(),
      };

  factory AccountResult.fromJson(Map<String, dynamic> j) => AccountResult(
        id: j['id'] as String,
        name: j['name'] as String,
        status: j['status'] as String,
        step: j['step'] as String,
        note: j['note'] as String?,
        at: DateTime.parse(j['at'] as String),
      );
}

class RunRecord {
  RunRecord({
    required this.startedAt,
    required this.source,
    required this.isTest,
    List<AccountResult>? results,
  }) : results = results ?? [];

  final DateTime startedAt;
  final String source;
  final bool isTest;
  final List<AccountResult> results;

  int get okCount => results.where((r) => r.status == 'success').length;

  Map<String, dynamic> toJson() => {
        'startedAt': startedAt.toIso8601String(),
        'source': source,
        'isTest': isTest,
        'results': results.map((r) => r.toJson()).toList(),
      };

  factory RunRecord.fromJson(Map<String, dynamic> j) => RunRecord(
        startedAt: DateTime.parse(j['startedAt'] as String),
        source: j['source'] as String,
        isTest: j['isTest'] as bool,
        results: (j['results'] as List)
            .map((e) => AccountResult.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
