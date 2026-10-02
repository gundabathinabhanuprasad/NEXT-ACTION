// Phase 19 Scheduler Models for Automated Evaluation & Diagnostic Metrics

class CategoryEvaluationDetail {
  final int evaluated;
  final int notificationsCreated;
  final int duplicatesSkipped;
  final int preferencesSuppressed;
  final int errors;

  const CategoryEvaluationDetail({
    required this.evaluated,
    required this.notificationsCreated,
    required this.duplicatesSkipped,
    required this.preferencesSuppressed,
    required this.errors,
  });

  factory CategoryEvaluationDetail.fromJson(Map<String, dynamic> json) {
    return CategoryEvaluationDetail(
      evaluated: json['evaluated'] as int? ?? 0,
      notificationsCreated: json['notifications_created'] as int? ?? 0,
      duplicatesSkipped: json['duplicates_skipped'] as int? ?? 0,
      preferencesSuppressed: json['preferences_suppressed'] as int? ?? 0,
      errors: json['errors'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'evaluated': evaluated,
        'notifications_created': notificationsCreated,
        'duplicates_skipped': duplicatesSkipped,
        'preferences_suppressed': preferencesSuppressed,
        'errors': errors,
      };
}

class SchedulerEvaluationResponse {
  final int evaluated;
  final int notificationsCreated;
  final int duplicatesSkipped;
  final int preferencesSuppressed;
  final int errorsCount;
  final double durationMs;
  final DateTime evaluatedAt;
  final String? userId;
  final Map<String, CategoryEvaluationDetail> details;

  const SchedulerEvaluationResponse({
    required this.evaluated,
    required this.notificationsCreated,
    required this.duplicatesSkipped,
    required this.preferencesSuppressed,
    required this.errorsCount,
    required this.durationMs,
    required this.evaluatedAt,
    this.userId,
    required this.details,
  });

  factory SchedulerEvaluationResponse.fromJson(Map<String, dynamic> json) {
    final detailsMap = <String, CategoryEvaluationDetail>{};
    if (json['details'] is Map<String, dynamic>) {
      (json['details'] as Map<String, dynamic>).forEach((key, val) {
        if (val is Map<String, dynamic>) {
          detailsMap[key] = CategoryEvaluationDetail.fromJson(val);
        }
      });
    }

    return SchedulerEvaluationResponse(
      evaluated: json['evaluated'] as int? ?? 0,
      notificationsCreated: json['notifications_created'] as int? ?? 0,
      duplicatesSkipped: json['duplicates_skipped'] as int? ?? 0,
      preferencesSuppressed: json['preferences_suppressed'] as int? ?? 0,
      errorsCount: json['errors_count'] as int? ?? 0,
      durationMs: (json['duration_ms'] as num?)?.toDouble() ?? 0.0,
      evaluatedAt: json['evaluated_at'] != null
          ? DateTime.parse(json['evaluated_at'] as String)
          : DateTime.now(),
      userId: json['user_id'] as String?,
      details: detailsMap,
    );
  }

  Map<String, dynamic> toJson() => {
        'evaluated': evaluated,
        'notifications_created': notificationsCreated,
        'duplicates_skipped': duplicatesSkipped,
        'preferences_suppressed': preferencesSuppressed,
        'errors_count': errorsCount,
        'duration_ms': durationMs,
        'evaluated_at': evaluatedAt.toIso8601String(),
        'user_id': userId,
        'details': details.map((k, v) => MapEntry(k, v.toJson())),
      };
}
