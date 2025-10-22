import 'package:flutter/foundation.dart' show ValueNotifier;

class ObjectiveItem {
  final String id;
  final String text;
  bool complete;
  ObjectiveItem({required this.id, required this.text, this.complete = false});
}

class Quest {
  final String id;
  final String title;
  final List<ObjectiveItem> items;
  Quest({required this.id, required this.title, required this.items});

  bool get isComplete => items.every((i) => i.complete);
}

class GameState {
  // Singleton-ish simple state for this MVP
  static final GameState instance = GameState._();
  GameState._();

  // Scene flags
  final ValueNotifier<bool> consentGiven = ValueNotifier<bool>(false);
  final Set<String> _spokenTo = <String>{};
  Set<String> get spokenTo => _spokenTo;

  // Chapter/Section/Quest tracking
  final ValueNotifier<String> chapter = ValueNotifier<String>('Chapter 1: Arrival');
  final ValueNotifier<String> section = ValueNotifier<String>("Doctors' Lab");
  final ValueNotifier<Quest> quest = ValueNotifier<Quest>(
    Quest(
      id: 'arrival_lab_intro',
      title: "Meet the Doctors & Consent",
      items: [
        ObjectiveItem(id: 'talk_elena', text: 'Talk to Dr. Elena Vega'),
        ObjectiveItem(id: 'talk_arun', text: 'Talk to Dr. Arun Patel'),
        ObjectiveItem(id: 'consent', text: 'Confirm informed consent'),
      ],
    ),
  );

  void markSpoken(String name) {
    _spokenTo.add(name);
    final q = quest.value;
    if (name.contains('Elena')) {
      _setObjectiveComplete(q, 'talk_elena');
    }
    if (name.contains('Arun')) {
      _setObjectiveComplete(q, 'talk_arun');
    }
    quest.notifyListeners();
  }

  void setConsent(bool value) {
    consentGiven.value = value;
    if (value) {
      _setObjectiveComplete(quest.value, 'consent');
      quest.notifyListeners();
    }
  }

  void startSection({required String chapterName, required String sectionName, Quest? newQuest}) {
    chapter.value = chapterName;
    section.value = sectionName;
    if (newQuest != null) {
      quest.value = newQuest;
    }
  }

  void _setObjectiveComplete(Quest q, String id) {
    for (final item in q.items) {
      if (item.id == id) {
        item.complete = true;
        return;
      }
    }
  }

  void setSpokenBulk(Iterable<String> names) {
    _spokenTo
      ..clear()
      ..addAll(names);
    final q = quest.value;
    if (_spokenTo.any((n) => n.contains('Elena'))) _setObjectiveComplete(q, 'talk_elena');
    if (_spokenTo.any((n) => n.contains('Arun'))) _setObjectiveComplete(q, 'talk_arun');
    quest.notifyListeners();
  }
}
