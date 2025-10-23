import 'package:flutter/foundation.dart' show ValueNotifier;

// --- Data Models (Now with copyWith for immutable updates) ---

class ObjectiveItem {
  final String id;
  final String text;
  final bool complete;

  ObjectiveItem({
    required this.id,
    required this.text,
    this.complete = false,
  });

  /// Creates a copy of this ObjectiveItem but with the given fields replaced with new values.
  ObjectiveItem copyWith({bool? complete}) {
    return ObjectiveItem(
      id: id,
      text: text,
      complete: complete ?? this.complete,
    );
  }
}

class Quest {
  final String id;
  final String title;
  final List<ObjectiveItem> items;

  Quest({required this.id, required this.title, required this.items});

  bool get isComplete => items.every((i) => i.complete);

  /// Creates a copy of this Quest but with the given fields replaced with new values.
  Quest copyWith({List<ObjectiveItem>? items}) {
    return Quest(
      id: id,
      title: title,
      items: items ?? this.items,
    );
  }
}

// --- Game State Singleton ---

class GameState {
  // Singleton-ish simple state for this MVP
  static final GameState instance = GameState._();
  GameState._();

  // A map to robustly link character IDs to their corresponding objective IDs.
  // This avoids fragile string matching like `name.contains('Elena')`.
  static const Map<String, String> _characterObjectiveMap = {
    'char_elena': 'talk_elena',
    'char_arun': 'talk_arun',
  };

  // --- State Properties (Wrapped in ValueNotifiers for reactivity) ---

  // Scene flags
  final ValueNotifier<bool> consentGiven = ValueNotifier<bool>(false);
  final ValueNotifier<Set<String>> spokenTo = ValueNotifier<Set<String>>(<String>{});

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

  // Knowledge flags (what the player has learned via choices)
  final ValueNotifier<Set<String>> knowledge = ValueNotifier<Set<String>>(<String>{});

  // --- State Mutator Methods (Now using immutable patterns) ---

  /// Marks a character as spoken to and updates the relevant quest objective.
  /// Uses a robust [characterId] instead of a name.
  void markSpoken(String characterId) {
    // Update the 'spokenTo' set immutably
    final newSpokenTo = Set<String>.from(spokenTo.value)..add(characterId);
    spokenTo.value = newSpokenTo;

    // Check if this character is tied to an objective
    final objectiveId = _characterObjectiveMap[characterId];
    if (objectiveId != null) {
      _setObjectiveComplete(objectiveId);
    }
  }

  /// Sets the consent status and updates the 'consent' quest objective.
  void setConsent(bool value) {
    consentGiven.value = value;
    if (value) {
      _setObjectiveComplete('consent');
    }
  }

  /// Adds a new piece of knowledge.
  void learn(String id) {
    final next = Set<String>.from(knowledge.value)..add(id);
    knowledge.value = next;
  }

  /// Replaces the entire set of known facts.
  void setKnownBulk(Iterable<String> ids) {
    knowledge.value = Set<String>.from(ids);
  }

  /// Replaces the entire set of spoken-to characters and updates objectives.
  void setSpokenBulk(Iterable<String> characterIds) {
    spokenTo.value = Set<String>.from(characterIds);

    // Find all objectives that should be completed based on the new set
    final objectivesToComplete = characterIds
        .map((id) => _characterObjectiveMap[id])
        .where((objectiveId) => objectiveId != null)
        .toSet();

    if (objectivesToComplete.isNotEmpty) {
      final newItems = quest.value.items.map((item) {
        if (objectivesToComplete.contains(item.id)) {
          return item.copyWith(complete: true);
        }
        return item;
      }).toList();

      quest.value = quest.value.copyWith(items: newItems);
    }
  }

  /// Starts a new chapter/section, optionally with a new quest.
  void startSection({
    required String chapterName,
    required String sectionName,
    Quest? newQuest,
  }) {
    chapter.value = chapterName;
    section.value = sectionName;
    if (newQuest != null) {
      quest.value = newQuest;
    }
  }

  /// Private helper to update an objective in an immutable way.
  /// This creates a new Quest object, which automatically notifies listeners.
  void _setObjectiveComplete(String id) {
    final currentQuest = quest.value;

    // Create a new list of items with the target item updated.
    final newItems = currentQuest.items.map((item) {
      if (item.id == id) {
        // Use copyWith to create a new, updated item
        return item.copyWith(complete: true);
      }
      return item;
    }).toList();

    // Create a new Quest with the updated items and assign it to the notifier.
    // This assignment is what triggers the UI to rebuild.
    quest.value = currentQuest.copyWith(items: newItems);
  }
}
