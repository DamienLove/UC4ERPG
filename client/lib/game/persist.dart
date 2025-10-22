import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'state.dart';

class Persist {
  static const _kPrefix = 'uc4e_';
  static const _kConsent = '${_kPrefix}consent';
  static const _kChapter = '${_kPrefix}chapter';
  static const _kSection = '${_kPrefix}section';
  static const _kQuest = '${_kPrefix}quest';
  static const _kSpoken = '${_kPrefix}spoken';

  static Future<void> save(GameState gs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kConsent, gs.consentGiven.value);
    await prefs.setString(_kChapter, gs.chapter.value);
    await prefs.setString(_kSection, gs.section.value);
    final q = gs.quest.value;
    await prefs.setString(
      _kQuest,
      jsonEncode({
        'id': q.id,
        'title': q.title,
        'items': q.items.map((e) => {'id': e.id, 'text': e.text, 'complete': e.complete}).toList(),
      }),
    );
    await prefs.setStringList(_kSpoken, gs.spokenTo.toList());
  }

  static Future<void> loadInto(GameState gs) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(_kConsent)) {
      gs.consentGiven.value = prefs.getBool(_kConsent) ?? false;
    }
    if (prefs.containsKey(_kChapter)) gs.chapter.value = prefs.getString(_kChapter) ?? gs.chapter.value;
    if (prefs.containsKey(_kSection)) gs.section.value = prefs.getString(_kSection) ?? gs.section.value;
    if (prefs.containsKey(_kQuest)) {
      try {
        final raw = jsonDecode(prefs.getString(_kQuest) ?? '{}');
        final items = (raw['items'] as List?)?.map((e) => ObjectiveItem(id: e['id'], text: e['text'], complete: e['complete'] == true)).toList();
        if (items != null) {
          gs.quest.value = Quest(id: raw['id'] ?? 'unknown', title: raw['title'] ?? 'Quest', items: items);
        }
      } catch (_) {}
    }
    final spoken = prefs.getStringList(_kSpoken);
    if (spoken != null) gs.setSpokenBulk(spoken);
  }

  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kConsent);
    await prefs.remove(_kChapter);
    await prefs.remove(_kSection);
    await prefs.remove(_kQuest);
    await prefs.remove(_kSpoken);
  }
}

