import 'dart:math' as math;

/// Dart port of the backend `rules-v1` classifier.
///
/// The rules, category order, score cap, confidence formula, and extracted
/// fields intentionally mirror `app/services/organization.py`. Keep both in
/// sync when the server classifier changes; parity tests load fixtures
/// generated from the Python implementation.
const List<String> classifierCategories = <String>[
  'Finance',
  'Education',
  'Health',
  'Identity',
  'Home',
  'Appliances',
  'Insurance',
  'Travel',
  'Work',
  'Legal',
  'Uncategorized',
];

const String classifierMethod = 'rules-v1';

const Map<String, List<String>> _categoryTerms = <String, List<String>>{
  'Finance': <String>[
    'invoice',
    'receipt',
    'bank statement',
    'account statement',
    'transaction',
    'balance due',
    'payment due',
    'tax return',
    'credit card',
    'debit card',
    'purchase order',
    'amount due',
    'subtotal',
    'routing number',
  ],
  'Education': <String>[
    'transcript',
    'student',
    'university',
    'school',
    'semester',
    'course',
    'enrollment',
    'tuition',
    'grade report',
    'diploma',
    'academic',
  ],
  'Health': <String>[
    'medical',
    'patient',
    'prescription',
    'diagnosis',
    'physician',
    'clinic',
    'hospital',
    'laboratory',
    'lab result',
    'health record',
    'dosage',
  ],
  'Identity': <String>[
    'passport',
    'driver license',
    'driving licence',
    'identity card',
    'social security',
    'birth certificate',
    'national id',
    'residence permit',
  ],
  'Home': <String>[
    'lease agreement',
    'rental agreement',
    'mortgage',
    'landlord',
    'tenant',
    'property deed',
    'utility bill',
    'electricity bill',
    'water bill',
    'rent',
  ],
  'Appliances': <String>[
    'appliance',
    'serial number',
    'model number',
    'user manual',
    'installation guide',
    'warranty card',
    'refrigerator',
    'washing machine',
    'dishwasher',
  ],
  'Insurance': <String>[
    'insurance',
    'policy number',
    'premium',
    'insured',
    'coverage',
    'claim number',
    'beneficiary',
    'deductible',
    'underwriter',
  ],
  'Travel': <String>[
    'boarding pass',
    'itinerary',
    'flight',
    'airline',
    'hotel reservation',
    'booking confirmation',
    'train ticket',
    'departure',
    'arrival',
    'reservation',
  ],
  'Work': <String>[
    'employment',
    'employer',
    'employee',
    'pay stub',
    'payslip',
    'salary',
    'job offer',
    'performance review',
    'timesheet',
    'payroll',
    'workplace',
  ],
  'Legal': <String>[
    'agreement',
    'contract',
    'court',
    'legal notice',
    'attorney',
    'law firm',
    'affidavit',
    'non-disclosure',
    'terms and conditions',
    'statute',
  ],
  'Uncategorized': <String>[],
};

const List<(String, List<String>)> _documentTypes = <(String, List<String>)>[
  ('invoice', <String>['invoice', 'amount due', 'bill to']),
  ('receipt', <String>['receipt', 'transaction', 'purchase']),
  ('bank statement', <String>['bank statement', 'account statement']),
  (
    'insurance policy',
    <String>['insurance policy', 'policy number', 'coverage'],
  ),
  ('transcript', <String>['transcript', 'grade report']),
  ('medical record', <String>['medical record', 'patient', 'diagnosis']),
  (
    'identity document',
    <String>['passport', 'identity card', 'driver license', 'birth certificate'],
  ),
  ('lease', <String>['lease agreement', 'rental agreement', 'tenant']),
  ('warranty', <String>['warranty', 'serial number']),
  ('travel itinerary', <String>['itinerary', 'boarding pass', 'flight']),
  (
    'employment document',
    <String>['employment', 'pay stub', 'payslip', 'job offer'],
  ),
  ('contract', <String>['contract', 'agreement', 'legal notice']),
];

const String _monthNames =
    'January|February|March|April|May|June|July|August|September|October|November|December';

final List<RegExp> _datePatterns = <RegExp>[
  RegExp(
    r'(?<![\p{L}\p{N}_])(20\d{2}|19\d{2})-(\d{1,2})-(\d{1,2})(?![\p{L}\p{N}_])',
    unicode: true,
  ),
  RegExp(
    '(?<![\\p{L}\\p{N}_])($_monthNames)'
    r'\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+((?:19|20)\d{2})(?![\p{L}\p{N}_])',
    caseSensitive: false,
    unicode: true,
  ),
  RegExp(
    '(?<![\\p{L}\\p{N}_])(\\d{1,2})\\s+($_monthNames)'
    r'\s+((?:19|20)\d{2})(?![\p{L}\p{N}_])',
    caseSensitive: false,
    unicode: true,
  ),
  RegExp(
    r'(?<![\p{L}\p{N}_])(\d{1,2})[./-](\d{1,2})[./-]((?:19|20)\d{2})(?![\p{L}\p{N}_])',
    unicode: true,
  ),
];

final Map<String, int> _months = <String, int>{
  for (var index = 0; index < _monthNames.split('|').length; index++)
    _monthNames.split('|')[index].toLowerCase(): index + 1,
};

final List<RegExp> _referencePatterns = <RegExp>[
  RegExp(
    r'(?<![\p{L}\p{N}_])(?:invoice|policy|reference|ref|claim|account|order)'
    r'\s*(?:no\.?|number|#)\s*[:#-]?\s*([A-Z0-9][A-Z0-9/-]{2,39})(?![\p{L}\p{N}_])',
    caseSensitive: false,
    unicode: true,
  ),
];

final List<RegExp> _issuerPatterns = <RegExp>[
  RegExp(
    r'^\s*(?:issued by|issuer|from)\s*:\s*(.{2,100})\s*$',
    caseSensitive: false,
    unicode: true,
    multiLine: true,
  ),
  RegExp(
    r'^\s*(?:prepared by|provided by)\s*:\s*(.{2,100})\s*$',
    caseSensitive: false,
    unicode: true,
    multiLine: true,
  ),
];

class DocumentClassification {
  const DocumentClassification({
    required this.category,
    required this.confidence,
    required this.reasons,
    required this.method,
    required this.tags,
    this.documentTitle,
    this.documentType,
    this.documentDate,
    this.issuer,
    this.referenceNumber,
  });

  final String category;
  final double confidence;
  final List<String> reasons;
  final String method;
  final String? documentTitle;
  final String? documentType;
  final DateTime? documentDate;
  final String? issuer;
  final String? referenceNumber;
  final List<String> tags;
}

class DocumentClassifier {
  const DocumentClassifier();

  DocumentClassification classify({
    required String filename,
    String? extractedText,
    List<String> existingTags = const <String>[],
  }) {
    final text = extractedText ?? '';
    final source = '$filename\n$text';
    final scores = <String, int>{};
    final reasonsByCategory = <String, List<String>>{};

    for (final category in classifierCategories) {
      if (category == 'Uncategorized') {
        continue;
      }
      final matched = _categoryTerms[category]!
          .where((term) => _termMatches(source, term))
          .toList(growable: false);
      if (matched.isNotEmpty) {
        scores[category] = math.min(6, matched.length);
        reasonsByCategory[category] = matched
            .take(3)
            .map((term) => "Matched '$term'")
            .toList(growable: false);
      }
    }

    String category;
    double confidence;
    List<String> reasons;
    if (scores.isNotEmpty) {
      category = classifierCategories.firstWhere(
        (candidate) =>
            scores[candidate] ==
            scores.values.reduce((left, right) => math.max(left, right)),
      );
      final score = scores[category]!;
      confidence = math.min(0.95, 0.55 + 0.1 * score);
      reasons = List<String>.from(reasonsByCategory[category]!);
      if (scores.length > 1) {
        reasons.add('Selected the category with the strongest rule score');
      }
    } else {
      category = 'Uncategorized';
      confidence = 0.0;
      reasons = <String>['No category-specific indicators were found'];
    }

    final documentType = _extractDocumentType(source);
    final documentDate = _parseDate(text);
    final issuer = _extractIssuer(text);
    final referenceNumber = _extractReference(text);
    final tags = List<String>.from(existingTags);
    if (category != 'Uncategorized' &&
        !tags
            .map((tag) => tag.toLowerCase())
            .contains(category.toLowerCase())) {
      tags.insert(0, category);
    }
    if (documentType != null &&
        !tags
            .map((tag) => tag.toLowerCase())
            .contains(documentType.toLowerCase())) {
      tags.add(documentType);
    }

    return DocumentClassification(
      category: category,
      confidence: confidence,
      reasons: reasons,
      method: classifierMethod,
      documentTitle: _extractTitle(filename, text),
      documentType: documentType,
      documentDate: documentDate,
      issuer: issuer,
      referenceNumber: referenceNumber,
      tags: tags.take(20).toList(growable: false),
    );
  }

  bool _termMatches(String source, String term) {
    final escaped = term
        .split(RegExp(r'\s+'))
        .map(RegExp.escape)
        .join(r'\s+');
    final pattern =
        r'(?<![\p{L}\p{N}_])' + escaped + r'(?![\p{L}\p{N}_])';
    return RegExp(
      pattern,
      caseSensitive: false,
      unicode: true,
    ).hasMatch(source);
  }

  DateTime? _parseDate(String source) {
    for (var index = 0; index < _datePatterns.length; index++) {
      final match = _datePatterns[index].firstMatch(source);
      if (match == null) {
        continue;
      }
      final groups = match.groups(<int>[1, 2, 3]);
      try {
        DateTime? parsed;
        if (index == 0) {
          parsed = _checkedDate(
            int.parse(groups[0]!),
            int.parse(groups[1]!),
            int.parse(groups[2]!),
          );
        } else if (index == 1) {
          parsed = _checkedDate(
            int.parse(groups[2]!),
            _months[groups[0]!.toLowerCase()]!,
            int.parse(groups[1]!),
          );
        } else if (index == 2) {
          parsed = _checkedDate(
            int.parse(groups[2]!),
            _months[groups[1]!.toLowerCase()]!,
            int.parse(groups[0]!),
          );
        } else {
          final first = int.parse(groups[0]!);
          final second = int.parse(groups[1]!);
          final year = int.parse(groups[2]!);
          if (first <= 12 && second <= 12) {
            continue;
          }
          final day = first > 12 ? first : second;
          final month = first > 12 ? second : first;
          parsed = _checkedDate(year, month, day);
        }
        if (parsed != null) {
          return parsed;
        }
      } on ArgumentError {
        continue;
      } on FormatException {
        continue;
      }
    }
    return null;
  }

  DateTime? _checkedDate(int year, int month, int day) {
    if (year < 1 || year > 9999) {
      return null;
    }
    final value = DateTime(year, month, day);
    if (value.year != year || value.month != month || value.day != day) {
      return null;
    }
    return value;
  }

  String? _extractDocumentType(String source) {
    for (final (label, terms) in _documentTypes) {
      if (terms.any((term) => _termMatches(source, term))) {
        return label;
      }
    }
    return null;
  }

  String? _extractIssuer(String source) {
    for (final pattern in _issuerPatterns) {
      final match = pattern.firstMatch(source);
      if (match != null) {
        final value = match.group(1)!.trim();
        return value.length > 255 ? value.substring(0, 255) : value;
      }
    }
    return null;
  }

  String? _extractReference(String source) {
    for (final pattern in _referencePatterns) {
      final match = pattern.firstMatch(source);
      if (match != null) {
        final value = match.group(1)!;
        return value.length > 100 ? value.substring(0, 100) : value;
      }
    }
    return null;
  }

  String? _extractTitle(String filename, String text) {
    final lines = text.split(
      RegExp(r'\r\n|[\n\r\v\f\x85\u2028\u2029]', unicode: true),
    );
    for (final line in lines) {
      final candidate = line
          .split(RegExp(r'\s+', unicode: true))
          .where((part) => part.isNotEmpty)
          .join(' ')
          .replaceAll(RegExp(r'^[ \-_]+|[ \-_]+$'), '');
      if (candidate.isNotEmpty &&
          candidate.length <= 120 &&
          _parseDate(candidate) == null) {
        return candidate;
      }
    }
    final dotIndex = filename.lastIndexOf('.');
    final stem = (dotIndex >= 0 ? filename.substring(0, dotIndex) : filename)
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .trim();
    if (stem.isEmpty) {
      return null;
    }
    return stem.length > 120 ? stem.substring(0, 120) : stem;
  }
}

String dateOnlyIso8601(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year.toString().padLeft(4, '0')}-$month-$day';
}
