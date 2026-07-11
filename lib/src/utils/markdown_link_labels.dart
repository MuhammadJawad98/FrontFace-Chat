/// Normalizes product CTA link labels in assistant Markdown so mobile and
/// web show the same copy (e.g. "View Listings" → "View Details").
///
/// The model sometimes emits different labels by channel; this keeps the
/// visible link text consistent while preserving the href.
String normalizeMarkdownDetailLinkLabels(
  String markdown, {
  required String viewDetailsLabel,
}) {
  if (markdown.isEmpty) return markdown;

  return markdown.replaceAllMapped(_markdownLinkPattern, (match) {
    final label = match.group(1)!;
    final href = match.group(2)!;
    if (!_isViewDetailsVariant(label)) return match.group(0)!;
    return '[$viewDetailsLabel]($href)';
  });
}

final _markdownLinkPattern = RegExp(
  r'\[([^\]]+)\]\(([^)\s]+)\)',
);

bool _isViewDetailsVariant(String label) {
  final normalized = label.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  const english = {
    'view details',
    'view detail',
    'view listings',
    'view listing',
    'see details',
    'see detail',
    'see listings',
    'see listing',
    'more details',
    'show details',
  };
  if (english.contains(normalized)) return true;

  // Strip Arabic diacritics / tatweel for stable matching.
  final arabic = label
      .trim()
      .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '')
      .replaceAll(RegExp(r'\s+'), ' ');

  const arabicLabels = {
    'عرض التفاصيل',
    'عرض تفاصيل',
    'عرض القوائم',
    'عرض القائمة',
    'عرض القائمه',
    'رؤية التفاصيل',
    'مشاهدة التفاصيل',
    'شاهد التفاصيل',
    'التفاصيل',
    'تفاصيل',
  };
  return arabicLabels.contains(arabic);
}
