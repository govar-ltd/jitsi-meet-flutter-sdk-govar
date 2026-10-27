import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_govar_foreground_service/call_notification.dart';

void main() {
  test('covers all Govar interface languages with notification title and body', () {
    const languages = ['en','ru','ar','es','kk','fr','it','ms','hi','ur','de','id','pt','uk','zh','fa','tr','am','vi','ne','uz','bn','pl','be','ro','hy','cs','tg','ko','ka','hu','ja','bg','sv','he','fi','sk','el'];
    expect(GovarCallNotification.translations.keys.toSet(), languages.toSet());
    for (final language in languages) {
      final text = GovarCallNotification.forLanguage(language);
      expect(text.length, 2);
      expect(text.every((s) => s.trim().isNotEmpty), isTrue);
      expect(text[0], startsWith('Govar'));
    }
  });
  test('selected interface locale overrides device language and normalizes regions', () {
    expect(GovarCallNotification.forLanguage('ru-RU'), GovarCallNotification.translations['ru']);
    expect(GovarCallNotification.forLanguage('pt_BR'), GovarCallNotification.translations['pt']);
    expect(GovarCallNotification.forLanguage('unknown'), GovarCallNotification.translations['en']);
  });
}
