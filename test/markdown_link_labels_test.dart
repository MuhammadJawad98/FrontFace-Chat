import 'package:flutter_test/flutter_test.dart';
import 'package:frontface_chat/src/utils/markdown_link_labels.dart';

void main() {
  group('normalizeMarkdownDetailLinkLabels', () {
    test('rewrites View Listings to View Details', () {
      const input =
          '1. **Car**\n   - [View Listings](https://onego.tech/cars/1)';
      final out = normalizeMarkdownDetailLinkLabels(
        input,
        viewDetailsLabel: 'View Details',
      );
      expect(out, contains('[View Details](https://onego.tech/cars/1)'));
      expect(out, isNot(contains('View Listings')));
    });

    test('keeps href when label is already View Details', () {
      const input = '[View Details](https://onego.tech/cars/2)';
      final out = normalizeMarkdownDetailLinkLabels(
        input,
        viewDetailsLabel: 'View Details',
      );
      expect(out, input);
    });

    test('does not rewrite unrelated links', () {
      const input = 'See our [privacy policy](https://example.com/privacy)';
      final out = normalizeMarkdownDetailLinkLabels(
        input,
        viewDetailsLabel: 'View Details',
      );
      expect(out, input);
    });

    test('rewrites Arabic listing CTAs to عرض التفاصيل', () {
      const input = '[عرض القوائم](https://onego.tech/cars/3)';
      final out = normalizeMarkdownDetailLinkLabels(
        input,
        viewDetailsLabel: 'عرض التفاصيل',
      );
      expect(out, '[عرض التفاصيل](https://onego.tech/cars/3)');
    });

    test('rewrites multiple car links in one reply', () {
      const input = '''
1. **Mercedes G-Class**
   - [View Listings](https://onego.tech/cars/124)
2. **Mercedes E-Class**
   - [View Listing](https://onego.tech/cars/123)
''';
      final out = normalizeMarkdownDetailLinkLabels(
        input,
        viewDetailsLabel: 'View Details',
      );
      expect(
        out,
        contains('[View Details](https://onego.tech/cars/124)'),
      );
      expect(
        out,
        contains('[View Details](https://onego.tech/cars/123)'),
      );
    });
  });
}
