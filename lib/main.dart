import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ReadingJournalApp());
}

// ---------- DATA ----------

enum BookStatus { tbr, dnf, reading, finished }

enum ViewMode { grid, compact, list, shelf }

enum ChallengeMetric { books, pages, readingDays }

class ReadingSession {
  ReadingSession({
    required this.date,
    this.pages = 0,
    this.note = '',
  });

  DateTime date;
  int pages;
  String note;

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'pages': pages,
        'note': note,
      };

  factory ReadingSession.fromJson(Map<String, dynamic> json) => ReadingSession(
        date: DateTime.tryParse(json['date']?.toString() ?? '') ?? DateTime.now(),
        pages: (json['pages'] as num?)?.toInt() ?? 0,
        note: json['note']?.toString() ?? '',
      );
}

IconData _iconFromJsonCode(int? codePoint) {
  if (codePoint == Icons.flag_rounded.codePoint) return Icons.flag_rounded;
  if (codePoint == Icons.flag_outlined.codePoint) return Icons.flag_outlined;
  if (codePoint == Icons.menu_book_rounded.codePoint) return Icons.menu_book_rounded;
  if (codePoint == Icons.auto_stories_rounded.codePoint) return Icons.auto_stories_rounded;
  if (codePoint == Icons.star_rounded.codePoint) return Icons.star_rounded;
  if (codePoint == Icons.speed_rounded.codePoint) return Icons.speed_rounded;
  return Icons.flag_rounded;
}

class ReadingChallenge {
  ReadingChallenge({
    required this.id,
    required this.title,
    required this.startDate,
    required this.endDate,
    required this.target,
    this.metric = ChallengeMetric.books,
    this.icon = Icons.flag_rounded,
  });

  String id;
  String title;
  DateTime startDate;
  DateTime endDate;
  int target;
  ChallengeMetric metric;
  IconData icon;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'startDate': startDate.toIso8601String(),
        'endDate': endDate.toIso8601String(),
        'target': target,
        'metric': metric.name,
        'iconCode': icon.codePoint,
      };

  factory ReadingChallenge.fromJson(Map<String, dynamic> json) => ReadingChallenge(
        id: json['id']?.toString() ?? const Uuid().v4(),
        title: json['title']?.toString() ?? 'Reto lector',
        startDate: DateTime.tryParse(json['startDate']?.toString() ?? '') ?? DateTime.now(),
        endDate: DateTime.tryParse(json['endDate']?.toString() ?? '') ?? DateTime.now(),
        target: (json['target'] as num?)?.toInt() ?? 1,
        metric: ChallengeMetric.values.firstWhere(
          (value) => value.name == json['metric'],
          orElse: () => ChallengeMetric.books,
        ),
        icon: _iconFromJsonCode((json['iconCode'] as num?)?.toInt()),
      );
}

class Book {
  Book({
    required this.id,
    required this.title,
    this.isbn = '',
    this.pages = 0,
    this.format = 'Físico',
    this.author = '',
    List<String>? genres,
    this.startDate,
    this.endDate,
    this.dnf = false,
    this.status = BookStatus.tbr,
    this.favorite = false,
    this.currentPage = 0,
    List<String>? tags,
    this.spice = 0,
    this.rating = 0,
    Map<String, double>? emotions,
    this.review = '',
    this.coverPath = '',
    this.readCount = 1,
    List<ReadingSession>? readingSessions,
  })
      : genres = List<String>.from(genres ?? const []),
        tags = List<String>.from(tags ?? const []),
        emotions = Map<String, double>.from(emotions ?? const {}),
        readingSessions = List<ReadingSession>.from(readingSessions ?? const []);

  String id;
  String title;
  String isbn;
  int pages;
  String format;
  String author;
  List<String> genres;
  DateTime? startDate;
  DateTime? endDate;
  bool dnf;
  BookStatus status;
  bool favorite;
  int currentPage;
  List<String> tags;
  double spice;
  double rating;
  Map<String, double> emotions;
  String review;
  String coverPath;
  int readCount;
  List<ReadingSession> readingSessions;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'isbn': isbn,
        'pages': pages,
        'format': format,
        'author': author,
        'genres': genres,
        'startDate': startDate?.toIso8601String(),
        'endDate': endDate?.toIso8601String(),
        'dnf': dnf,
        'status': status.name,
        'favorite': favorite,
        'currentPage': currentPage,
        'tags': tags,
        'spice': spice,
        'rating': rating,
        'emotions': emotions,
        'review': review,
        'coverPath': coverPath,
        'readCount': readCount,
        'readingSessions': readingSessions.map((e) => e.toJson()).toList(),
      };

  factory Book.fromJson(Map<String, dynamic> json) {
    final rawEmotions = (json['emotions'] as Map?)?.map(
          (key, value) => MapEntry(key.toString(), (value as num).toDouble()),
        ) ??
        <String, double>{};
    final rawGenres = (json['genres'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final rawSessions = (json['readingSessions'] as List?)
            ?.whereType<Map>()
            .map((e) => ReadingSession.fromJson(Map<String, dynamic>.from(e)))
            .toList() ??
        <ReadingSession>[];
    final status = BookStatus.values.firstWhere(
      (value) => value.name == json['status'],
      orElse: () => BookStatus.tbr,
    );
    return Book(
      id: json['id']?.toString() ?? const Uuid().v4(),
      title: json['title']?.toString() ?? 'Sin título',
      isbn: json['isbn']?.toString() ?? '',
      pages: (json['pages'] as num?)?.toInt() ?? 0,
      format: json['format']?.toString() ?? 'Físico',
      author: json['author']?.toString() ?? '',
      genres: rawGenres,
      startDate: _parseDate(json['startDate']),
      endDate: _parseDate(json['endDate']),
      dnf: json['dnf'] as bool? ?? false,
      status: status,
      favorite: json['favorite'] as bool? ?? false,
      currentPage: (json['currentPage'] as num?)?.toInt() ?? 0,
      tags: (json['tags'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      spice: (json['spice'] as num?)?.toDouble() ?? 0,
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      emotions: rawEmotions,
      review: json['review']?.toString() ?? '',
      coverPath: json['coverPath']?.toString() ?? '',
      readCount: (json['readCount'] as num?)?.toInt() ?? 1,
      readingSessions: rawSessions,
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) {
      return null;
    }
    return DateTime.tryParse(value.toString());
  }
}

class AppController extends ChangeNotifier {
  AppController(this._prefs);

  final SharedPreferences _prefs;
  final List<Book> books = [];
  final List<ReadingChallenge> challenges = [];
  String localeCode = 'es-ES';
  String palette = 'terracotta';
  String style = 'cozy';
  String fontStyle = 'system';
  String mood = 'warm';
  String background = 'paper';
  String cardStyle = 'soft';
  String density = 'comfortable';
  double cornerRadius = 24;
  double accentIntensity = .78;
  bool decorations = true;
  bool doodles = true;
  bool animations = true;
  bool darkMode = false;
  String libraryDefaultView = 'grid';
  String librarySort = 'recent';
  bool favoritesFirst = true;
  bool showProgressOnCards = true;
  bool showAuthorOnCards = true;
  String coverShape = 'rounded';
  String navigationStyle = 'bar';
  String statsStyle = 'cards';
  String calendarStyle = 'trail';
  bool showStatsCalendar = true;
  String wrappedTemplate = 'scrapbook';
  String wrappedPattern = 'doodles';
  String wrappedRatio = 'story';
  String bookishScene = 'cozy';
  String bookishShelf = 'wood';
  String bookishDecor = 'plants';
  String bookishDisplay = 'mix';
  String bookishRatio = 'portrait';
  double backgroundOpacity = .12;
  double titleScale = 1.0;
  double uiScale = 1.0;
  String contentWidth = 'standard';
  String spacing = 'comfortable';
  bool showAppTagline = true;

  static const _booksKey = 'books_v1';
  static const _challengesKey = 'challenges_v1';
  static const _settingsKey = 'settings_v3';

  Future<void> load() async {
    final savedBooks = _prefs.getString(_booksKey);
    if (savedBooks != null) {
      final decoded = jsonDecode(savedBooks) as List;
      books
        ..clear()
        ..addAll(decoded.map((e) => Book.fromJson(Map<String, dynamic>.from(e as Map))));
    }
    final savedChallenges = _prefs.getString(_challengesKey);
    if (savedChallenges != null) {
      final decoded = jsonDecode(savedChallenges) as List;
      challenges
        ..clear()
        ..addAll(decoded.map((e) => ReadingChallenge.fromJson(Map<String, dynamic>.from(e as Map))));
    }
    final settings = _prefs.getString(_settingsKey);
    if (settings != null) {
      final map = Map<String, dynamic>.from(jsonDecode(settings) as Map);
      localeCode = map['localeCode']?.toString() ?? localeCode;
      palette = map['palette']?.toString() ?? palette;
      style = map['style']?.toString() ?? style;
      fontStyle = map['fontStyle']?.toString() ?? fontStyle;
      mood = map['mood']?.toString() ?? mood;
      background = map['background']?.toString() ?? background;
      cardStyle = map['cardStyle']?.toString() ?? cardStyle;
      density = map['density']?.toString() ?? density;
      cornerRadius = (map['cornerRadius'] as num?)?.toDouble() ?? cornerRadius;
      accentIntensity = (map['accentIntensity'] as num?)?.toDouble() ?? accentIntensity;
      decorations = map['decorations'] as bool? ?? decorations;
      doodles = map['doodles'] as bool? ?? doodles;
      animations = map['animations'] as bool? ?? animations;
      darkMode = map['darkMode'] as bool? ?? darkMode;
      libraryDefaultView = map['libraryDefaultView']?.toString() ?? libraryDefaultView;
      librarySort = map['librarySort']?.toString() ?? librarySort;
      favoritesFirst = map['favoritesFirst'] as bool? ?? favoritesFirst;
      showProgressOnCards = map['showProgressOnCards'] as bool? ?? showProgressOnCards;
      showAuthorOnCards = map['showAuthorOnCards'] as bool? ?? showAuthorOnCards;
      coverShape = map['coverShape']?.toString() ?? coverShape;
      navigationStyle = map['navigationStyle']?.toString() ?? navigationStyle;
      statsStyle = map['statsStyle']?.toString() ?? statsStyle;
      calendarStyle = map['calendarStyle']?.toString() ?? calendarStyle;
      showStatsCalendar = map['showStatsCalendar'] as bool? ?? showStatsCalendar;
      wrappedTemplate = map['wrappedTemplate']?.toString() ?? wrappedTemplate;
      wrappedPattern = map['wrappedPattern']?.toString() ?? wrappedPattern;
      wrappedRatio = map['wrappedRatio']?.toString() ?? wrappedRatio;
      bookishScene = map['bookishScene']?.toString() ?? bookishScene;
      bookishShelf = map['bookishShelf']?.toString() ?? bookishShelf;
      bookishDecor = map['bookishDecor']?.toString() ?? bookishDecor;
      bookishDisplay = map['bookishDisplay']?.toString() ?? bookishDisplay;
      bookishRatio = map['bookishRatio']?.toString() ?? bookishRatio;
      backgroundOpacity = (map['backgroundOpacity'] as num?)?.toDouble() ?? backgroundOpacity;
      titleScale = (map['titleScale'] as num?)?.toDouble() ?? titleScale;
      uiScale = (map['uiScale'] as num?)?.toDouble() ?? uiScale;
      contentWidth = map['contentWidth']?.toString() ?? contentWidth;
      spacing = map['spacing']?.toString() ?? spacing;
      showAppTagline = map['showAppTagline'] as bool? ?? showAppTagline;
    }
    notifyListeners();
  }

  Future<void> save() async {
    await _prefs.setString(_booksKey, jsonEncode(books.map((b) => b.toJson()).toList()));
    await _prefs.setString(_challengesKey, jsonEncode(challenges.map((r) => r.toJson()).toList()));
    await _prefs.setString(
      _settingsKey,
      jsonEncode({
        'localeCode': localeCode,
        'palette': palette,
        'style': style,
        'fontStyle': fontStyle,
        'mood': mood,
        'background': background,
        'cardStyle': cardStyle,
        'density': density,
        'cornerRadius': cornerRadius,
        'accentIntensity': accentIntensity,
        'decorations': decorations,
        'doodles': doodles,
        'animations': animations,
        'darkMode': darkMode,
        'libraryDefaultView': libraryDefaultView,
        'librarySort': librarySort,
        'favoritesFirst': favoritesFirst,
        'showProgressOnCards': showProgressOnCards,
        'showAuthorOnCards': showAuthorOnCards,
        'coverShape': coverShape,
        'navigationStyle': navigationStyle,
        'statsStyle': statsStyle,
        'calendarStyle': calendarStyle,
        'showStatsCalendar': showStatsCalendar,
        'wrappedTemplate': wrappedTemplate,
        'wrappedPattern': wrappedPattern,
        'wrappedRatio': wrappedRatio,
        'bookishScene': bookishScene,
        'bookishShelf': bookishShelf,
        'bookishDecor': bookishDecor,
        'bookishDisplay': bookishDisplay,
        'bookishRatio': bookishRatio,
        'backgroundOpacity': backgroundOpacity,
        'titleScale': titleScale,
        'uiScale': uiScale,
        'contentWidth': contentWidth,
        'spacing': spacing,
        'showAppTagline': showAppTagline,
      }),
    );
  }

  Future<void> addBook(Book book) async {
    books.insert(0, book);
    await save();
    notifyListeners();
  }

  Future<void> updateBook(Book book) async {
    final index = books.indexWhere((b) => b.id == book.id);
    if (index >= 0) {
      books[index] = book;
      await save();
      notifyListeners();
    }
  }

  Future<void> deleteBook(String id) async {
    books.removeWhere((b) => b.id == id);
    await save();
    notifyListeners();
  }

  Future<void> addSession(String bookId, ReadingSession session) async {
    final index = books.indexWhere((b) => b.id == bookId);
    if (index < 0) return;
    final book = books[index];
    book.readingSessions.add(session);
    book.readingSessions.sort((a, b) => a.date.compareTo(b.date));
    if (session.pages > 0 && book.pages > 0) {
      book.currentPage = math.min(book.pages, book.currentPage + session.pages);
    }
    if (book.status == BookStatus.tbr && session.pages > 0) book.status = BookStatus.reading;
    if (book.pages > 0 && book.currentPage >= book.pages) {
      book.currentPage = book.pages;
      book.status = BookStatus.finished;
      book.endDate ??= session.date;
    }
    await save();
    notifyListeners();
  }

  Future<void> toggleFavorite(String bookId) async {
    final index = books.indexWhere((b) => b.id == bookId);
    if (index < 0) return;
    books[index].favorite = !books[index].favorite;
    await save();
    notifyListeners();
  }

  Future<void> updateProgress(String bookId, int page) async {
    final index = books.indexWhere((b) => b.id == bookId);
    if (index < 0) return;
    final book = books[index];
    book.currentPage = book.pages > 0 ? math.min(math.max(0, page), book.pages) : math.max(0, page);
    if (book.pages > 0 && book.currentPage >= book.pages) {
      book.currentPage = book.pages;
      book.status = BookStatus.finished;
      book.endDate ??= DateTime.now();
    } else if (book.currentPage > 0 && book.status == BookStatus.tbr) {
      book.status = BookStatus.reading;
    }
    await save();
    notifyListeners();
  }

  Future<void> rereadBook(String bookId) async {
    final index = books.indexWhere((b) => b.id == bookId);
    if (index < 0) return;
    final book = books[index];
    book.readCount += 1;
    book.currentPage = 0;
    book.status = BookStatus.reading;
    book.dnf = false;
    book.startDate = DateTime.now();
    book.endDate = null;
    await save();
    notifyListeners();
  }

  Future<void> addChallenge(ReadingChallenge challenge) async {
    challenges.insert(0, challenge);
    await save();
    notifyListeners();
  }

  Future<void> deleteChallenge(String id) async {
    challenges.removeWhere((challenge) => challenge.id == id);
    await save();
    notifyListeners();
  }

  int challengeProgress(ReadingChallenge challenge) {
    final start = DateTime(challenge.startDate.year, challenge.startDate.month, challenge.startDate.day);
    final end = DateTime(challenge.endDate.year, challenge.endDate.month, challenge.endDate.day);
    switch (challenge.metric) {
      case ChallengeMetric.books:
        return books.where((book) {
          final date = book.endDate ?? book.startDate;
          if (date == null) return false;
          final d = DateTime(date.year, date.month, date.day);
          final inside = d.isAtSameMomentAs(start) || d.isAtSameMomentAs(end) || (d.isAfter(start) && d.isBefore(end));
          return inside && book.status == BookStatus.finished;
        }).length;
      case ChallengeMetric.pages:
        return books.fold<int>(0, (sum, book) {
          final date = book.endDate ?? book.startDate;
          if (date == null) return sum;
          final d = DateTime(date.year, date.month, date.day);
          final inside = d.isAtSameMomentAs(start) || d.isAtSameMomentAs(end) || (d.isAfter(start) && d.isBefore(end));
          return inside && book.status == BookStatus.finished ? sum + book.pages : sum;
        });
      case ChallengeMetric.readingDays:
        final days = <String>{};
        for (final book in books) {
          for (final session in book.readingSessions) {
            final d = DateTime(session.date.year, session.date.month, session.date.day);
            if (d.isBefore(start) || d.isAfter(end)) continue;
            days.add(DateFormat('yyyy-MM-dd').format(d));
          }
        }
        return days.length;
    }
  }

  Future<void> updateSettings({String? newLocale, String? newPalette, String? newStyle, String? newFont, String? newMood, String? newBackground, String? newCardStyle, String? newDensity, double? newCornerRadius, double? newAccentIntensity, bool? newDecorations, bool? newDoodles, bool? newAnimations, bool? newDark, String? newLibraryDefaultView, String? newLibrarySort, bool? newFavoritesFirst, bool? newShowProgressOnCards, bool? newShowAuthorOnCards, String? newCoverShape, String? newNavigationStyle, String? newStatsStyle, String? newCalendarStyle, bool? newShowStatsCalendar, String? newWrappedTemplate, String? newWrappedPattern, String? newWrappedRatio, String? newBookishScene, String? newBookishShelf, String? newBookishDecor, String? newBookishDisplay, String? newBookishRatio, double? newBackgroundOpacity, double? newTitleScale, double? newUiScale, String? newContentWidth, String? newSpacing, bool? newShowAppTagline}) async {
    if (newLocale != null) {
      localeCode = newLocale;
    }
    if (newPalette != null) {
      palette = newPalette;
    }
    if (newStyle != null) {
      style = newStyle;
    }
    if (newFont != null) {
      fontStyle = newFont;
    }
    if (newMood != null) {
      mood = newMood;
    }
    if (newBackground != null) {
      background = newBackground;
    }
    if (newCardStyle != null) {
      cardStyle = newCardStyle;
    }
    if (newDensity != null) {
      density = newDensity;
    }
    if (newCornerRadius != null) {
      cornerRadius = newCornerRadius;
    }
    if (newAccentIntensity != null) {
      accentIntensity = newAccentIntensity;
    }
    if (newDecorations != null) {
      decorations = newDecorations;
    }
    if (newDoodles != null) {
      doodles = newDoodles;
    }
    if (newAnimations != null) {
      animations = newAnimations;
    }
    if (newDark != null) {
      darkMode = newDark;
    }
    if (newLibraryDefaultView != null) libraryDefaultView = newLibraryDefaultView;
    if (newLibrarySort != null) librarySort = newLibrarySort;
    if (newFavoritesFirst != null) favoritesFirst = newFavoritesFirst;
    if (newShowProgressOnCards != null) showProgressOnCards = newShowProgressOnCards;
    if (newShowAuthorOnCards != null) showAuthorOnCards = newShowAuthorOnCards;
    if (newCoverShape != null) coverShape = newCoverShape;
    if (newNavigationStyle != null) navigationStyle = newNavigationStyle;
    if (newStatsStyle != null) statsStyle = newStatsStyle;
    if (newCalendarStyle != null) calendarStyle = newCalendarStyle;
    if (newShowStatsCalendar != null) showStatsCalendar = newShowStatsCalendar;
    if (newWrappedTemplate != null) wrappedTemplate = newWrappedTemplate;
    if (newWrappedPattern != null) wrappedPattern = newWrappedPattern;
    if (newWrappedRatio != null) wrappedRatio = newWrappedRatio;
    if (newBookishScene != null) bookishScene = newBookishScene;
    if (newBookishShelf != null) bookishShelf = newBookishShelf;
    if (newBookishDecor != null) bookishDecor = newBookishDecor;
    if (newBookishDisplay != null) bookishDisplay = newBookishDisplay;
    if (newBookishRatio != null) bookishRatio = newBookishRatio;
    if (newBackgroundOpacity != null) backgroundOpacity = newBackgroundOpacity;
    if (newTitleScale != null) titleScale = newTitleScale;
    if (newUiScale != null) uiScale = newUiScale;
    if (newContentWidth != null) contentWidth = newContentWidth;
    if (newSpacing != null) spacing = newSpacing;
    if (newShowAppTagline != null) showAppTagline = newShowAppTagline;
    await save();
    notifyListeners();
  }

  Color get pageBackground {
    final base = darkMode ? const Color(0xFF171517) : const Color(0xFFF8F5F0);
    switch (background) {
      case 'mist': return Color.lerp(base, seedColor, backgroundOpacity)!;
      case 'warm': return Color.lerp(base, const Color(0xFFF1E6DA), .25 + backgroundOpacity)!;
      case 'lavender': return Color.lerp(base, const Color(0xFFE9E1F1), .28 + backgroundOpacity)!;
      case 'sage': return Color.lerp(base, const Color(0xFFDDE8DD), .25 + backgroundOpacity)!;
      case 'parchment': return Color.lerp(base, const Color(0xFFEDE0C5), .30 + backgroundOpacity)!;
      case 'rose': return Color.lerp(base, const Color(0xFFF2DDE4), .28 + backgroundOpacity)!;
      case 'blue': return Color.lerp(base, const Color(0xFFDDE8F0), .28 + backgroundOpacity)!;
      default: return base;
    }
  }

  Color get surfaceCard {
    if (darkMode) return const Color(0xFF211F22);
    switch (cardStyle) {
      case 'glass': return Colors.white.withValues(alpha: .55 + backgroundOpacity);
      case 'cream': return const Color(0xFFFFFBF5);
      case 'ink': return const Color(0xFFF1EEE8);
      default: return Colors.white.withValues(alpha: .88);
    }
  }

  Color get seedColor {
    const palettes = {
      'terracotta': Color(0xFFB76E5E),
      'lavender': Color(0xFF8B78A7),
      'sage': Color(0xFF6D8773),
      'rose': Color(0xFFC77887),
      'midnight': Color(0xFF5D6B9A),
      'butter': Color(0xFFC59B45),
      'ocean': Color(0xFF4F8190),
      'berry': Color(0xFF9A5C78),
      'plum': Color(0xFF74506C),
      'peach': Color(0xFFD79273),
      'forest': Color(0xFF517663),
      'sky': Color(0xFF648CAA),
      'sand': Color(0xFFB18A63),
      'coral': Color(0xFFC46F62),
      'iris': Color(0xFF756EA8),
      'moss': Color(0xFF71815B),
      'inkblue': Color(0xFF425774),
      'apricot': Color(0xFFCC896D),
    };
    return palettes[palette] ?? palettes['terracotta']!;
  }

  Color get moodAccent {
    switch (mood) {
      case 'calm': return const Color(0xFF8AA79B);
      case 'dreamy': return const Color(0xFFB59BC9);
      case 'moody': return const Color(0xFF6F667D);
      case 'bright': return const Color(0xFFE2AE55);
      case 'airy': return const Color(0xFF8EA7BF);
      case 'mystic': return const Color(0xFF8C70A9);
      default: return const Color(0xFFD08B73);
    }
  }

  double get contentMaxWidth {
    switch (contentWidth) {
      case 'narrow': return 700;
      case 'wide': return 980;
      case 'full': return 1180;
      default: return 840;
    }
  }

  double get pageHorizontalPadding {
    switch (spacing) {
      case 'compact': return 12;
      case 'airy': return 26;
      case 'roomy': return 34;
      default: return 18;
    }
  }

  double get sectionGap {
    switch (spacing) {
      case 'compact': return 8;
      case 'airy': return 16;
      case 'roomy': return 22;
      default: return 12;
    }
  }

  Future<void> applyPreset(String preset) async {
    final key = preset == 'darkAcademia' ? 'dark_academia' : preset;

    // Cada estética configura una identidad completa, no solo el color.
    // Así, tocar una tarjeta de la galería cambia realmente la personalidad
    // de la app y también mantiene el comportamiento responsive.
    switch (key) {
      case 'cozy':
        palette = 'terracotta'; style = key; fontStyle = 'rounded'; mood = 'warm'; background = 'paper'; cardStyle = 'cream'; coverShape = 'rounded'; wrappedTemplate = 'scrapbook'; wrappedPattern = 'doodles'; bookishScene = 'cozy'; bookishShelf = 'wood'; bookishDecor = 'plants'; bookishDisplay = 'mix'; bookishRatio = 'portrait'; navigationStyle = 'pill'; statsStyle = 'cards'; calendarStyle = 'trail'; density = 'comfortable'; spacing = 'airy'; cornerRadius = 26; accentIntensity = .74; backgroundOpacity = .13; titleScale = 1.03; uiScale = 1.00; contentWidth = 'standard'; darkMode = false; decorations = true; doodles = true;
        break;
      case 'romance':
        palette = 'rose'; style = key; fontStyle = 'rounded'; mood = 'dreamy'; background = 'rose'; cardStyle = 'glass'; coverShape = 'soft'; wrappedTemplate = 'dreamy'; wrappedPattern = 'botanical'; bookishScene = 'pastel'; bookishShelf = 'rainbow'; bookishDecor = 'flowers'; bookishDisplay = 'covers'; bookishRatio = 'portrait'; navigationStyle = 'pill'; statsStyle = 'cards'; calendarStyle = 'botanical'; density = 'airy'; spacing = 'airy'; cornerRadius = 30; accentIntensity = .88; backgroundOpacity = .18; titleScale = 1.06; uiScale = 1.01; contentWidth = 'standard'; darkMode = false; decorations = true; doodles = true;
        break;
      case 'fantasy':
        palette = 'iris'; style = key; fontStyle = 'serif'; mood = 'mystic'; background = 'lavender'; cardStyle = 'glass'; coverShape = 'soft'; wrappedTemplate = 'dreamy'; wrappedPattern = 'stars'; bookishScene = 'pastel'; bookishShelf = 'floating'; bookishDecor = 'moon'; bookishDisplay = 'mix'; bookishRatio = 'portrait'; navigationStyle = 'airy'; statsStyle = 'editorial'; calendarStyle = 'botanical'; density = 'airy'; spacing = 'roomy'; cornerRadius = 28; accentIntensity = .96; backgroundOpacity = .20; titleScale = 1.10; uiScale = 1.02; contentWidth = 'wide'; darkMode = false; decorations = true; doodles = true;
        break;
      case 'gothic':
        palette = 'plum'; style = key; fontStyle = 'serif'; mood = 'moody'; background = 'mist'; cardStyle = 'ink'; coverShape = 'square'; wrappedTemplate = 'poster'; wrappedPattern = 'stars'; bookishScene = 'gothic'; bookishShelf = 'wood'; bookishDecor = 'moon'; bookishDisplay = 'spines'; bookishRatio = 'story'; navigationStyle = 'compact'; statsStyle = 'editorial'; calendarStyle = 'bold'; density = 'compact'; spacing = 'comfortable'; cornerRadius = 14; accentIntensity = .92; backgroundOpacity = .18; titleScale = 1.04; uiScale = .98; contentWidth = 'standard'; darkMode = true; decorations = true; doodles = true;
        break;
      case 'dark_academia':
        palette = 'forest'; style = key; fontStyle = 'serif'; mood = 'moody'; background = 'parchment'; cardStyle = 'cream'; coverShape = 'square'; wrappedTemplate = 'editorial'; wrappedPattern = 'paper'; bookishScene = 'gothic'; bookishShelf = 'wood'; bookishDecor = 'plants'; bookishDisplay = 'spines'; bookishRatio = 'portrait'; navigationStyle = 'bar'; statsStyle = 'editorial'; calendarStyle = 'minimal'; density = 'comfortable'; spacing = 'airy'; cornerRadius = 12; accentIntensity = .70; backgroundOpacity = .20; titleScale = 1.01; uiScale = 1.00; contentWidth = 'wide'; darkMode = false; decorations = true; doodles = true;
        break;
      case 'cottagecore':
        palette = 'moss'; style = key; fontStyle = 'serif'; mood = 'calm'; background = 'sage'; cardStyle = 'cream'; coverShape = 'soft'; wrappedTemplate = 'scrapbook'; wrappedPattern = 'botanical'; bookishScene = 'cottage'; bookishShelf = 'wood'; bookishDecor = 'flowers'; bookishDisplay = 'covers'; bookishRatio = 'portrait'; navigationStyle = 'airy'; statsStyle = 'cards'; calendarStyle = 'botanical'; density = 'airy'; spacing = 'roomy'; cornerRadius = 30; accentIntensity = .70; backgroundOpacity = .20; titleScale = 1.05; uiScale = 1.01; contentWidth = 'standard'; darkMode = false; decorations = true; doodles = true;
        break;
      case 'whimsigoth':
        palette = 'berry'; style = key; fontStyle = 'serif'; mood = 'mystic'; background = 'rose'; cardStyle = 'glass'; coverShape = 'rounded'; wrappedTemplate = 'dreamy'; wrappedPattern = 'stars'; bookishScene = 'gothic'; bookishShelf = 'floating'; bookishDecor = 'flowers'; bookishDisplay = 'mix'; bookishRatio = 'story'; navigationStyle = 'pill'; statsStyle = 'editorial'; calendarStyle = 'trail'; density = 'airy'; spacing = 'airy'; cornerRadius = 26; accentIntensity = .92; backgroundOpacity = .21; titleScale = 1.08; uiScale = 1.00; contentWidth = 'standard'; darkMode = false; decorations = true; doodles = true;
        break;
      case 'minimal':
        palette = 'midnight'; style = key; fontStyle = 'system'; mood = 'calm'; background = 'mist'; cardStyle = 'ink'; coverShape = 'square'; wrappedTemplate = 'minimal'; wrappedPattern = 'clean'; bookishScene = 'minimal'; bookishShelf = 'floating'; bookishDecor = 'minimal'; bookishDisplay = 'spines'; bookishRatio = 'square'; navigationStyle = 'compact'; statsStyle = 'minimal'; calendarStyle = 'minimal'; density = 'compact'; spacing = 'compact'; cornerRadius = 10; accentIntensity = .46; backgroundOpacity = .06; titleScale = .98; uiScale = .98; contentWidth = 'standard'; darkMode = false; decorations = false; doodles = false;
        break;
      case 'celestial':
        palette = 'inkblue'; style = key; fontStyle = 'serif'; mood = 'mystic'; background = 'blue'; cardStyle = 'glass'; coverShape = 'rounded'; wrappedTemplate = 'poster'; wrappedPattern = 'stars'; bookishScene = 'minimal'; bookishShelf = 'floating'; bookishDecor = 'moon'; bookishDisplay = 'mix'; bookishRatio = 'story'; navigationStyle = 'airy'; statsStyle = 'editorial'; calendarStyle = 'bold'; density = 'airy'; spacing = 'roomy'; cornerRadius = 26; accentIntensity = .96; backgroundOpacity = .22; titleScale = 1.10; uiScale = 1.01; contentWidth = 'wide'; darkMode = false; decorations = true; doodles = true;
        break;
      case 'botanical':
        palette = 'forest'; style = key; fontStyle = 'serif'; mood = 'airy'; background = 'sage'; cardStyle = 'cream'; coverShape = 'soft'; wrappedTemplate = 'scrapbook'; wrappedPattern = 'botanical'; bookishScene = 'cottage'; bookishShelf = 'wood'; bookishDecor = 'plants'; bookishDisplay = 'covers'; bookishRatio = 'portrait'; navigationStyle = 'airy'; statsStyle = 'cards'; calendarStyle = 'botanical'; density = 'roomy'; spacing = 'roomy'; cornerRadius = 28; accentIntensity = .76; backgroundOpacity = .19; titleScale = 1.05; uiScale = 1.01; contentWidth = 'wide'; darkMode = false; decorations = true; doodles = true;
        break;
      case 'ocean':
        palette = 'ocean'; style = key; fontStyle = 'system'; mood = 'calm'; background = 'blue'; cardStyle = 'soft'; coverShape = 'rounded'; wrappedTemplate = 'minimal'; wrappedPattern = 'clean'; bookishScene = 'minimal'; bookishShelf = 'floating'; bookishDecor = 'minimal'; bookishDisplay = 'mix'; bookishRatio = 'portrait'; navigationStyle = 'pill'; statsStyle = 'cards'; calendarStyle = 'trail'; density = 'airy'; spacing = 'airy'; cornerRadius = 22; accentIntensity = .72; backgroundOpacity = .17; titleScale = 1.00; uiScale = 1.00; contentWidth = 'wide'; darkMode = false; decorations = true; doodles = true;
        break;
      case 'retro':
        palette = 'sand'; style = key; fontStyle = 'mono'; mood = 'bright'; background = 'parchment'; cardStyle = 'cream'; coverShape = 'ticket'; wrappedTemplate = 'poster'; wrappedPattern = 'paper'; bookishScene = 'cozy'; bookishShelf = 'wood'; bookishDecor = 'minimal'; bookishDisplay = 'spines'; bookishRatio = 'square'; navigationStyle = 'bar'; statsStyle = 'editorial'; calendarStyle = 'bold'; density = 'comfortable'; spacing = 'airy'; cornerRadius = 8; accentIntensity = .82; backgroundOpacity = .21; titleScale = 1.00; uiScale = 1.00; contentWidth = 'standard'; darkMode = false; decorations = true; doodles = true;
        break;
      case 'noir':
        palette = 'midnight'; style = key; fontStyle = 'condensed'; mood = 'moody'; background = 'mist'; cardStyle = 'ink'; coverShape = 'square'; wrappedTemplate = 'editorial'; wrappedPattern = 'clean'; bookishScene = 'minimal'; bookishShelf = 'floating'; bookishDecor = 'minimal'; bookishDisplay = 'spines'; bookishRatio = 'portrait'; navigationStyle = 'compact'; statsStyle = 'editorial'; calendarStyle = 'minimal'; density = 'compact'; spacing = 'compact'; cornerRadius = 6; accentIntensity = .55; backgroundOpacity = .08; titleScale = .96; uiScale = .97; contentWidth = 'narrow'; darkMode = true; decorations = false; doodles = true;
        break;
      case 'sunset':
        palette = 'coral'; style = key; fontStyle = 'medium'; mood = 'bright'; background = 'warm'; cardStyle = 'soft'; coverShape = 'rounded'; wrappedTemplate = 'scrapbook'; wrappedPattern = 'doodles'; bookishScene = 'cozy'; bookishShelf = 'rainbow'; bookishDecor = 'flowers'; bookishDisplay = 'covers'; bookishRatio = 'portrait'; navigationStyle = 'pill'; statsStyle = 'cards'; calendarStyle = 'trail'; density = 'roomy'; spacing = 'roomy'; cornerRadius = 30; accentIntensity = .90; backgroundOpacity = .21; titleScale = 1.06; uiScale = 1.01; contentWidth = 'wide'; darkMode = false; decorations = true; doodles = true;
        break;
      case 'sakura':
        palette = 'rose'; style = key; fontStyle = 'rounded'; mood = 'dreamy'; background = 'rose'; cardStyle = 'glass'; coverShape = 'soft'; wrappedTemplate = 'dreamy'; wrappedPattern = 'botanical'; bookishScene = 'pastel'; bookishShelf = 'rainbow'; bookishDecor = 'flowers'; bookishDisplay = 'covers'; bookishRatio = 'portrait'; navigationStyle = 'pill'; statsStyle = 'cards'; calendarStyle = 'botanical'; density = 'airy'; spacing = 'roomy'; cornerRadius = 32; accentIntensity = .86; backgroundOpacity = .23; titleScale = 1.07; uiScale = 1.01; contentWidth = 'standard'; darkMode = false; decorations = true; doodles = true;
        break;
      case 'parchment':
        palette = 'butter'; style = key; fontStyle = 'serif'; mood = 'warm'; background = 'parchment'; cardStyle = 'cream'; coverShape = 'ticket'; wrappedTemplate = 'editorial'; wrappedPattern = 'paper'; bookishScene = 'cozy'; bookishShelf = 'wood'; bookishDecor = 'plants'; bookishDisplay = 'spines'; bookishRatio = 'portrait'; navigationStyle = 'bar'; statsStyle = 'editorial'; calendarStyle = 'minimal'; density = 'comfortable'; spacing = 'airy'; cornerRadius = 10; accentIntensity = .64; backgroundOpacity = .23; titleScale = 1.02; uiScale = 1.00; contentWidth = 'wide'; darkMode = false; decorations = true; doodles = true;
        break;
    }
    await save();
    notifyListeners();
  }

  String tr(String key) => AppTexts.text(localeCode, key);
}

class ReadingJournalApp extends StatefulWidget {
  const ReadingJournalApp({super.key});

  @override
  State<ReadingJournalApp> createState() => _ReadingJournalAppState();
}

class _ReadingJournalAppState extends State<ReadingJournalApp> {
  AppController? controller;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SharedPreferences>(
      future: SharedPreferences.getInstance(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const MaterialApp(home: Scaffold(body: Center(child: CircularProgressIndicator())));
        }
        controller ??= AppController(snapshot.data!);
        return AnimatedBuilder(
          animation: controller!,
          builder: (context, _) {
            final seed = controller!.seedColor;
            final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: controller!.darkMode ? Brightness.dark : Brightness.light);
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              title: 'READBLOOM',
              theme: ThemeData(
                useMaterial3: true,
                colorScheme: scheme,
                scaffoldBackgroundColor: controller!.pageBackground,
                fontFamily: switch (controller!.fontStyle) {
                  'serif' => 'serif',
                  'rounded' => 'sans-serif-rounded',
                  'mono' => 'monospace',
                  'condensed' => 'sans-serif-condensed',
                  'light' => 'sans-serif-light',
                  'medium' => 'sans-serif-medium',
                  'black' => 'sans-serif-black',
                  'slab' => 'serif',
                  _ => 'sans-serif',
                },
                visualDensity: controller!.density == 'airy' || controller!.density == 'roomy' ? VisualDensity.comfortable : VisualDensity.standard,
                appBarTheme: AppBarTheme(
                  backgroundColor: scheme.surface,
                  surfaceTintColor: Colors.transparent,
                  elevation: 0,
                  centerTitle: false,
                ),
                navigationBarTheme: NavigationBarThemeData(
                  height: (controller!.navigationStyle == 'compact' ? 64 : controller!.navigationStyle == 'airy' ? 88 : 76) * controller!.uiScale,
                  elevation: 0,
                  backgroundColor: controller!.navigationStyle == 'pill' ? scheme.surface.withValues(alpha: .92) : scheme.surfaceContainerLow,
                  indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(controller!.navigationStyle == 'pill' ? 28 : 18)),
                  labelTextStyle: WidgetStatePropertyAll(TextStyle(fontWeight: FontWeight.w800, fontSize: controller!.navigationStyle == 'compact' ? 10 : 11)),
                ),
                inputDecorationTheme: InputDecorationTheme(
                  filled: true,
                  fillColor: scheme.surfaceContainerLow,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: scheme.primary, width: 1.4)),
                ),
                chipTheme: ChipThemeData(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  side: BorderSide.none,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                ),
                cardTheme: CardThemeData(
                  elevation: controller!.decorations ? (controller!.cardStyle == 'glass' ? 0 : 1) : 0,
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(controller!.cornerRadius)),
                  surfaceTintColor: Colors.transparent,
                  color: controller!.surfaceCard,
                ),
              ),
              builder: (context, child) {
                final media = MediaQuery.of(context);
                final baseScale = media.textScaler.scale(1.0);
                final scaler = TextScaler.linear(baseScale * controller!.uiScale);
                return MediaQuery(data: media.copyWith(textScaler: scaler), child: child!);
              },
              home: _VisualScope(controller: controller!, child: _HomeShell(controller: controller!)),
            );
          },
        );
      },
    );
  }
}

class _HomeShell extends StatefulWidget {
  const _HomeShell({required this.controller});
  final AppController controller;

  @override
  State<_HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<_HomeShell> {
  int index = 0;

  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.load());
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final pages = [
      LibraryPage(controller: c),
      AddBookPage(controller: c),
      StatsPage(controller: c),
      WrappedPage(controller: c),
      BookishPage(controller: c),
      CustomizationPage(controller: c),
    ];
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 18,
        title: Row(
          children: [
            Container(
              width: Responsive.narrow(context) ? 38 : 44,
              height: Responsive.narrow(context) ? 38 : 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                boxShadow: c.decorations ? [BoxShadow(color: c.seedColor.withValues(alpha: .18), blurRadius: 16, offset: const Offset(0, 7))] : const [],
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset('assets/readbloom_logo.png', fit: BoxFit.cover),
            ),
            SizedBox(width: Responsive.narrow(context) ? 9 : 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('READBLOOM', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: Responsive.narrow(context) ? 17 : null, fontWeight: FontWeight.w900, letterSpacing: Responsive.narrow(context) ? 1.4 : 2.0)),
              if (c.showAppTagline && !Responsive.narrow(context)) Text('Tu historia entre páginas', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
            ]),
          ],
        ),
        actions: [
          if (!Responsive.narrow(context) && c.books.any((book) => book.status == BookStatus.reading))
            IconButton(tooltip: 'Registrar sesión de lectura', onPressed: () { final current = c.books.firstWhere((book) => book.status == BookStatus.reading); _addReadingSession(context, c, current); }, icon: const Icon(Icons.timer_outlined)),
          if (!Responsive.narrow(context))
            IconButton(tooltip: 'Retos de lectura', onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChallengesPage(controller: c))), icon: const Icon(Icons.flag_outlined)),
          if (!Responsive.narrow(context))
            IconButton(tooltip: c.tr('import_csv'), onPressed: () => _importCsv(context, c), icon: const Icon(Icons.file_upload_outlined)),
          if (Responsive.narrow(context))
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'session') { final current = c.books.cast<Book?>().firstWhere((book) => book?.status == BookStatus.reading, orElse: () => null); if (current != null) _addReadingSession(context, c, current); }
                if (value == 'challenges') Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChallengesPage(controller: c)));
                if (value == 'csv') _importCsv(context, c);
              },
              itemBuilder: (_) => [
                if (c.books.any((book) => book.status == BookStatus.reading)) const PopupMenuItem(value: 'session', child: Text('Registrar lectura')),
                const PopupMenuItem(value: 'challenges', child: Text('Retos lectores')),
                const PopupMenuItem(value: 'csv', child: Text('Importar CSV')),
              ],
            ),
          const SizedBox(width: 6),
        ],
      ),
      body: Stack(children: [
        Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _AppDoodleBackground(controller: c)))),
        Positioned.fill(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: math.min(c.contentMaxWidth, math.max(320, MediaQuery.sizeOf(context).width - 2))),
              child: IndexedStack(index: index, children: pages),
            ),
          ),
        ),
      ]),
      floatingActionButton: index == 1
          ? null
          : FloatingActionButton.extended(
              onPressed: () => setState(() => index = 1),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Añadir libro'),
            ),
      bottomNavigationBar: NavigationBar(
        labelBehavior: Responsive.narrow(context) ? NavigationDestinationLabelBehavior.alwaysHide : NavigationDestinationLabelBehavior.alwaysShow,
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.library_books_outlined), selectedIcon: const Icon(Icons.library_books), label: c.tr('library')),
          NavigationDestination(icon: const Icon(Icons.add_box_outlined), selectedIcon: const Icon(Icons.add_box), label: c.tr('add')),
          NavigationDestination(icon: const Icon(Icons.query_stats_outlined), selectedIcon: const Icon(Icons.query_stats), label: c.tr('stats')),
          NavigationDestination(icon: const Icon(Icons.auto_graph_outlined), selectedIcon: const Icon(Icons.auto_graph), label: c.tr('wrapped')),
          NavigationDestination(icon: const Icon(Icons.local_florist_outlined), selectedIcon: const Icon(Icons.local_florist), label: c.tr('bookish')),
          NavigationDestination(icon: const Icon(Icons.tune_outlined), selectedIcon: const Icon(Icons.tune), label: c.tr('customization')),
        ],
      ),
    );
  }
}

Future<void> _importCsv(BuildContext context, AppController controller) async {
  final picked = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['csv'],
  );
  if (picked.isEmpty) return;

  final file = picked.single;
  String? text;
  try {
    final bytes = await file.readAsBytes();
    text = utf8.decode(bytes, allowMalformed: true);
  } catch (_) {
    if (file.path != null) {
      text = await File(file.path!).readAsString();
    }
  }
  if (text == null || text.trim().isEmpty) return;

  final rows = _parseCsv(text);
  if (rows.length < 2) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('El CSV no contiene filas de libros.')));
    return;
  }
  final header = rows.first.map(_norm).toList();
  var imported = 0;
  for (final row in rows.skip(1)) {
    if (row.every((cell) => cell.trim().isEmpty)) continue;
    String get(List<String> aliases) {
      final idx = header.indexWhere(aliases.contains);
      return idx >= 0 && idx < row.length ? row[idx].trim() : '';
    }

    final title = get(['title', 'titulo', 'título', 'book title', 'name']);
    if (title.isEmpty) continue;
    final author = get(['author', 'authors', 'autor', 'autora']);
    final pagesText = get(['pages', 'paginas', 'páginas', 'page count']);
    final ratingText = get(['rating', 'stars', 'puntuacion', 'puntuación']);
    final statusText = _norm(get(['status', 'estado', 'read status']));
    final dnf = _boolFromText(get(['dnf', 'did not finish'])) || statusText.contains('dnf');
    final status = _statusFromText(statusText, dnf);
    final start = _flexDate(get(['start date', 'started reading', 'fecha de comienzo', 'fecha inicio']));
    final end = _flexDate(get(['finish date', 'finished date', 'fecha de final', 'fecha fin']));
    final genres = _splitGenres(get(['genres', 'genre', 'generos', 'géneros']));

    await controller.addBook(Book(
      id: const Uuid().v4(),
      title: title,
      author: author,
      isbn: get(['isbn', 'isbn13', 'isbn-13']),
      pages: int.tryParse(pagesText.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
      format: get(['format', 'book format', 'formato']).isEmpty ? 'Físico' : get(['format', 'book format', 'formato']),
      genres: genres,
      startDate: start,
      endDate: end,
      dnf: dnf,
      status: status,
      rating: _clampQuarter(double.tryParse(ratingText.replaceAll(',', '.')) ?? 0),
      review: get(['review', 'notes', 'reseña', 'resena']),
    ));
    imported++;
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Importados $imported libros.')));
  }
}

List<List<String>> _parseCsv(String input) {
  final rows = <List<String>>[];
  final current = <String>[];
  var cell = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < input.length; i++) {
    final ch = input[i];
    if (ch == '"') {
      if (inQuotes && i + 1 < input.length && input[i + 1] == '"') {
        cell.write('"');
        i++;
      } else {
        inQuotes = !inQuotes;
      }
    } else if (ch == ',' && !inQuotes) {
      current.add(cell.toString());
      cell = StringBuffer();
    } else if (ch == '\n' && !inQuotes) {
      current.add(cell.toString().replaceAll('\r', ''));
      rows.add(List<String>.from(current));
      current.clear();
      cell = StringBuffer();
    } else {
      cell.write(ch);
    }
  }
  current.add(cell.toString().replaceAll('\r', ''));
  if (current.any((e) => e.isNotEmpty)) rows.add(current);
  return rows;
}

String _norm(String input) => input.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
bool _boolFromText(String s) => ['yes', 'true', '1', 'si', 'sí', 'dnf', 'unfinished'].contains(_norm(s));
BookStatus _statusFromText(String s, bool dnf) {
  if (dnf || s.contains('dnf')) return BookStatus.dnf;
  if (s.contains('read') || s.contains('finished') || s.contains('finish') || s.contains('final')) return BookStatus.finished;
  if (s.contains('currently') || s.contains('reading') || s.contains('leyendo')) return BookStatus.reading;
  return BookStatus.tbr;
}
DateTime? _flexDate(String value) {
  if (value.trim().isEmpty) return null;
  return DateTime.tryParse(value) ?? _tryFormats(value, const ['dd/MM/yyyy', 'MM/dd/yyyy', 'dd-MM-yyyy', 'yyyy/MM/dd']);
}
DateTime? _tryFormats(String value, List<String> patterns) {
  for (final pattern in patterns) {
    try {
      return DateFormat(pattern).parseStrict(value);
    } catch (_) {}
  }
  return null;
}
List<String> _splitGenres(String value) => value.split(RegExp(r'[|;,/]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
double _clampQuarter(double value) => (value * 4).round().clamp(0, 20).toDouble() / 4.0;

// ---------- TEXTS ----------

class AppTexts {
  static String text(String locale, String key) {
    const map = <String, Map<String, String>>{
      'es-ES': {
        'library': 'Biblioteca', 'add': 'Añadir', 'stats': 'Estadísticas', 'wrapped': 'Wrapped', 'bookish': 'Bookish', 'customization': 'Personalizar',
        'import_csv': 'Importar CSV', 'tbr': 'Por leer', 'dnf': 'DNF', 'reading': 'Leyendo', 'finished': 'Finalizado', 'books': 'libros',
        'new_book': 'Nuevo libro', 'save': 'Guardar libro', 'cover': 'Portada', 'title': 'Título', 'author': 'Autor/a', 'isbn': 'ISBN', 'pages': 'Páginas',
        'format': 'Formato de lectura', 'genres': 'Géneros literarios', 'start': 'Fecha de comienzo', 'end': 'Fecha de final', 'did_not_finish': 'No finalizado (DNF)',
        'spice': 'Spice', 'rating': 'Puntuación', 'emotions': 'Emociones', 'review': 'Reseña personal', 'search': 'Buscar…', 'display': 'Vista', 'empty': 'Todavía no hay libros en esta sección.',
        'overview': 'Resumen', 'total_books': 'Libros', 'total_pages': 'Páginas', 'avg_rating': 'Media', 'reading_speed': 'Ritmo', 'genres_read': 'Géneros',
        'format_mix': 'Formatos', 'wrapped_subtitle': 'Tu año lector, convertido en una historia visual.', 'bookish_subtitle': 'Crea una estantería cute para compartir.', 'export_share': 'Exportar y compartir',
        'palette': 'Gama cromática', 'style': 'Estilo', 'language': 'Idioma', 'typography': 'Tipografía', 'dark': 'Modo oscuro',
        'cozy': 'Cozy', 'romance': 'Romance', 'fantasy': 'Fantasía', 'gothic': 'Gótico', 'dark_academia': 'Dark academia', 'system': 'Sistema', 'mono': 'Máquina de escribir',
      },
      'eu': {
        'library': 'Liburutegia', 'add': 'Gehitu', 'stats': 'Estatistikak', 'wrapped': 'Wrapped', 'bookish': 'Bookish', 'customization': 'Pertsonalizatu',
        'import_csv': 'CSV inportatu', 'tbr': 'Irakurtzeko', 'dnf': 'DNF', 'reading': 'Irakurtzen', 'finished': 'Amaituta', 'books': 'liburu',
        'new_book': 'Liburu berria', 'save': 'Gorde liburua', 'cover': 'Azala', 'title': 'Izenburua', 'author': 'Egilea', 'isbn': 'ISBN', 'pages': 'Orrialdeak',
        'format': 'Irakurketa formatua', 'genres': 'Literatura generoak', 'start': 'Hasiera data', 'end': 'Amaiera data', 'did_not_finish': 'Ez amaitua (DNF)',
        'spice': 'Spice', 'rating': 'Puntuazioa', 'emotions': 'Emozioak', 'review': 'Nire iritzia', 'search': 'Bilatu…', 'display': 'Ikuspegia', 'empty': 'Atal honetan oraindik ez dago libururik.',
        'overview': 'Laburpena', 'total_books': 'Liburuak', 'total_pages': 'Orrialdeak', 'avg_rating': 'Batez bestekoa', 'reading_speed': 'Erritmoa', 'genres_read': 'Generoak',
        'format_mix': 'Formatuak', 'wrapped_subtitle': 'Zure irakurketa-urtea, istorio bisual bihurtuta.', 'bookish_subtitle': 'Sortu estanteria cute bat partekatzeko.', 'export_share': 'Esportatu eta partekatu',
        'palette': 'Kolore sorta', 'style': 'Estiloa', 'language': 'Hizkuntza', 'typography': 'Tipografia', 'dark': 'Modu iluna',
        'cozy': 'Cozy', 'romance': 'Erromantikoa', 'fantasy': 'Fantasia', 'gothic': 'Gotikoa', 'dark_academia': 'Dark academia', 'system': 'Sistema', 'mono': 'Idazmakina',
      },
      'es-LATAM': {
        'library': 'Biblioteca', 'add': 'Agregar', 'stats': 'Estadísticas', 'wrapped': 'Wrapped', 'bookish': 'Bookish', 'customization': 'Personalizar',
        'import_csv': 'Importar CSV', 'tbr': 'Por leer', 'dnf': 'DNF', 'reading': 'Leyendo', 'finished': 'Finalizado', 'books': 'libros',
        'new_book': 'Nuevo libro', 'save': 'Guardar libro', 'cover': 'Portada', 'title': 'Título', 'author': 'Autor/a', 'isbn': 'ISBN', 'pages': 'Páginas',
        'format': 'Formato de lectura', 'genres': 'Géneros literarios', 'start': 'Fecha de inicio', 'end': 'Fecha de finalización', 'did_not_finish': 'No terminado (DNF)',
        'spice': 'Spice', 'rating': 'Puntuación', 'emotions': 'Emociones', 'review': 'Reseña personal', 'search': 'Buscar…', 'display': 'Vista', 'empty': 'Aún no hay libros en esta sección.',
        'overview': 'Resumen', 'total_books': 'Libros', 'total_pages': 'Páginas', 'avg_rating': 'Promedio', 'reading_speed': 'Ritmo', 'genres_read': 'Géneros',
        'format_mix': 'Formatos', 'wrapped_subtitle': 'Tu año lector, convertido en una historia visual.', 'bookish_subtitle': 'Crea una estantería cute para compartir.', 'export_share': 'Exportar y compartir',
        'palette': 'Gama cromática', 'style': 'Estilo', 'language': 'Idioma', 'typography': 'Tipografía', 'dark': 'Modo oscuro',
        'cozy': 'Cozy', 'romance': 'Romance', 'fantasy': 'Fantasía', 'gothic': 'Gótico', 'dark_academia': 'Dark academia', 'system': 'Sistema', 'mono': 'Máquina de escribir',
      },
      'en-US': {
        'library': 'Library', 'add': 'Add', 'stats': 'Stats', 'wrapped': 'Wrapped', 'bookish': 'Bookish', 'customization': 'Customize',
        'import_csv': 'Import CSV', 'tbr': 'To read', 'dnf': 'DNF', 'reading': 'Reading', 'finished': 'Finished', 'books': 'books',
        'new_book': 'New book', 'save': 'Save book', 'cover': 'Cover', 'title': 'Title', 'author': 'Author', 'isbn': 'ISBN', 'pages': 'Pages',
        'format': 'Reading format', 'genres': 'Genres', 'start': 'Start date', 'end': 'Finish date', 'did_not_finish': 'Did not finish (DNF)',
        'spice': 'Spice', 'rating': 'Rating', 'emotions': 'Emotions', 'review': 'Personal review', 'search': 'Search…', 'display': 'View', 'empty': 'There are no books in this section yet.',
        'overview': 'Overview', 'total_books': 'Books', 'total_pages': 'Pages', 'avg_rating': 'Average', 'reading_speed': 'Pace', 'genres_read': 'Genres',
        'format_mix': 'Formats', 'wrapped_subtitle': 'Your reading year, turned into a visual story.', 'bookish_subtitle': 'Create a cute shelf to share.', 'export_share': 'Export & share',
        'palette': 'Color palette', 'style': 'Style', 'language': 'Language', 'typography': 'Typography', 'dark': 'Dark mode',
        'cozy': 'Cozy', 'romance': 'Romance', 'fantasy': 'Fantasy', 'gothic': 'Gothic', 'dark_academia': 'Dark academia', 'system': 'System', 'mono': 'Typewriter',
      },
      'en-GB': {
        'library': 'Library', 'add': 'Add', 'stats': 'Statistics', 'wrapped': 'Wrapped', 'bookish': 'Bookish', 'customization': 'Customise',
        'import_csv': 'Import CSV', 'tbr': 'To read', 'dnf': 'DNF', 'reading': 'Reading', 'finished': 'Finished', 'books': 'books',
        'new_book': 'New book', 'save': 'Save book', 'cover': 'Cover', 'title': 'Title', 'author': 'Author', 'isbn': 'ISBN', 'pages': 'Pages',
        'format': 'Reading format', 'genres': 'Genres', 'start': 'Start date', 'end': 'Finish date', 'did_not_finish': 'Did not finish (DNF)',
        'spice': 'Spice', 'rating': 'Rating', 'emotions': 'Emotions', 'review': 'Personal review', 'search': 'Search…', 'display': 'View', 'empty': 'There are no books in this section yet.',
        'overview': 'Overview', 'total_books': 'Books', 'total_pages': 'Pages', 'avg_rating': 'Average', 'reading_speed': 'Pace', 'genres_read': 'Genres',
        'format_mix': 'Formats', 'wrapped_subtitle': 'Your reading year, turned into a visual story.', 'bookish_subtitle': 'Create a cute shelf to share.', 'export_share': 'Export & share',
        'palette': 'Colour palette', 'style': 'Style', 'language': 'Language', 'typography': 'Typography', 'dark': 'Dark mode',
        'cozy': 'Cozy', 'romance': 'Romance', 'fantasy': 'Fantasy', 'gothic': 'Gothic', 'dark_academia': 'Dark academia', 'system': 'System', 'mono': 'Typewriter',
      },
      'fr': {
        'library': 'Bibliothèque', 'add': 'Ajouter', 'stats': 'Statistiques', 'wrapped': 'Wrapped', 'bookish': 'Bookish', 'customization': 'Personnaliser',
        'import_csv': 'Importer CSV', 'tbr': 'À lire', 'dnf': 'DNF', 'reading': 'En lecture', 'finished': 'Terminé', 'books': 'livres',
        'new_book': 'Nouveau livre', 'save': 'Enregistrer', 'cover': 'Couverture', 'title': 'Titre', 'author': 'Auteur·rice', 'isbn': 'ISBN', 'pages': 'Pages',
        'format': 'Format de lecture', 'genres': 'Genres littéraires', 'start': 'Date de début', 'end': 'Date de fin', 'did_not_finish': 'Non terminé (DNF)',
        'spice': 'Spice', 'rating': 'Note', 'emotions': 'Émotions', 'review': 'Avis personnel', 'search': 'Rechercher…', 'display': 'Vue', 'empty': 'Aucun livre dans cette section pour le moment.',
        'overview': 'Résumé', 'total_books': 'Livres', 'total_pages': 'Pages', 'avg_rating': 'Moyenne', 'reading_speed': 'Rythme', 'genres_read': 'Genres',
        'format_mix': 'Formats', 'wrapped_subtitle': 'Votre année de lecture en histoire visuelle.', 'bookish_subtitle': 'Créez une étagère cute à partager.', 'export_share': 'Exporter et partager',
        'palette': 'Palette', 'style': 'Style', 'language': 'Langue', 'typography': 'Typographie', 'dark': 'Mode sombre',
        'cozy': 'Cozy', 'romance': 'Romance', 'fantasy': 'Fantasy', 'gothic': 'Gothique', 'dark_academia': 'Dark academia', 'system': 'Système', 'mono': 'Machine à écrire',
      },
    };
    return map[locale]?[key] ?? map['es-ES']?[key] ?? key;
  }
}

// ---------- COMMON UI ----------

class Responsive {
  static double width(BuildContext context) => MediaQuery.sizeOf(context).width;
  static bool narrow(BuildContext context) => width(context) < 420;
  static bool medium(BuildContext context) => width(context) >= 600;
  static bool wide(BuildContext context) => width(context) >= 900;
  static bool twoColumnForm(BuildContext context) => width(context) >= 640;
  static double pagePad(BuildContext context, AppController controller) {
    final w = width(context);
    if (w < 380) return math.max(12, controller.pageHorizontalPadding - 4);
    if (w < 600) return math.min(18, controller.pageHorizontalPadding);
    return math.min(math.max(controller.pageHorizontalPadding, 20), 28);
  }
  static double contentWidth(BuildContext context, {double max = 860, double mobilePad = 12}) {
    final w = width(context);
    if (w < max + mobilePad * 2) return math.max(0, w - mobilePad * 2);
    return max;
  }
}

Widget _adaptivePair(BuildContext context, Widget first, Widget second, {double breakpoint = 640, double gap = 12}) => LayoutBuilder(
  builder: (context, constraints) {
    if (constraints.maxWidth >= breakpoint) {
      return Row(children: [Expanded(child: first), SizedBox(width: gap), Expanded(child: second)]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [first, SizedBox(height: gap), second]);
  },
);

class _VisualScope extends InheritedWidget {
  const _VisualScope({required this.controller, required super.child});
  final AppController controller;
  static _VisualScope? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_VisualScope>();
  @override
  bool updateShouldNotify(covariant _VisualScope oldWidget) => oldWidget.controller != controller;
}

class _AppDoodleBackground extends CustomPainter {
  const _AppDoodleBackground({required this.controller});
  final AppController controller;
  @override
  void paint(Canvas canvas, Size size) {
    if (!controller.doodles) return;
    final paint = Paint()
      ..color = controller.seedColor.withValues(alpha: controller.backgroundOpacity.clamp(.05, .24))
      ..style = PaintingStyle.stroke
      ..strokeWidth = controller.style == 'minimal' ? .9 : 1.15;
    final pattern = switch (controller.style) {
      'minimal' => 30.0,
      'gothic' || 'whimsigoth' || 'noir' => 17.0,
      'celestial' || 'fantasy' => 23.0,
      _ => 20.0,
    };

    for (var i = 0; i < 42; i++) {
      final x = 14 + (i * 83.0) % math.max(40, size.width - 28);
      final y = 20 + (i * 57.0) % math.max(40, size.height - 40);
      switch (controller.style) {
        case 'celestial':
          canvas.drawCircle(Offset(x, y), 3.5 + i % 4, paint);
          canvas.drawLine(Offset(x - 9, y), Offset(x + 9, y), paint);
          canvas.drawLine(Offset(x, y - 9), Offset(x, y + 9), paint);
          if (i.isEven) canvas.drawCircle(Offset(x + 11, y - 7), 1.7, paint);
          break;
        case 'fantasy':
          final path = Path()
            ..moveTo(x, y - 8)
            ..lineTo(x + 3.2, y - 2.2)
            ..lineTo(x + 9, y)
            ..lineTo(x + 3.2, y + 2.2)
            ..lineTo(x, y + 8)
            ..lineTo(x - 3.2, y + 2.2)
            ..lineTo(x - 9, y)
            ..lineTo(x - 3.2, y - 2.2)
            ..close();
          canvas.drawPath(path, paint);
          break;
        case 'botanical':
          canvas.drawLine(Offset(x - 2, y + 8), Offset(x + 5, y - 8), paint);
          canvas.drawOval(Rect.fromCenter(center: Offset(x - 2, y - 2), width: 7, height: 13), paint);
          canvas.drawOval(Rect.fromCenter(center: Offset(x + 3, y + 3), width: 7, height: 13), paint);
          break;
        case 'cozy':
        case 'cottagecore':
          canvas.drawArc(Rect.fromCenter(center: Offset(x, y), width: pattern, height: pattern * .65), -.8, 2.5, false, paint);
          canvas.drawCircle(Offset(x + 8, y - 5), 2.6, paint);
          break;
        case 'romance':
        case 'sakura':
          canvas.drawCircle(Offset(x, y - 3), 3.6, paint);
          canvas.drawCircle(Offset(x - 4, y + 2), 3.6, paint);
          canvas.drawCircle(Offset(x + 4, y + 2), 3.6, paint);
          canvas.drawCircle(Offset(x, y + 5), 3.3, paint);
          break;
        case 'gothic':
        case 'whimsigoth':
          canvas.drawLine(Offset(x - 8, y), Offset(x + 8, y), paint);
          canvas.drawLine(Offset(x, y - 8), Offset(x, y + 8), paint);
          canvas.drawCircle(Offset(x, y), 3.4, paint);
          break;
        case 'dark_academia':
        case 'parchment':
          canvas.drawLine(Offset(x - 8, y - 5), Offset(x + 8, y + 5), paint);
          canvas.drawLine(Offset(x - 8, y + 5), Offset(x + 8, y - 5), paint);
          canvas.drawLine(Offset(x - 7, y + 9), Offset(x + 7, y + 9), paint);
          break;
        case 'ocean':
          final wave = Path()
            ..moveTo(x - 10, y)
            ..quadraticBezierTo(x - 5, y - 7, x, y)
            ..quadraticBezierTo(x + 5, y + 7, x + 10, y);
          canvas.drawPath(wave, paint);
          break;
        case 'retro':
          canvas.drawRect(Rect.fromCenter(center: Offset(x, y), width: 11, height: 11), paint);
          canvas.drawCircle(Offset(x, y), 2.6, paint);
          break;
        case 'sunset':
          canvas.drawArc(Rect.fromCenter(center: Offset(x, y + 4), width: 18, height: 18), math.pi, math.pi, false, paint);
          for (var ray = 0; ray < 3; ray++) {
            final dx = (ray - 1) * 5.0;
            canvas.drawLine(Offset(x + dx, y - 8), Offset(x + dx, y - 12), paint);
          }
          break;
        case 'noir':
          canvas.drawLine(Offset(x - 9, y - 9), Offset(x + 9, y + 9), paint);
          canvas.drawLine(Offset(x - 9, y + 9), Offset(x + 9, y - 9), paint);
          break;
        case 'minimal':
          canvas.drawLine(Offset(x - 9, y), Offset(x + 9, y), paint);
          break;
        default:
          canvas.drawCircle(Offset(x, y), 2.4 + (i % 3), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _AppDoodleBackground oldDelegate) => true;
}

class PageIntro extends StatelessWidget {
  const PageIntro({super.key, required this.title, required this.subtitle});
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final controller = _VisualScope.maybeOf(context)?.controller;
    final pagePad = controller == null ? 18.0 : Responsive.pagePad(context, controller);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: Padding(
          padding: EdgeInsets.fromLTRB(pagePad, 12, pagePad, 16),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(pagePad, 17, pagePad, 19),
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [scheme.primaryContainer, scheme.surfaceContainerLow]),
              borderRadius: BorderRadius.circular(26),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 8, height: 28, decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(8))),
                const SizedBox(width: 12),
                Expanded(child: Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -.5))),
              ]),
              const SizedBox(height: 7),
              Text(subtitle, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, height: 1.35)),
            ]),
          ),
        ),
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.child, this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) {
    final c = _VisualScope.maybeOf(context)?.controller;
    final factor = c == null ? 1.0 : (c.spacing == 'roomy' ? 1.10 : c.spacing == 'compact' ? .94 : 1.0);
    final resolved = EdgeInsets.fromLTRB(padding.left * factor, padding.top * factor, padding.right * factor, padding.bottom * factor);
    final configuredMax = c?.contentMaxWidth ?? 840.0;
    final maxWidth = Responsive.width(context) >= 900 ? math.min(configuredMax, 980) : double.infinity;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SizedBox(
          width: double.infinity,
          child: Card(margin: const EdgeInsets.only(bottom: 12), child: Padding(padding: resolved, child: child)),
        ),
      ),
    );
  }
}

class BookCover extends StatelessWidget {
  const BookCover({super.key, required this.book, this.width = 100, this.height = 146});
  final Book book;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final exists = book.coverPath.isNotEmpty && File(book.coverPath).existsSync();
    final visual = _VisualScope.maybeOf(context)?.controller;
    final radius = switch (visual?.coverShape) {
      'soft' => 24.0,
      'square' => 6.0,
      'ticket' => 11.0,
      _ => 16.0,
    };
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: width,
        height: height,
        child: exists
            ? Image.file(File(book.coverPath), fit: BoxFit.cover)
            : Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [Theme.of(context).colorScheme.primaryContainer, Theme.of(context).colorScheme.secondaryContainer]),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(_genreIcon(book.genres), color: Theme.of(context).colorScheme.primary, size: 28),
                    Text(book.title.isEmpty ? 'Book' : book.title, maxLines: 5, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                  ]),
                ),
              ),
      ),
    );
  }
}

IconData _genreIcon(List<String> genres) {
  final text = genres.join(' ').toLowerCase();
  if (text.contains('fantas')) return Icons.auto_awesome_rounded;
  if (text.contains('romanc')) return Icons.favorite_rounded;
  if (text.contains('mister') || text.contains('thriller') || text.contains('polic')) return Icons.search_rounded;
  if (text.contains('terror')) return Icons.nightlight_round;
  if (text.contains('ciencia') || text.contains('science')) return Icons.science_rounded;
  if (text.contains('hist')) return Icons.history_edu_rounded;
  if (text.contains('poes')) return Icons.edit_note_rounded;
  return Icons.menu_book_rounded;
}

class RatingStars extends StatelessWidget {
  const RatingStars({super.key, required this.value, this.size = 18});
  final double value;
  final double size;
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: List.generate(5, (i) {
      final filled = value >= i + 1;
      final half = !filled && value >= i + 0.5;
      return Icon(half ? Icons.star_half : Icons.star, size: size, color: filled || half ? Theme.of(context).colorScheme.tertiary : Theme.of(context).colorScheme.outlineVariant);
    }));
  }
}

// ---------- LIBRARY ----------

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, required this.controller});
  final AppController controller;
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  BookStatus status = BookStatus.tbr;
  late ViewMode viewMode;
  String search = '';
  bool favoriteOnly = false;
  String sortMode = 'recent';

  @override
  void initState() {
    super.initState();
    viewMode = _viewFromKey(widget.controller.libraryDefaultView);
    sortMode = widget.controller.librarySort;
  }

  ViewMode _viewFromKey(String key) {
    switch (key) {
      case 'compact': return ViewMode.compact;
      case 'list': return ViewMode.list;
      case 'shelf': return ViewMode.shelf;
      default: return ViewMode.grid;
    }
  }

  List<Book> get filtered {
    final normalized = search.trim().toLowerCase();
    final result = widget.controller.books.where((b) {
      if (b.status != status) return false;
      if (favoriteOnly && !b.favorite) return false;
      if (normalized.isEmpty) return true;
      return b.title.toLowerCase().contains(normalized) ||
          b.author.toLowerCase().contains(normalized) ||
          b.genres.any((g) => g.toLowerCase().contains(normalized)) ||
          b.tags.any((t) => t.toLowerCase().contains(normalized));
    }).toList();
    result.sort((a, b) {
      if (widget.controller.favoritesFirst && a.favorite != b.favorite) {
        return a.favorite ? -1 : 1;
      }
      switch (sortMode) {
        case 'title':
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        case 'rating':
          return b.rating.compareTo(a.rating);
        case 'pages':
          return b.pages.compareTo(a.pages);
        default:
          final ad = a.endDate ?? a.startDate ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bd = b.endDate ?? b.startDate ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bd.compareTo(ad);
      }
    });
    return result;
  }

  String _statusLabel(BuildContext context, BookStatus value) {
    final c = widget.controller;
    switch (value) {
      case BookStatus.tbr: return c.tr('tbr');
      case BookStatus.reading: return c.tr('reading');
      case BookStatus.finished: return c.tr('finished');
      case BookStatus.dnf: return c.tr('dnf');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final reading = c.books.where((b) => b.status == BookStatus.reading).toList();
    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        PageIntro(title: c.tr('library'), subtitle: 'Tu biblioteca, tus estados y tus hábitos, organizados para que encontrar cualquier libro sea inmediato.'),
        if (reading.isNotEmpty && search.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: SectionCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.play_circle_outline_rounded, color: c.seedColor),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Continúa leyendo', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17))),
                  Text('${reading.length}', style: TextStyle(color: c.seedColor, fontWeight: FontWeight.w900)),
                ]),
                const SizedBox(height: 12),
                SizedBox(
                  height: 122,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: reading.length,
                    separatorBuilder: (context, index) => const SizedBox(width: 12),
                    itemBuilder: (_, i) {
                      final book = reading[i];
                      final progress = book.pages > 0 ? book.currentPage / book.pages : 0.0;
                      return InkWell(
                        onTap: () => _showBookDetails(context, c, book),
                        borderRadius: BorderRadius.circular(18),
                        child: SizedBox(width: Responsive.narrow(context) ? 214 : 235, child: Row(children: [
                          BookCover(book: book, width: 68, height: 102),
                          const SizedBox(width: 10),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                            Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
                            const SizedBox(height: 4),
                            Text(book.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                            const SizedBox(height: 8),
                            ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: progress, minHeight: 7)),
                            const SizedBox(height: 4),
                            Text(book.pages > 0 ? '${book.currentPage}/${book.pages} pág.' : 'Añade las páginas para ver el progreso', style: Theme.of(context).textTheme.labelSmall),
                          ])),
                        ])),
                      );
                    },
                  ),
                ),
              ]),
            ),
          ),
        const SizedBox(height: 8),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: Responsive.pagePad(context, c)),
          child: TextField(
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: c.tr('search'), suffixIcon: search.isEmpty ? null : IconButton(onPressed: () => setState(() => search = ''), icon: const Icon(Icons.close_rounded))),
            onChanged: (v) => setState(() => search = v),
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: Responsive.pagePad(context, c)),
          child: Row(children: [
            for (final s in BookStatus.values)
              _StatusChip(label: _statusLabel(context, s), count: c.books.where((b) => b.status == s).length, selected: status == s, onTap: () => setState(() { status = s; favoriteOnly = false; })),
            FilterChip(avatar: const Icon(Icons.favorite_rounded, size: 18), label: const Text('Favoritos'), selected: favoriteOnly, onSelected: (value) => setState(() => favoriteOnly = value)),
          ]),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: Responsive.pagePad(context, c)),
          child: LayoutBuilder(builder: (context, constraints) {
            final wide = constraints.maxWidth >= 720;
            final orderField = DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: ['recent', 'title', 'rating', 'pages'].contains(sortMode) ? sortMode : 'recent',
              decoration: const InputDecoration(labelText: 'Ordenar por'),
              items: const [
                DropdownMenuItem(value: 'recent', child: Text('Más recientes')), DropdownMenuItem(value: 'title', child: Text('Título A–Z')), DropdownMenuItem(value: 'rating', child: Text('Mejor valoración')), DropdownMenuItem(value: 'pages', child: Text('Más páginas')),
              ],
              onChanged: (value) => setState(() => sortMode = value ?? 'recent'),
            );
            final views = SegmentedButton<ViewMode>(
              segments: const [ButtonSegment(value: ViewMode.grid, icon: Icon(Icons.grid_view_rounded)), ButtonSegment(value: ViewMode.compact, icon: Icon(Icons.apps_rounded)), ButtonSegment(value: ViewMode.list, icon: Icon(Icons.view_list_rounded)), ButtonSegment(value: ViewMode.shelf, icon: Icon(Icons.view_carousel_rounded))],
              selected: {viewMode},
              onSelectionChanged: (value) => setState(() => viewMode = value.first),
              showSelectedIcon: false,
              style: const ButtonStyle(tapTargetSize: MaterialTapTargetSize.padded),
            );
            if (wide) {
              return Row(children: [Expanded(child: orderField), const SizedBox(width: 14), Flexible(flex: 0, child: views)]);
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [orderField, const SizedBox(height: 10), SingleChildScrollView(scrollDirection: Axis.horizontal, child: views)]);
          }),
        ),
        const SizedBox(height: 14),
        if (filtered.isEmpty)
          Padding(padding: const EdgeInsets.all(32), child: Column(children: [Icon(Icons.auto_stories_outlined, size: 42, color: Theme.of(context).colorScheme.outline), const SizedBox(height: 10), Text(c.tr('empty'), textAlign: TextAlign.center)]))
        else
          Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: _buildView(filtered)),
      ],
    );
  }

  Widget _buildView(List<Book> books) {
    switch (viewMode) {
      case ViewMode.list:
        return Column(children: books.map((b) => _BookListTile(book: b, controller: widget.controller)).toList());
      case ViewMode.compact:
        return LayoutBuilder(builder: (context, constraints) {
          final w = constraints.maxWidth;
          final columns = w < 420 ? 3 : w < 700 ? 4 : w < 1050 ? 5 : 6;
          final gap = w < 600 ? 10.0 : 14.0;
          final cell = (w - gap * (columns - 1)) / columns;
          final coverW = math.min(cell * .78, 92.0);
          final extent = coverW * 1.46 + 48;
          return GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: books.length, gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: columns, crossAxisSpacing: gap, mainAxisSpacing: 18, mainAxisExtent: extent), itemBuilder: (_, i) => _BookGridItem(book: books[i], controller: widget.controller, compact: true));
        });
      case ViewMode.shelf:
        return _ShelfView(books: books, controller: widget.controller);
      case ViewMode.grid:
        return LayoutBuilder(builder: (context, constraints) {
          final w = constraints.maxWidth;
          final columns = w < 420 ? 2 : w < 680 ? 3 : w < 980 ? 4 : 5;
          final gap = w < 600 ? 13.0 : 18.0;
          final cell = (w - gap * (columns - 1)) / columns;
          final coverW = math.min(cell * .76, 155.0);
          final extent = coverW * 1.46 + 78;
          return GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: books.length, gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: columns, crossAxisSpacing: gap, mainAxisSpacing: 24, mainAxisExtent: extent), itemBuilder: (_, i) => _BookGridItem(book: books[i], controller: widget.controller));
        });
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.count, required this.selected, required this.onTap});
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: FilterChip(label: Text('$label  $count'), selected: selected, onSelected: (_) => onTap()),
      );
}

class _BookGridItem extends StatelessWidget {
  const _BookGridItem({required this.book, required this.controller, this.compact = false});
  final Book book;
  final AppController controller;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final progress = book.pages > 0 ? (book.currentPage / book.pages).clamp(0.0, 1.0) : 0.0;
    return LayoutBuilder(builder: (context, constraints) {
      final coverWidth = math.min(constraints.maxWidth * (compact ? .78 : .76), compact ? 92.0 : 155.0);
      final coverHeight = coverWidth * 1.46;
      return InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _showBookDetails(context, controller, book),
        child: Stack(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: BookCover(book: book, width: coverWidth, height: coverHeight)),
            const SizedBox(height: 9),
          Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
          if (!compact && controller.showAuthorOnCards) Text(book.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
          if (!compact && controller.showProgressOnCards && book.pages > 0 && book.currentPage > 0) ...[
            const SizedBox(height: 5),
            ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: progress, minHeight: 5)),
          ],
          if (book.rating > 0) Padding(padding: const EdgeInsets.only(top: 4), child: RatingStars(value: book.rating, size: compact ? 11 : 14)),
        ]),
        Positioned(
          top: 0,
          right: 0,
          child: Material(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: .9),
            shape: const CircleBorder(),
            child: IconButton(
              constraints: const BoxConstraints.tightFor(width: 38, height: 38),
              padding: EdgeInsets.zero,
              tooltip: book.favorite ? 'Quitar de favoritos' : 'Añadir a favoritos',
              onPressed: () => controller.toggleFavorite(book.id),
              icon: Icon(book.favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded, size: 19, color: book.favorite ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        ),
        if (book.readCount > 1)
          Positioned(left: 0, top: 0, child: CircleAvatar(radius: 16, backgroundColor: Theme.of(context).colorScheme.primary, child: Text('${book.readCount}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)))),
      ]),
      );
    });
  }
}

class _BookListTile extends StatelessWidget {
  const _BookListTile({required this.book, required this.controller});
  final Book book;
  final AppController controller;
  @override
  Widget build(BuildContext context) {
    final progress = book.pages > 0 ? (book.currentPage / book.pages).clamp(0.0, 1.0) : 0.0;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.all(10),
        leading: BookCover(book: book, width: 54, height: 80),
        title: Row(children: [Expanded(child: Text(book.title, style: const TextStyle(fontWeight: FontWeight.w800))), if (book.favorite) Icon(Icons.favorite_rounded, size: 18, color: Theme.of(context).colorScheme.error)]),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 2),
          Text([book.author, if (book.pages > 0) '${book.pages} pág.', if (book.format.isNotEmpty) book.format].where((s) => s.isNotEmpty).join(' · ')),
          if (controller.showProgressOnCards && book.pages > 0 && book.currentPage > 0) ...[
            const SizedBox(height: 6),
            ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: progress, minHeight: 5)),
            const SizedBox(height: 2),
            Text('${book.currentPage}/${book.pages} pág.', style: Theme.of(context).textTheme.labelSmall),
          ],
        ]),
        trailing: book.readCount > 1 ? CircleAvatar(radius: 16, child: Text('${book.readCount}')) : null,
        onTap: () => _showBookDetails(context, controller, book),
      ),
    );
  }
}

class _ShelfView extends StatelessWidget {
  const _ShelfView({required this.books, required this.controller});
  final List<Book> books;
  final AppController controller;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 18, 14, 20),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(22)),
        child: Column(children: [
          SizedBox(height: 220, child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: books.take(8).map((b) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Transform.rotate(angle: ((b.title.hashCode % 7) - 3) * .008, child: BookCover(book: b, width: 44, height: 168))))).toList())),
          Container(height: 20, decoration: BoxDecoration(gradient: LinearGradient(colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.secondary]), borderRadius: BorderRadius.circular(7), boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.primary.withValues(alpha: .25), blurRadius: 12, offset: const Offset(0, 5))])),
          const SizedBox(height: 8),
          const Text('Estantería', style: TextStyle(fontWeight: FontWeight.w800)),
        ]),
      );
}

Future<void> _showBookDetails(BuildContext context, AppController controller, Book book) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(left: 18, right: 18, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [BookCover(book: book, width: 110, height: 164), const SizedBox(width: 16), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(book.title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text(book.author), const SizedBox(height: 12), RatingStars(value: book.rating, size: 21), if (book.readCount > 1) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Leído ${book.readCount} veces'))]))]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: FilledButton.tonalIcon(onPressed: () => controller.toggleFavorite(book.id), icon: Icon(book.favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded), label: Text(book.favorite ? 'Favorito' : 'Guardar favorito'))),
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton.icon(onPressed: () async { await controller.rereadBook(book.id); if (context.mounted) Navigator.pop(context); }, icon: const Icon(Icons.replay_rounded), label: const Text('Volver a leer'))),
          ]),
          if (book.pages > 0) ...[
            const SizedBox(height: 14),
            Row(children: [const Text('Progreso', style: TextStyle(fontWeight: FontWeight.w800)), const Spacer(), Text('${book.currentPage}/${book.pages}')]),
            Slider(value: book.currentPage.toDouble().clamp(0, book.pages.toDouble()), min: 0, max: book.pages.toDouble(), divisions: math.min(book.pages, 100), onChanged: (v) => controller.updateProgress(book.id, v.round())),
          ],
          const SizedBox(height: 18),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ...book.genres.map((g) => Chip(label: Text(g))),
            if (book.format.isNotEmpty) Chip(label: Text(book.format)),
            if (book.spice > 0) Chip(label: Text('Spice ${book.spice.toStringAsFixed(book.spice.truncateToDouble() == book.spice ? 0 : 2)}')),
          ]),
          if (book.review.isNotEmpty) ...[const SizedBox(height: 14), Text(book.review)],
          if (book.readingSessions.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('Sesiones de lectura', style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            ...book.readingSessions.reversed.take(8).map((session) => Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(children: [
                    Icon(Icons.menu_book_rounded, size: 17, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 7),
                    Text(DateFormat('dd/MM/yyyy').format(session.date)),
                    const Spacer(),
                    if (session.pages > 0) Text('${session.pages} pág.'),
                    if (session.note.isNotEmpty) ...[const SizedBox(width: 8), Flexible(child: Text(session.note, overflow: TextOverflow.ellipsis))],
                  ]),
                )),
          ],
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: () => _addReadingSession(context, controller, book),
            icon: const Icon(Icons.add_chart_rounded),
            label: const Text('Registrar sesión de lectura'),
          ),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: FilledButton.icon(onPressed: () async { Navigator.pop(context); await _editBook(context, controller, book); }, icon: const Icon(Icons.edit_outlined), label: const Text('Editar'))),
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton.icon(onPressed: () async { await controller.deleteBook(book.id); if (context.mounted) Navigator.pop(context); }, icon: const Icon(Icons.delete_outline), label: const Text('Eliminar'))),
          ]),
        ]),
      ),
    ),
  );
}

Future<void> _addReadingSession(BuildContext context, AppController controller, Book book) async {
  DateTime date = DateTime.now();
  final pages = TextEditingController();
  final note = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('Registrar lectura'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_today_rounded),
            title: const Text('Fecha'),
            subtitle: Text(DateFormat('dd/MM/yyyy').format(date)),
            onTap: () async {
              final picked = await showDatePicker(context: dialogContext, firstDate: DateTime(1950), lastDate: DateTime(2100), initialDate: date);
              if (picked != null) setDialogState(() => date = picked);
            },
          ),
          TextField(controller: pages, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Páginas leídas', prefixIcon: Icon(Icons.auto_stories_rounded))),
          const SizedBox(height: 10),
          TextField(controller: note, maxLines: 3, decoration: const InputDecoration(labelText: 'Nota del día', prefixIcon: Icon(Icons.notes_rounded))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancelar')),
          FilledButton(onPressed: () async {
            await controller.addSession(book.id, ReadingSession(date: date, pages: int.tryParse(pages.text.trim()) ?? 0, note: note.text.trim()));
            if (dialogContext.mounted) Navigator.pop(dialogContext);
          }, child: const Text('Guardar')),
        ],
      ),
    ),
  );
  pages.dispose();
  note.dispose();
}

Future<void> _editBook(BuildContext context, AppController controller, Book book) async {
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => AddBookPage(controller: controller, existing: book)));
}

// ---------- ADD BOOK ----------

class AddBookPage extends StatefulWidget {
  const AddBookPage({super.key, required this.controller, this.existing});
  final AppController controller;
  final Book? existing;
  @override
  State<AddBookPage> createState() => _AddBookPageState();
}

class _AddBookPageState extends State<AddBookPage> {
  late final TextEditingController title;
  late final TextEditingController author;
  late final TextEditingController isbn;
  late final TextEditingController pages;
  late final TextEditingController format;
  late final TextEditingController genres;
  late final TextEditingController tags;
  late final TextEditingController review;
  late double spice;
  late double rating;
  late BookStatus status;
  late bool dnf;
  late bool favorite;
  late int currentPage;
  late Map<String, double> emotions;
  late DateTime? startDate;
  late DateTime? endDate;
  String coverPath = '';

  final emotionOptions = const ['Feliz', 'Tierna', 'Tensa', 'Triste', 'Enfado', 'Asombro', 'Calma', 'Ansiedad', 'Nostalgia', 'Enamoramiento'];
  final genreOptions = const ['Romance', 'Fantasía', 'Misterio', 'Thriller', 'Ciencia ficción', 'Contemporánea', 'Histórica', 'Juvenil', 'Terror', 'Literaria', 'Policíaca', 'No ficción', 'Poesía', 'Autobiografía'];

  @override
  void initState() {
    super.initState();
    final b = widget.existing;
    title = TextEditingController(text: b?.title ?? '');
    author = TextEditingController(text: b?.author ?? '');
    isbn = TextEditingController(text: b?.isbn ?? '');
    pages = TextEditingController(text: b?.pages.toString() ?? '');
    format = TextEditingController(text: b?.format ?? 'Físico');
    genres = TextEditingController(text: b?.genres.join(', ') ?? '');
    tags = TextEditingController(text: b?.tags.join(', ') ?? '');
    review = TextEditingController(text: b?.review ?? '');
    spice = b?.spice ?? 0;
    rating = b?.rating ?? 0;
    status = b?.status ?? BookStatus.tbr;
    dnf = b?.dnf ?? false;
    favorite = b?.favorite ?? false;
    currentPage = b?.currentPage ?? 0;
    startDate = b?.startDate;
    endDate = b?.endDate;
    emotions = Map<String, double>.from(b?.emotions ?? {});
    coverPath = b?.coverPath ?? '';
  }

  @override
  void dispose() {
    title.dispose(); author.dispose(); isbn.dispose(); pages.dispose(); format.dispose(); genres.dispose(); tags.dispose(); review.dispose();
    super.dispose();
  }

  Future<void> pickCover() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1200, imageQuality: 88);
    if (picked == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final ext = picked.name.contains('.') ? picked.name.split('.').last : 'jpg';
    final target = File('${dir.path}/cover_${const Uuid().v4()}.$ext');
    await target.writeAsBytes(await picked.readAsBytes());
    setState(() => coverPath = target.path);
  }

  Future<void> chooseDate({required bool start}) async {
    final value = await showDatePicker(context: context, firstDate: DateTime(1950), lastDate: DateTime(2100), initialDate: (start ? startDate : endDate) ?? DateTime.now());
    if (value == null) return;
    setState(() { if (start) { startDate = value; } else { endDate = value; } });
  }

  Future<void> saveBook() async {
    if (title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('El título es obligatorio.')));
      return;
    }
    final book = Book(
      id: widget.existing?.id ?? const Uuid().v4(),
      title: title.text.trim(),
      author: author.text.trim(),
      isbn: isbn.text.trim(),
      pages: int.tryParse(pages.text.trim()) ?? 0,
      format: format.text.trim(),
      genres: _splitGenres(genres.text),
      tags: _splitGenres(tags.text),
      startDate: startDate,
      endDate: endDate,
      dnf: dnf,
      status: dnf ? BookStatus.dnf : status,
      favorite: favorite,
      currentPage: currentPage,
      spice: spice,
      rating: rating,
      emotions: emotions,
      review: review.text.trim(),
      coverPath: coverPath,
      readCount: widget.existing?.readCount ?? 1,
    );
    if (widget.existing == null) {
      await widget.controller.addBook(book);
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Libro guardado.'))); }
    } else {
      await widget.controller.updateBook(book);
      if (mounted) Navigator.pop(context);
      return;
    }
    title.clear(); author.clear(); isbn.clear(); pages.clear(); genres.clear(); tags.clear(); review.clear(); setState(() { coverPath = ''; rating = 0; spice = 0; dnf = false; favorite = false; currentPage = 0; status = BookStatus.tbr; emotions = {}; startDate = null; endDate = null; });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final isEditing = widget.existing != null;
    return ListView(padding: const EdgeInsets.fromLTRB(18, 10, 18, 30), children: [
      PageIntro(title: isEditing ? 'Editar libro' : c.tr('new_book'), subtitle: 'Registra portada, datos de lectura, emociones y tu experiencia personal.'),
      SectionCard(child: Column(children: [
        Align(alignment: Alignment.centerLeft, child: Text(c.tr('cover'), style: const TextStyle(fontWeight: FontWeight.w800))),
        const SizedBox(height: 12),
        Row(children: [
          BookCover(book: Book(id: 'temp', title: title.text, coverPath: coverPath), width: 100, height: 148),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [OutlinedButton.icon(onPressed: pickCover, icon: const Icon(Icons.photo_library_outlined), label: const Text('Elegir portada')), if (coverPath.isNotEmpty) TextButton.icon(onPressed: () => setState(() => coverPath = ''), icon: const Icon(Icons.close), label: const Text('Quitar'))])),
        ]),
      ])),
      const SizedBox(height: 14),
      SectionCard(child: Column(children: [
        _field(title, c.tr('title'), Icons.title_rounded),
        _field(author, c.tr('author'), Icons.person_outline_rounded),
        _field(isbn, c.tr('isbn'), Icons.qr_code_2_rounded),
        Row(children: [Expanded(child: _field(pages, c.tr('pages'), Icons.menu_book_outlined, keyboard: TextInputType.number, onChanged: (_) => setState(() {}))), const SizedBox(width: 12), Expanded(child: _field(format, c.tr('format'), Icons.import_contacts_outlined))]),
        _field(genres, c.tr('genres'), Icons.category_outlined, hint: 'Romance, Fantasía, Misterio…'),
        Align(alignment: Alignment.centerLeft, child: Text('Géneros rápidos', style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800))),
        const SizedBox(height: 8),
        Wrap(spacing: 7, runSpacing: 7, children: genreOptions.map((genre) {
          final selected = _splitGenres(genres.text).map(_norm).contains(_norm(genre));
          return FilterChip(label: Text(genre), selected: selected, onSelected: (_) {
            final current = _splitGenres(genres.text);
            if (selected) { current.removeWhere((e) => _norm(e) == _norm(genre)); } else { current.add(genre); }
            genres.text = current.join(', ');
            setState(() {});
          });
        }).toList()),
        const SizedBox(height: 10),
        _field(tags, 'Etiquetas personales', Icons.label_outline_rounded, hint: 'Comfort read, favorito, club…'),
        DropdownButtonFormField<BookStatus>(initialValue: status, decoration: InputDecoration(labelText: 'Estado'), items: [
          DropdownMenuItem(value: BookStatus.tbr, child: Text(c.tr('tbr'))),
          DropdownMenuItem(value: BookStatus.reading, child: Text(c.tr('reading'))),
          DropdownMenuItem(value: BookStatus.finished, child: Text(c.tr('finished'))),
          DropdownMenuItem(value: BookStatus.dnf, child: Text(c.tr('dnf'))),
        ], onChanged: (v) => setState(() => status = v ?? BookStatus.tbr)),
        SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, title: Text(c.tr('did_not_finish')), value: dnf, onChanged: (v) => setState(() => dnf = v)),
      ])),
      const SizedBox(height: 14),
      SectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Fechas', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        Row(children: [Expanded(child: OutlinedButton.icon(onPressed: () => chooseDate(start: true), icon: const Icon(Icons.calendar_month_outlined), label: Text(startDate == null ? c.tr('start') : DateFormat('dd/MM/yyyy').format(startDate!)))), const SizedBox(width: 10), Expanded(child: OutlinedButton.icon(onPressed: () => chooseDate(start: false), icon: const Icon(Icons.event_available_outlined), label: Text(endDate == null ? c.tr('end') : DateFormat('dd/MM/yyyy').format(endDate!))))]),
      ])),
      const SizedBox(height: 14),
      SectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, title: const Text('Guardar en favoritos'), subtitle: const Text('Aparecerá en el filtro Favoritos de la biblioteca.'), value: favorite, onChanged: (v) => setState(() => favorite = v)),
        if (pages.text.trim().isNotEmpty && (int.tryParse(pages.text.trim()) ?? 0) > 0) ...[
          Row(children: [const Text('Página actual', style: TextStyle(fontWeight: FontWeight.w800)), const Spacer(), Text('$currentPage / ${pages.text.trim()}')]),
          Slider(value: currentPage.toDouble().clamp(0, math.max(1, int.tryParse(pages.text.trim()) ?? 1).toDouble()), min: 0, max: math.max(1, int.tryParse(pages.text.trim()) ?? 1).toDouble(), divisions: math.min(math.max(1, int.tryParse(pages.text.trim()) ?? 1), 100), onChanged: (v) => setState(() => currentPage = v.round())),
        ],
      ])),
      const SizedBox(height: 14),
      SectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(c.tr('rating'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        _RatingEditor(value: rating, onChanged: (v) => setState(() => rating = v)),
        const SizedBox(height: 12),
        _MetricAdjuster(
          label: c.tr('spice'),
          value: spice,
          min: 0,
          max: 5,
          step: .25,
          onChanged: (v) => setState(() => spice = v),
          icon: Icons.local_fire_department_rounded,
          accent: Colors.deepOrange,
        ),
      ])),
      const SizedBox(height: 14),
      SectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(c.tr('emotions'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        ...emotionOptions.map((emotion) {
          final value = emotions[emotion] ?? 0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _MetricAdjuster(
              label: emotion,
              value: value,
              min: 0,
              max: 5,
              step: 1,
              onChanged: (v) => setState(() => emotions[emotion] = v),
              icon: Icons.favorite_rounded,
              accent: Theme.of(context).colorScheme.secondary,
            ),
          );
        }),
      ])),
      const SizedBox(height: 14),
      SectionCard(child: TextField(controller: review, minLines: 5, maxLines: 10, decoration: InputDecoration(labelText: c.tr('review'), alignLabelWithHint: true))),
      const SizedBox(height: 18),
      FilledButton.icon(onPressed: saveBook, icon: const Icon(Icons.check_rounded), label: Text(c.tr('save')), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54))),
    ]);
  }

  Widget _field(TextEditingController controller, String label, IconData icon, {String? hint, TextInputType? keyboard, ValueChanged<String>? onChanged}) => Padding(padding: const EdgeInsets.only(bottom: 12), child: TextField(controller: controller, onChanged: onChanged, keyboardType: keyboard, decoration: InputDecoration(prefixIcon: Icon(icon), labelText: label, hintText: hint)));
}

class _MetricAdjuster extends StatelessWidget {
  const _MetricAdjuster({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
    this.icon,
    this.accent,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final double step;
  final ValueChanged<double> onChanged;
  final IconData? icon;
  final Color? accent;

  double _snap(double next) {
    final steps = ((next - min) / step).round();
    return (min + steps * step).clamp(min, max).toDouble();
  }

  String _format(double v) {
    if ((v - v.roundToDouble()).abs() < .0001) {
      return '${v.round()}';
    }
    return v.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }

  @override
  Widget build(BuildContext context) {
    final color = accent ?? Theme.of(context).colorScheme.primary;
    final canDecrease = value > min + .0001;
    final canIncrease = value < max - .0001;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: .16)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (icon != null) ...[Icon(icon, size: 18, color: color), const SizedBox(width: 8)],
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800))),
          Container(
            constraints: const BoxConstraints(minWidth: 58),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(12)),
            child: Text(_format(value), textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900, color: color)),
          ),
        ]),
        Row(children: [
          IconButton.filledTonal(
            tooltip: 'Bajar',
            onPressed: canDecrease ? () => onChanged(_snap(value - step)) : null,
            icon: const Icon(Icons.remove_rounded),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: color,
                thumbColor: color,
                overlayColor: color.withValues(alpha: .12),
                valueIndicatorColor: color,
              ),
              child: Slider(
                value: _snap(value),
                min: min,
                max: max,
                divisions: ((max - min) / step).round(),
                label: _format(_snap(value)),
                onChanged: (v) => onChanged(_snap(v)),
              ),
            ),
          ),
          IconButton.filledTonal(
            tooltip: 'Subir',
            onPressed: canIncrease ? () => onChanged(_snap(value + step)) : null,
            icon: const Icon(Icons.add_rounded),
          ),
        ]),
      ]),
    );
  }
}

class _RatingEditor extends StatelessWidget {
  const _RatingEditor({required this.value, required this.onChanged});
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => _MetricAdjuster(
        label: 'Valoración del libro',
        value: value,
        min: 0,
        max: 5,
        step: .25,
        onChanged: onChanged,
        icon: Icons.star_rounded,
        accent: Theme.of(context).colorScheme.primary,
      );
}
// ---------- READING CHALLENGES ----------

class ChallengesPage extends StatefulWidget {
  const ChallengesPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<ChallengesPage> createState() => _ChallengesPageState();
}

class _ChallengesPageState extends State<ChallengesPage> {
  String preset = 'annual';
  final title = TextEditingController();
  final target = TextEditingController(text: '24');
  ChallengeMetric metric = ChallengeMetric.books;
  DateTime startDate = DateTime(DateTime.now().year, 1, 1);
  DateTime endDate = DateTime(DateTime.now().year, 12, 31);

  @override
  void dispose() {
    title.dispose();
    target.dispose();
    super.dispose();
  }

  void applyPreset(String value) {
    final now = DateTime.now();
    setState(() {
      preset = value;
      if (value == 'annual') {
        startDate = DateTime(now.year, 1, 1);
        endDate = DateTime(now.year, 12, 31);
        title.text = title.text.trim().isEmpty ? 'Mi reto lector ${now.year}' : title.text;
        target.text = target.text.trim().isEmpty ? '24' : target.text;
      } else if (value == 'monthly') {
        startDate = DateTime(now.year, now.month, 1);
        endDate = DateTime(now.year, now.month + 1, 0);
        title.text = title.text.trim().isEmpty ? 'Reto lector de ${DateFormat('MMMM', 'es_ES').format(now)}' : title.text;
        target.text = target.text.trim().isEmpty ? '3' : target.text;
      } else {
        title.text = title.text.trim().isEmpty ? 'Reto lector personalizado' : title.text;
      }
    });
  }

  Future<void> pickDate(bool start) async {
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime(1950),
      lastDate: DateTime(2100),
      initialDate: start ? startDate : endDate,
    );
    if (selected == null) return;
    setState(() {
      if (start) {
        startDate = selected;
        if (endDate.isBefore(startDate)) endDate = startDate;
      } else {
        endDate = selected;
        if (endDate.isBefore(startDate)) startDate = endDate;
      }
      preset = 'custom';
    });
  }

  Future<void> createChallenge() async {
    final count = int.tryParse(target.text.trim());
    if (count == null || count <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Indica una meta mayor que 0.')));
      return;
    }
    final challenge = ReadingChallenge(
      id: const Uuid().v4(),
      title: title.text.trim().isEmpty ? 'Reto lector' : title.text.trim(),
      startDate: startDate,
      endDate: endDate,
      target: count,
      metric: metric,
    );
    await widget.controller.addChallenge(challenge);
    if (!mounted) return;
    title.clear();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reto creado.')));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      appBar: AppBar(title: const Text('Retos lectores'), centerTitle: false),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
        children: [
          PageIntro(
            title: 'Tu meta, a tu manera',
            subtitle: 'Crea un reto anual, mensual o con cualquier intervalo de fechas y síguelo visualmente.',
          ),
          SectionCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Periodo', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'annual', label: Text('Anual'), icon: Icon(Icons.calendar_today_rounded)),
                  ButtonSegment(value: 'monthly', label: Text('Mensual'), icon: Icon(Icons.calendar_month_rounded)),
                  ButtonSegment(value: 'custom', label: Text('A medida'), icon: Icon(Icons.date_range_rounded)),
                ],
                selected: {preset},
                onSelectionChanged: (selection) => applyPreset(selection.first),
                showSelectedIcon: false,
              ),
              const SizedBox(height: 14),
              TextField(controller: title, decoration: const InputDecoration(labelText: 'Nombre del reto', prefixIcon: Icon(Icons.edit_note_rounded))),
              const SizedBox(height: 12),
              DropdownButtonFormField<ChallengeMetric>(
                initialValue: metric,
                decoration: const InputDecoration(labelText: 'Qué quieres conseguir'),
                items: const [
                  DropdownMenuItem(value: ChallengeMetric.books, child: Text('Libros terminados')),
                  DropdownMenuItem(value: ChallengeMetric.pages, child: Text('Páginas leídas')),
                  DropdownMenuItem(value: ChallengeMetric.readingDays, child: Text('Días de lectura')),
                ],
                onChanged: (value) => setState(() => metric = value ?? metric),
              ),
              const SizedBox(height: 12),
              TextField(controller: target, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Meta', prefixIcon: Icon(Icons.flag_rounded))),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: OutlinedButton.icon(onPressed: () => pickDate(true), icon: const Icon(Icons.event_outlined), label: Text(DateFormat('dd/MM/yyyy').format(startDate)))),
                const SizedBox(width: 10),
                Expanded(child: OutlinedButton.icon(onPressed: () => pickDate(false), icon: const Icon(Icons.event_available_outlined), label: Text(DateFormat('dd/MM/yyyy').format(endDate)))),
              ]),
              const SizedBox(height: 14),
              FilledButton.icon(onPressed: createChallenge, icon: const Icon(Icons.add_task_rounded), label: const Text('Crear reto'), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52))),
            ]),
          ),
          const SizedBox(height: 18),
          const Text('Mis retos', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 10),
          if (c.challenges.isEmpty)
            SectionCard(child: Column(children: [Icon(Icons.flag_circle_outlined, size: 44, color: Theme.of(context).colorScheme.primary), const SizedBox(height: 8), const Text('Aún no tienes retos. Crea el primero arriba.', textAlign: TextAlign.center)]))
          else
            ...c.challenges.map((challenge) {
              final progress = c.challengeProgress(challenge);
              final ratio = (progress / challenge.target).clamp(0.0, 1.0);
              final totalDays = challenge.endDate.difference(DateTime(challenge.startDate.year, challenge.startDate.month, challenge.startDate.day)).inDays + 1;
              final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
              final start = DateTime(challenge.startDate.year, challenge.startDate.month, challenge.startDate.day);
              final end = DateTime(challenge.endDate.year, challenge.endDate.month, challenge.endDate.day);
              final elapsedDays = today.isBefore(start) ? 0 : (today.isAfter(end) ? totalDays : today.difference(start).inDays + 1);
              final timeRatio = (elapsedDays / math.max(totalDays, 1)).clamp(0.0, 1.0);
              return SectionCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    CircleAvatar(backgroundColor: c.seedColor.withValues(alpha: .15), child: Icon(challenge.icon, color: c.seedColor)),
                    const SizedBox(width: 12),
                    Expanded(child: Text(challenge.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
                    IconButton(onPressed: () => c.deleteChallenge(challenge.id), icon: const Icon(Icons.delete_outline_rounded)),
                  ]),
                  const SizedBox(height: 8),
                  Text('${_challengeMetricLabel(challenge.metric)} · ${DateFormat('dd/MM/yy').format(challenge.startDate)} → ${DateFormat('dd/MM/yy').format(challenge.endDate)}'),
                  const SizedBox(height: 10),
                  Row(children: [Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(20), child: LinearProgressIndicator(value: ratio, minHeight: 13))), const SizedBox(width: 10), Text('$progress/${challenge.target}', style: const TextStyle(fontWeight: FontWeight.w900))]),
                  const SizedBox(height: 8),
                  Row(children: [Icon(Icons.schedule_rounded, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant), const SizedBox(width: 6), Text('Transcurso ${(timeRatio * 100).round()}%')]),
                ]),
              );
            }),
        ],
      ),
    );
  }
}

String _challengeMetricLabel(ChallengeMetric metric) {
  switch (metric) {
    case ChallengeMetric.books: return 'Libros';
    case ChallengeMetric.pages: return 'Páginas';
    case ChallengeMetric.readingDays: return 'Días de lectura';
  }
}

// ---------- STATS ----------

class StatsPage extends StatelessWidget {
  const StatsPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final finished = controller.books
        .where((book) => book.status == BookStatus.finished)
        .toList();
    final pages = finished.fold<int>(0, (sum, book) => sum + book.pages);
    final rated = controller.books.where((book) => book.rating > 0).toList();
    final avg = rated.isEmpty
        ? 0.0
        : rated.fold<double>(0, (sum, book) => sum + book.rating) /
            rated.length;

    final genreCounts = <String, int>{};
    for (final book in finished) {
      for (final genre in book.genres) {
        genreCounts[genre] = (genreCounts[genre] ?? 0) + 1;
      }
    }
    final topGenres = genreCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final sessionDates = <DateTime>{};
    var sessionCount = 0;
    for (final book in controller.books) {
      for (final session in book.readingSessions) {
        final day = DateTime(session.date.year, session.date.month, session.date.day);
        sessionDates.add(day);
        sessionCount++;
      }
    }
    var streak = 0;
    var cursor = DateTime.now();
    while (sessionDates.contains(DateTime(cursor.year, cursor.month, cursor.day))) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    final now = DateTime.now();
    final finishedThisMonth = finished.where((book) => book.endDate?.year == now.year && book.endDate?.month == now.month).length;

    final formatCounts = <String, int>{};
    for (final book in finished) {
      if (book.format.isNotEmpty) {
        formatCounts[book.format] = (formatCounts[book.format] ?? 0) + 1;
      }
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        PageIntro(
          title: controller.tr('stats'),
          subtitle:
              'Una lectura cuantitativa de tus hábitos y tus preferencias.',
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: Responsive.pagePad(context, controller)),
          child: GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.35,
            children: [
              _MetricCard(
                style: controller.statsStyle,
                icon: Icons.menu_book_rounded,
                label: controller.tr('total_books'),
                value: '${controller.books.length}',
              ),
              _MetricCard(
                style: controller.statsStyle,
                icon: Icons.auto_stories_outlined,
                label: controller.tr('total_pages'),
                value: '$pages',
              ),
              _MetricCard(
                style: controller.statsStyle,
                icon: Icons.star_rounded,
                label: controller.tr('avg_rating'),
                value: avg == 0 ? '—' : avg.toStringAsFixed(2),
              ),
              _MetricCard(
                style: controller.statsStyle,
                icon: Icons.speed_rounded,
                label: controller.tr('reading_speed'),
                value: finished.isEmpty
                    ? '—'
                    : '${(pages / math.max(1, finished.length)).round()} pág/libro',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(children: [
            Expanded(child: _MetricCard(style: controller.statsStyle, icon: Icons.local_fire_department_rounded, label: 'Racha actual', value: '$streak días')),
            const SizedBox(width: 10),
            Expanded(child: _MetricCard(style: controller.statsStyle, icon: Icons.today_rounded, label: 'Terminados este mes', value: '$finishedThisMonth')),
            const SizedBox(width: 10),
            Expanded(child: _MetricCard(style: controller.statsStyle, icon: Icons.menu_book_outlined, label: 'Sesiones', value: '$sessionCount')),
          ]),
        ),
        if (controller.showStatsCalendar) ...[
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: ReadingCalendar(controller: controller),
          ),
        ],
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  controller.tr('genres_read'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                if (topGenres.isEmpty)
                  const Text(
                    'Añade géneros a tus libros para ver este gráfico.',
                  )
                else
                  ...topGenres.take(6).map(
                        (entry) => _BarRow(
                          label: entry.key,
                          value: entry.value,
                          max: topGenres.first.value,
                        ),
                      ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  controller.tr('format_mix'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                if (formatCounts.isEmpty)
                  const Text('Todavía no hay formatos registrados.')
                else
                  ...formatCounts.entries.map(
                        (entry) => _BarRow(
                          label: entry.key,
                          value: entry.value,
                          max: formatCounts.values.fold<int>(
                            0,
                            (maxValue, value) =>
                                maxValue > value ? maxValue : value,
                          ),
                        ),
                      ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ReadingDayData {
  _ReadingDayData();
  int pages = 0;
  int sessions = 0;
  List<String> bookTitles = <String>[];
}

class ReadingCalendar extends StatefulWidget {
  const ReadingCalendar({super.key, required this.controller});
  final AppController controller;
  @override
  State<ReadingCalendar> createState() => _ReadingCalendarState();
}

class _ReadingCalendarState extends State<ReadingCalendar> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);

  Map<DateTime, _ReadingDayData> get activity {
    final result = <DateTime, _ReadingDayData>{};
    void add(DateTime date, {int pages = 0, String? title}) {
      final key = DateTime(date.year, date.month, date.day);
      final item = result[key] ??= _ReadingDayData();
      item.pages += pages;
      item.sessions++;
      if (title != null && title.isNotEmpty && !item.bookTitles.contains(title)) {
        item.bookTitles.add(title);
      }
    }

    for (final book in widget.controller.books) {
      if (book.readingSessions.isNotEmpty) {
        for (final session in book.readingSessions) {
          add(session.date, pages: session.pages, title: book.title);
        }
      } else if (book.startDate != null && book.endDate != null) {
        var cursor = DateTime(book.startDate!.year, book.startDate!.month, book.startDate!.day);
        final finish = DateTime(book.endDate!.year, book.endDate!.month, book.endDate!.day);
        while (!cursor.isAfter(finish)) {
          add(cursor, title: book.title);
          cursor = cursor.add(const Duration(days: 1));
        }
      } else if (book.startDate != null) {
        add(book.startDate!, title: book.title);
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final activityMap = activity;
    final scheme = Theme.of(context).colorScheme;
    final firstWeekday = DateTime(month.year, month.month, 1).weekday - 1;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final cells = <DateTime?>[
      ...List<DateTime?>.filled(firstWeekday, null),
      ...List.generate(daysInMonth, (index) => DateTime(month.year, month.month, index + 1)),
    ];
    while (cells.length < 42) {
      cells.add(null);
    }
    final weekdayLabels = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
    return SectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('Calendario de lectura', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17))),
          IconButton(onPressed: () => setState(() => month = DateTime(month.year, month.month - 1)), icon: const Icon(Icons.chevron_left_rounded)),
          Text(DateFormat('MMMM yyyy', 'es_ES').format(month), style: const TextStyle(fontWeight: FontWeight.w800)),
          IconButton(onPressed: () => setState(() => month = DateTime(month.year, month.month + 1)), icon: const Icon(Icons.chevron_right_rounded)),
        ]),
        const SizedBox(height: 6),
        Text('Cada punto representa una sesión. Las líneas enlazan días consecutivos de lectura y el tamaño del halo refleja actividad.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 14),
        Row(children: weekdayLabels.map((label) => Expanded(child: Center(child: Text(label, style: TextStyle(fontWeight: FontWeight.w800, color: scheme.onSurfaceVariant))))) .toList()),
        const SizedBox(height: 6),
        AspectRatio(
          aspectRatio: 1.34,
          child: LayoutBuilder(builder: (context, constraints) {
            return Stack(children: [
              CustomPaint(size: Size.infinite, painter: _ReadingCalendarPainter(activityMap, month, widget.controller, scheme)),
              GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7),
                itemCount: cells.length,
                itemBuilder: (_, index) {
                  final date = cells[index];
                  if (date == null) return const SizedBox.shrink();
                  final dayData = activityMap[DateTime(date.year, date.month, date.day)];
                  final isToday = DateTime.now().year == date.year && DateTime.now().month == date.month && DateTime.now().day == date.day;
                  return InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: dayData == null ? null : () => _showReadingDay(context, date, dayData),
                    child: Center(child: Container(
                      width: 35,
                      height: 35,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: isToday ? scheme.primary : Colors.transparent, width: 2),
                        color: dayData == null ? Colors.transparent : scheme.primary.withValues(alpha: .10 + math.min(dayData.sessions, 5) * .075),
                      ),
                      child: Center(child: Text('${date.day}', style: TextStyle(fontWeight: dayData == null ? FontWeight.w500 : FontWeight.w900))),
                    )),
                  );
                },
              ),
            ]);
          }),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Icon(Icons.circle, size: 10, color: scheme.primary),
          const SizedBox(width: 6),
          const Text('Lectura registrada'),
          const SizedBox(width: 18),
          Icon(Icons.auto_awesome_rounded, size: 15, color: scheme.secondary),
          const SizedBox(width: 5),
          const Text('Día con varias sesiones'),
        ]),
      ]),
    );
  }
}

class _ReadingCalendarPainter extends CustomPainter {
  _ReadingCalendarPainter(this.activity, this.month, this.controller, this.scheme);
  final Map<DateTime, _ReadingDayData> activity;
  final DateTime month;
  final AppController controller;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / 7;
    final cellH = size.height / 6;
    final linePaint = Paint()
      ..color = scheme.primary.withValues(alpha: controller.calendarStyle == 'minimal' ? .22 : .48)
      ..strokeWidth = controller.calendarStyle == 'bold' ? 4.2 : controller.calendarStyle == 'minimal' ? 1.4 : 2.8
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final dotPaint = Paint()..color = scheme.primary;
    final active = activity.keys.where((day) => day.year == month.year && day.month == month.month).toList()..sort();
    for (var i = 0; i < active.length - 1; i++) {
      final a = active[i];
      final b = active[i + 1];
      if (b.difference(a).inDays != 1) continue;
      final aIndex = (DateTime(a.year, a.month, 1).weekday - 1) + a.day - 1;
      final bIndex = (DateTime(b.year, b.month, 1).weekday - 1) + b.day - 1;
      final p1 = Offset((aIndex % 7 + .5) * cellW, (aIndex ~/ 7 + .5) * cellH);
      final p2 = Offset((bIndex % 7 + .5) * cellW, (bIndex ~/ 7 + .5) * cellH);
      canvas.drawLine(p1, p2, linePaint);
    }
    for (final day in active) {
      final index = (DateTime(day.year, day.month, 1).weekday - 1) + day.day - 1;
      final center = Offset((index % 7 + .5) * cellW, (index ~/ 7 + .5) * cellH);
      final count = activity[day]?.sessions ?? 0;
      canvas.drawCircle(center.translate(cellW * .20, cellH * .22), 2.5 + math.min(count, 4), dotPaint);
      if (controller.doodles && count >= 2) {
        final doodlePaint = Paint()..color = scheme.secondary.withValues(alpha: .68)..style = PaintingStyle.stroke..strokeWidth = 1.4;
        if (controller.calendarStyle == 'botanical') {
          canvas.drawArc(Rect.fromCenter(center: center.translate(-cellW * .22, -cellH * .20), width: 11, height: 8), -.8, 2.2, false, doodlePaint);
          canvas.drawLine(center.translate(-cellW * .24, -cellH * .18), center.translate(-cellW * .16, -cellH * .29), doodlePaint);
        } else {
          canvas.drawCircle(center.translate(-cellW * .23, -cellH * .20), 5, doodlePaint);
          canvas.drawLine(center.translate(-cellW * .23, -cellH * .25), center.translate(-cellW * .18, -cellH * .30), doodlePaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ReadingCalendarPainter oldDelegate) => true;
}

Future<void> _showReadingDay(BuildContext context, DateTime date, _ReadingDayData data) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(DateFormat('EEEE d MMMM yyyy', 'es_ES').format(date), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        Text('${data.sessions} sesión${data.sessions == 1 ? '' : 'es'} · ${data.pages} páginas'),
        const SizedBox(height: 10),
        ...data.bookTitles.map((title) => ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.menu_book_rounded), title: Text(title))),
      ]),
    ),
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.icon, required this.label, required this.value, this.style = 'cards'});
  final IconData icon;
  final String label;
  final String value;
  final String style;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isMinimal = style == 'minimal';
    final isEditorial = style == 'editorial';
    return Card(
      elevation: isMinimal ? 0 : null,
      color: isEditorial ? scheme.surface : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Container(width: 34, height: 34, decoration: BoxDecoration(color: scheme.primary.withValues(alpha: isMinimal ? .08 : .14), shape: BoxShape.circle), child: Icon(icon, size: 18)), const Spacer(), if (isEditorial) Icon(Icons.more_horiz_rounded, color: scheme.onSurfaceVariant)]),
          const Spacer(),
          Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900, letterSpacing: isEditorial ? -1.0 : 0)),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    );
  }
}

class _BarRow extends StatelessWidget {
  const _BarRow({required this.label, required this.value, required this.max});

  final String label;
  final int value;
  final int max;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(label, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: max == 0 ? 0 : value / max,
                minHeight: 11,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text('$value'),
        ],
      ),
    );
  }
}

// ---------- WRAPPED ----------

class WrappedPage extends StatefulWidget {
  const WrappedPage({super.key, required this.controller});
  final AppController controller;
  @override
  State<WrappedPage> createState() => _WrappedPageState();
}

class _WrappedPageState extends State<WrappedPage> {
  final globalKey = GlobalKey();
  final titleController = TextEditingController(text: 'MY READING YEAR');
  int year = DateTime.now().year;
  late String template;
  late String pattern;
  late String ratio;
  late String alignment;
  int coverCount = 5;
  double stickerDensity = .55;
  bool showPages = true;
  bool showRating = true;
  bool showTopGenre = true;
  bool showMood = true;
  bool showTopBooks = true;
  bool showFooter = true;

  @override
  void initState() {
    super.initState();
    final c = widget.controller;
    template = c.wrappedTemplate;
    pattern = c.wrappedPattern;
    ratio = c.wrappedRatio;
    alignment = 'left';
  }

  @override
  void dispose() {
    titleController.dispose();
    super.dispose();
  }

  List<Book> get yearBooks => widget.controller.books.where((book) => (book.endDate ?? book.startDate)?.year == year && book.status == BookStatus.finished).toList();

  Map<String, int> _genres(List<Book> books) {
    final map = <String, int>{};
    for (final book in books) {
      for (final genre in book.genres) {
        map[genre] = (map[genre] ?? 0) + 1;
      }
    }
    return map;
  }

  String _topMood(List<Book> books) {
    final totals = <String, double>{};
    for (final book in books) {
      book.emotions.forEach((key, value) => totals[key] = (totals[key] ?? 0) + value);
    }
    if (totals.isEmpty) return '—';
    return (totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
  }

  Future<void> _saveWrappedPrefs() => widget.controller.updateSettings(newWrappedTemplate: template, newWrappedPattern: pattern, newWrappedRatio: ratio);

  Future<void> exportCard() async {
    final renderObject = globalKey.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) return;
    final image = await renderObject.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/wrapped_$year.png';
    await File(path).writeAsBytes(bytes.buffer.asUint8List());
    await SharePlus.instance.share(ShareParams(files: [XFile(path)], text: 'Mi Wrapped lector $year'));
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final theme = Theme.of(context);
    final books = yearBooks;
    final pages = books.fold<int>(0, (sum, book) => sum + book.pages);
    final rated = books.where((book) => book.rating > 0).toList();
    final avg = rated.isEmpty ? 0.0 : rated.fold<double>(0, (sum, book) => sum + book.rating) / rated.length;
    final genreMap = _genres(books);
    final topGenre = genreMap.isEmpty ? '—' : (genreMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
    final mood = _topMood(books);
    final safeMax = math.max(1, math.min(8, books.length));
    final safeDivisions = books.length <= 1 ? 1 : math.min(7, books.length - 1);

    return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
      PageIntro(title: 'Wrapped $year', subtitle: 'Crea una pieza que se parezca a ti: formato, composición, decoración, datos, portadas y tipografía visual.'),
      Padding(padding: EdgeInsets.symmetric(horizontal: Responsive.pagePad(context, controller)), child: SectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [IconButton(onPressed: () => setState(() => year--), icon: const Icon(Icons.chevron_left_rounded)), Expanded(child: Center(child: Text('$year', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)))), IconButton(onPressed: () => setState(() => year++), icon: const Icon(Icons.chevron_right_rounded))]),
        TextField(controller: titleController, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Título de portada', prefixIcon: Icon(Icons.title_rounded))),
        const SizedBox(height: 14),
        const Text('Plantilla', style: TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final entry in const {'scrapbook':'Scrapbook', 'editorial':'Editorial', 'dreamy':'Dreamy', 'minimal':'Minimal', 'poster':'Poster'}.entries)
            _ChoicePill(label: entry.value, selected: template == entry.key, onTap: () { setState(() => template = entry.key); unawaited(_saveWrappedPrefs()); }),
        ]),
        const SizedBox(height: 14),
        _adaptivePair(
          context,
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: ratio,
            decoration: const InputDecoration(labelText: 'Formato'),
            items: const [DropdownMenuItem(value: 'story', child: Text('Historia 9:16')), DropdownMenuItem(value: 'portrait', child: Text('Vertical 4:5')), DropdownMenuItem(value: 'square', child: Text('Cuadrado 1:1'))],
            onChanged: (v) { setState(() => ratio = v ?? ratio); unawaited(_saveWrappedPrefs()); },
          ),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: alignment,
            decoration: const InputDecoration(labelText: 'Texto'),
            items: const [DropdownMenuItem(value: 'left', child: Text('Izquierda')), DropdownMenuItem(value: 'center', child: Text('Centrado')), DropdownMenuItem(value: 'right', child: Text('Derecha'))],
            onChanged: (v) => setState(() => alignment = v ?? alignment),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(initialValue: pattern, decoration: const InputDecoration(labelText: 'Textura y decoración'), items: const [DropdownMenuItem(value: 'doodles', child: Text('Doodles')), DropdownMenuItem(value: 'stars', child: Text('Estrellas')), DropdownMenuItem(value: 'botanical', child: Text('Botánico')), DropdownMenuItem(value: 'paper', child: Text('Papel suave')), DropdownMenuItem(value: 'clean', child: Text('Limpio'))], onChanged: (v) { setState(() => pattern = v ?? pattern); unawaited(_saveWrappedPrefs()); }),
        const SizedBox(height: 10),
        Text('Intensidad de stickers: ${(stickerDensity * 100).round()}%'),
        Slider(value: stickerDensity, min: 0, max: 1, divisions: 10, onChanged: (v) => setState(() => stickerDensity = v)),
        Text('Portadas visibles: $coverCount'),
        Slider(value: math.min(coverCount, safeMax).toDouble(), min: 1, max: safeMax.toDouble(), divisions: safeDivisions, onChanged: books.isEmpty ? null : (v) => setState(() => coverCount = v.round())),
        const Divider(height: 24),
        const Text('Elementos de la historia', style: TextStyle(fontWeight: FontWeight.w900)),
        SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, title: const Text('Páginas'), value: showPages, onChanged: (v) => setState(() => showPages = v)),
        SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, title: const Text('Media de estrellas'), value: showRating, onChanged: (v) => setState(() => showRating = v)),
        SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, title: const Text('Género del año'), value: showTopGenre, onChanged: (v) => setState(() => showTopGenre = v)),
        SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, title: const Text('Mood dominante'), value: showMood, onChanged: (v) => setState(() => showMood = v)),
        SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, title: const Text('Portadas destacadas'), value: showTopBooks, onChanged: (v) => setState(() => showTopBooks = v)),
        SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, title: const Text('Pie de autoría'), value: showFooter, onChanged: (v) => setState(() => showFooter = v)),
      ]))),
      const SizedBox(height: 14),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: Center(child: FittedBox(child: RepaintBoundary(key: globalKey, child: _WrappedArtwork(controller: controller, template: template, pattern: pattern, title: titleController.text, year: year, books: books, pages: pages, avg: avg, topGenre: topGenre, mood: mood, showPages: showPages, showRating: showRating, showTopGenre: showTopGenre, showMood: showMood, showTopBooks: showTopBooks, showFooter: showFooter, coverCount: coverCount, stickerDensity: stickerDensity, ratio: ratio, alignment: alignment))))),
      const SizedBox(height: 14),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: FilledButton.icon(onPressed: books.isEmpty ? null : exportCard, icon: const Icon(Icons.ios_share_rounded), label: Text(controller.tr('export_share')))),
      if (books.isEmpty) Padding(padding: const EdgeInsets.fromLTRB(18, 12, 18, 0), child: Text('Añade libros finalizados con fechas para llenar tu Wrapped.', textAlign: TextAlign.center, style: theme.textTheme.bodySmall)),
    ]);
  }
}

class _ChoicePill extends StatelessWidget {
  const _ChoicePill({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap());
}

class _WrappedArtwork extends StatelessWidget {
  const _WrappedArtwork({required this.controller, required this.template, required this.pattern, required this.title, required this.year, required this.books, required this.pages, required this.avg, required this.topGenre, required this.mood, required this.showPages, required this.showRating, required this.showTopGenre, required this.showMood, required this.showTopBooks, required this.showFooter, required this.coverCount, required this.stickerDensity, required this.ratio, required this.alignment});
  final AppController controller;
  final String template;
  final String pattern;
  final String title;
  final int year;
  final List<Book> books;
  final int pages;
  final double avg;
  final String topGenre;
  final String mood;
  final bool showPages;
  final bool showRating;
  final bool showTopGenre;
  final bool showMood;
  final bool showTopBooks;
  final bool showFooter;
  final int coverCount;
  final double stickerDensity;
  final String ratio;
  final String alignment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = template == 'minimal' ? theme.colorScheme.surface : template == 'editorial' ? const Color(0xFF161416) : template == 'poster' ? LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [controller.seedColor, controller.moodAccent, const Color(0xFFF2C9AA)]) : template == 'dreamy' ? LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color.lerp(controller.seedColor, const Color(0xFFE6D7F2), .62)!, const Color(0xFFDFF1F3)]) : LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [controller.seedColor, controller.moodAccent]);
    final foreground = template == 'editorial' || template == 'poster' ? Colors.white : (template == 'minimal' ? theme.colorScheme.onSurface : Colors.white);
    final accent = template == 'minimal' ? controller.seedColor : Colors.white;
    final count = math.min(coverCount, books.length);
    final width = ratio == 'square' ? 410.0 : 360.0;
    final height = ratio == 'square' ? 410.0 : ratio == 'portrait' ? 540.0 : 640.0;
    final cross = alignment == 'center' ? CrossAxisAlignment.center : alignment == 'right' ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final textAlign = alignment == 'center' ? TextAlign.center : alignment == 'right' ? TextAlign.right : TextAlign.left;

    return Container(width: width, height: height, decoration: BoxDecoration(color: background is Color ? background : null, gradient: background is LinearGradient ? background : null, borderRadius: BorderRadius.circular(controller.cornerRadius + 8), border: Border.all(color: foreground.withValues(alpha: .14))), clipBehavior: Clip.antiAlias, child: Stack(children: [
      Positioned.fill(child: CustomPaint(painter: _DoodlePainter(pattern: pattern, color: foreground.withValues(alpha: .22), density: stickerDensity))),
      Padding(padding: const EdgeInsets.fromLTRB(26, 30, 26, 28), child: Column(crossAxisAlignment: cross, children: [
        Row(children: [Icon(Icons.auto_awesome_rounded, color: accent, size: 20), const Spacer(), Text('$year', style: TextStyle(color: foreground.withValues(alpha: .75), fontWeight: FontWeight.w800))]),
        const Spacer(),
        Text(title.isEmpty ? 'MY READING YEAR' : title.toUpperCase(), textAlign: textAlign, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: foreground, fontSize: 34 * controller.titleScale, height: .96, fontWeight: FontWeight.w900, letterSpacing: -1.4)),
        const SizedBox(height: 18),
        Row(children: [Expanded(child: _WrapStat(value: '${books.length}', label: 'libros', color: foreground)), if (showPages) Expanded(child: _WrapStat(value: '$pages', label: 'páginas', color: foreground)), if (showRating) Expanded(child: _WrapStat(value: avg == 0 ? '—' : avg.toStringAsFixed(2), label: 'media', color: foreground))]),
        if (showTopGenre) ...[const SizedBox(height: 14), Text('GÉNERO DEL AÑO', textAlign: textAlign, style: TextStyle(color: foreground.withValues(alpha: .68), letterSpacing: 1.8, fontWeight: FontWeight.w700, fontSize: 10)), const SizedBox(height: 3), Text(topGenre, textAlign: textAlign, style: TextStyle(color: accent, fontSize: 19, fontWeight: FontWeight.w900))],
        if (showMood) ...[const SizedBox(height: 10), Text('MOOD', textAlign: textAlign, style: TextStyle(color: foreground.withValues(alpha: .68), letterSpacing: 1.8, fontWeight: FontWeight.w700, fontSize: 10)), Text(mood, textAlign: textAlign, style: TextStyle(color: foreground, fontSize: 16, fontWeight: FontWeight.w800))],
        if (showTopBooks) ...[const SizedBox(height: 16), if (count > 0) Wrap(alignment: alignment == 'center' ? WrapAlignment.center : alignment == 'right' ? WrapAlignment.end : WrapAlignment.start, spacing: 7, runSpacing: 7, children: books.take(count).map((book) => BookCover(book: book, width: ratio == 'square' ? 48 : 52, height: ratio == 'square' ? 70 : 78)).toList())],
        const Spacer(),
        if (showFooter) Text('reading journal · ${controller.style}', style: TextStyle(color: foreground.withValues(alpha: .62), fontWeight: FontWeight.w700, fontSize: 10)),
      ])),
    ]));
  }
}

class _DoodlePainter extends CustomPainter {
  _DoodlePainter({required this.pattern, required this.color, this.density = .6});
  final String pattern;
  final Color color;
  final double density;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 1.5;
    if (pattern == 'clean') return;
    final count = (5 + density * 18).round();
    for (var i = 0; i < count; i++) {
      final x = (i * 73.0 + 35) % size.width;
      final y = (i * 117.0 + 20) % size.height;
      if (pattern == 'botanical') {
        canvas.drawArc(Rect.fromCenter(center: Offset(x, y), width: 20, height: 12), -1.2, 2.3, false, paint);
        canvas.drawLine(Offset(x - 3, y + 8), Offset(x + 8, y - 10), paint);
      } else if (pattern == 'stars') {
        _star(canvas, Offset(x, y), 7, paint);
      } else if (pattern == 'paper') {
        canvas.drawLine(Offset(x - 13, y), Offset(x + 13, y), paint);
      } else {
        canvas.drawCircle(Offset(x, y), 4 + (i % 3) * 2.0, paint);
        canvas.drawLine(Offset(x - 5, y), Offset(x + 5, y), paint);
        canvas.drawLine(Offset(x, y - 5), Offset(x, y + 5), paint);
      }
    }
  }
  void _star(Canvas canvas, Offset c, double r, Paint p) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final a = -math.pi / 2 + i * math.pi / 5;
      final rr = i.isEven ? r : r * .42;
      final point = Offset(c.dx + math.cos(a) * rr, c.dy + math.sin(a) * rr);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, p);
  }
  @override
  bool shouldRepaint(covariant _DoodlePainter oldDelegate) => oldDelegate.pattern != pattern || oldDelegate.color != color || oldDelegate.density != density;
}

class _WrapStat extends StatelessWidget {
  const _WrapStat({required this.value, required this.label, this.color = Colors.white});
  final String value;
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(value, style: TextStyle(color: color, fontSize: 26, fontWeight: FontWeight.w900)), Text(label, style: TextStyle(color: color.withValues(alpha: .72)))]);
}

class BookishPage extends StatefulWidget {
  const BookishPage({super.key, required this.controller});
  final AppController controller;
  @override
  State<BookishPage> createState() => _BookishPageState();
}

class _BookishPageState extends State<BookishPage> {
  final globalKey = GlobalKey();
  final titleController = TextEditingController(text: 'MY BOOKISH SHELF');
  late String scene;
  late String shelf;
  late String decor;
  late String display;
  late String ratio;
  late String alignment;
  int bookCount = 8;
  double bookScale = 1;
  double stickerDensity = .55;
  bool showTitle = true;
  bool showSubtitle = true;

  @override
  void initState() {
    super.initState();
    final c = widget.controller;
    scene = c.bookishScene;
    shelf = c.bookishShelf;
    decor = c.bookishDecor;
    display = c.bookishDisplay;
    ratio = c.bookishRatio;
    alignment = 'center';
    final allowed = math.max(1, math.min(8, c.books.length));
    bookCount = math.min(bookCount, allowed);
  }

  @override
  void dispose() {
    titleController.dispose();
    super.dispose();
  }

  Future<void> _saveBookishPrefs() => widget.controller.updateSettings(newBookishScene: scene, newBookishShelf: shelf, newBookishDecor: decor, newBookishDisplay: display, newBookishRatio: ratio);

  Future<void> exportCard() async {
    final renderObject = globalKey.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) return;
    final image = await renderObject.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/bookish_shelf.png';
    await File(path).writeAsBytes(bytes.buffer.asUint8List());
    await SharePlus.instance.share(ShareParams(files: [XFile(path)], text: 'Mi estantería Bookish'));
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final books = controller.books.take(math.min(bookCount, controller.books.length)).toList();
    final safeMax = math.max(1, math.min(8, controller.books.length));
    final safeDivisions = controller.books.length <= 1 ? 1 : math.min(7, controller.books.length - 1);
    return ListView(padding: const EdgeInsets.only(bottom: 34), children: [
      PageIntro(title: 'Bookish', subtitle: 'Construye una escena a tu gusto: estantería, portadas o lomos, objetos, formato, tipografía y cantidad de decoración.'),
      Padding(padding: EdgeInsets.symmetric(horizontal: Responsive.pagePad(context, controller)), child: SectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(controller: titleController, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Título de la estantería', prefixIcon: Icon(Icons.text_fields_rounded))),
        const SizedBox(height: 12),
        _adaptivePair(
          context,
          DropdownButtonFormField<String>(isExpanded: true, initialValue: scene, decoration: const InputDecoration(labelText: 'Escena'), items: const [DropdownMenuItem(value: 'cozy', child: Text('Cozy café')), DropdownMenuItem(value: 'cottage', child: Text('Cottage garden')), DropdownMenuItem(value: 'gothic', child: Text('Gothic library')), DropdownMenuItem(value: 'pastel', child: Text('Pastel dream')), DropdownMenuItem(value: 'minimal', child: Text('Minimal'))], onChanged: (v) { setState(() => scene = v ?? scene); unawaited(_saveBookishPrefs()); }),
          DropdownButtonFormField<String>(isExpanded: true, initialValue: shelf, decoration: const InputDecoration(labelText: 'Estante'), items: const [DropdownMenuItem(value: 'wood', child: Text('Madera cálida')), DropdownMenuItem(value: 'marble', child: Text('Mármol')), DropdownMenuItem(value: 'floating', child: Text('Flotante')), DropdownMenuItem(value: 'rainbow', child: Text('Arcoíris'))], onChanged: (v) { setState(() => shelf = v ?? shelf); unawaited(_saveBookishPrefs()); }),
        ),
        const SizedBox(height: 12),
        _adaptivePair(
          context,
          DropdownButtonFormField<String>(isExpanded: true, initialValue: decor, decoration: const InputDecoration(labelText: 'Decoración'), items: const [DropdownMenuItem(value: 'plants', child: Text('Plantas + café')), DropdownMenuItem(value: 'flowers', child: Text('Flores + lazos')), DropdownMenuItem(value: 'moon', child: Text('Luna + estrellas')), DropdownMenuItem(value: 'minimal', child: Text('Minimal'))], onChanged: (v) { setState(() => decor = v ?? decor); unawaited(_saveBookishPrefs()); }),
          DropdownButtonFormField<String>(isExpanded: true, initialValue: display, decoration: const InputDecoration(labelText: 'Libros'), items: const [DropdownMenuItem(value: 'covers', child: Text('Portadas')), DropdownMenuItem(value: 'spines', child: Text('Lomos')), DropdownMenuItem(value: 'mix', child: Text('Mezcla'))], onChanged: (v) { setState(() => display = v ?? display); unawaited(_saveBookishPrefs()); }),
        ),
        const SizedBox(height: 12),
        _adaptivePair(
          context,
          DropdownButtonFormField<String>(isExpanded: true, initialValue: ratio, decoration: const InputDecoration(labelText: 'Formato'), items: const [DropdownMenuItem(value: 'portrait', child: Text('Vertical 4:5')), DropdownMenuItem(value: 'story', child: Text('Historia 9:16')), DropdownMenuItem(value: 'square', child: Text('Cuadrado'))], onChanged: (v) { setState(() => ratio = v ?? ratio); unawaited(_saveBookishPrefs()); }),
          DropdownButtonFormField<String>(isExpanded: true, initialValue: alignment, decoration: const InputDecoration(labelText: 'Alineación'), items: const [DropdownMenuItem(value: 'left', child: Text('Izquierda')), DropdownMenuItem(value: 'center', child: Text('Centrado')), DropdownMenuItem(value: 'right', child: Text('Derecha'))], onChanged: (v) => setState(() => alignment = v ?? alignment)),
        ),
        const SizedBox(height: 10),
        Text('Libros visibles: $bookCount'),
        Slider(value: bookCount.toDouble().clamp(1, safeMax).toDouble(), min: 1, max: safeMax.toDouble(), divisions: safeDivisions, onChanged: controller.books.isEmpty ? null : (v) => setState(() => bookCount = v.round())),
        Text('Escala de libros: ${(bookScale * 100).round()}%'),
        Slider(value: bookScale, min: .72, max: 1.28, divisions: 14, onChanged: (v) => setState(() => bookScale = v)),
        Text('Decoración: ${(stickerDensity * 100).round()}%'),
        Slider(value: stickerDensity, min: 0, max: 1, divisions: 10, onChanged: (v) => setState(() => stickerDensity = v)),
        SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, title: const Text('Mostrar título'), value: showTitle, onChanged: (v) => setState(() => showTitle = v)),
        SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, title: const Text('Mostrar subtítulo'), value: showSubtitle, onChanged: (v) => setState(() => showSubtitle = v)),
      ]))),
      const SizedBox(height: 14),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: Center(child: FittedBox(child: RepaintBoundary(key: globalKey, child: _BookishArtwork(controller: controller, scene: scene, shelf: shelf, decor: decor, display: display, books: books, scale: bookScale, title: titleController.text, showTitle: showTitle, showSubtitle: showSubtitle, ratio: ratio, alignment: alignment, density: stickerDensity))))),
      const SizedBox(height: 14),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: FilledButton.icon(onPressed: books.isEmpty ? null : exportCard, icon: const Icon(Icons.ios_share_rounded), label: Text(controller.tr('export_share'))),),
    ]);
  }
}

class _BookishArtwork extends StatelessWidget {
  const _BookishArtwork({required this.controller, required this.scene, required this.shelf, required this.decor, required this.display, required this.books, required this.scale, required this.title, required this.showTitle, required this.showSubtitle, required this.ratio, required this.alignment, required this.density});
  final AppController controller;
  final String scene;
  final String shelf;
  final String decor;
  final String display;
  final List<Book> books;
  final double scale;
  final String title;
  final bool showTitle;
  final bool showSubtitle;
  final String ratio;
  final String alignment;
  final double density;

  LinearGradient _gradient() {
    switch (scene) {
      case 'cottage': return const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFE4EFD7), Color(0xFFF7E9D7)]);
      case 'gothic': return const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1B1720), Color(0xFF413344)]);
      case 'pastel': return const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF2DFF0), Color(0xFFDDEBFA)]);
      case 'minimal': return const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF3F0EA), Color(0xFFE2DDD4)]);
      default: return LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [controller.seedColor.withValues(alpha: .90), Color.lerp(controller.seedColor, const Color(0xFFF1D9C2), .65)!]);
    }
  }

  Widget _spine(Book book, BuildContext context) => Container(width: 34, height: 168, padding: const EdgeInsets.all(5), decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [controller.seedColor.withValues(alpha: .95), controller.moodAccent.withValues(alpha: .85)]), borderRadius: BorderRadius.circular(5)), child: RotatedBox(quarterTurns: 1, child: Center(child: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 9)))));

  @override
  Widget build(BuildContext context) {
    final foreground = scene == 'gothic' ? Colors.white : const Color(0xFF342C2B);
    final shelfColor = switch (shelf) {'marble' => const Color(0xFFD7D2D0), 'floating' => const Color(0xFFB99068), 'rainbow' => controller.moodAccent, _ => const Color(0xFF8D5C3D)};
    final iconItems = decor == 'minimal' ? const <IconData>[] : decor == 'moon' ? const [Icons.nights_stay_rounded, Icons.auto_awesome_rounded, Icons.local_fire_department_rounded] : decor == 'flowers' ? const [Icons.local_florist_rounded, Icons.favorite_rounded, Icons.auto_awesome_rounded] : const [Icons.local_cafe_rounded, Icons.local_florist_rounded, Icons.light_rounded];
    final width = ratio == 'square' ? 410.0 : 360.0;
    final height = ratio == 'square' ? 410.0 : ratio == 'story' ? 640.0 : 540.0;
    final cross = alignment == 'center' ? CrossAxisAlignment.center : alignment == 'right' ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    return Container(width: width, height: height, clipBehavior: Clip.antiAlias, decoration: BoxDecoration(gradient: _gradient(), borderRadius: BorderRadius.circular(controller.cornerRadius + 8)), child: Stack(children: [
      Positioned.fill(child: CustomPaint(painter: _BookishDoodlePainter(color: foreground.withValues(alpha: .13), gothic: scene == 'gothic', density: density))),
      Positioned(top: 24, left: 24, right: 24, child: Column(crossAxisAlignment: cross, children: [
        if (showTitle) Text(title.isEmpty ? 'MY BOOKISH SHELF' : title.toUpperCase(), maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: alignment == 'center' ? TextAlign.center : alignment == 'right' ? TextAlign.right : TextAlign.left, style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900, letterSpacing: -.8, color: foreground)),
        if (showSubtitle) Text('${books.length} libros · ${display == 'covers' ? 'portadas' : display == 'spines' ? 'lomos' : 'mix'}', style: TextStyle(color: foreground.withValues(alpha: .68), fontWeight: FontWeight.w800)),
      ])),
      ...List.generate(iconItems.length, (i) => Positioned(top: 90.0 + i * 24, right: 26 + (i.isEven ? 18.0 : 0), child: Icon(iconItems[i], size: 22 + i * 2.0, color: foreground.withValues(alpha: .62)))),
      Positioned(left: 22, right: 22, bottom: 88, child: Transform.scale(scale: scale, alignment: Alignment.bottomCenter, child: Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.center, children: books.asMap().entries.map((entry) { final i = entry.key; final book = entry.value; final useSpine = display == 'spines' || (display == 'mix' && i.isOdd); return Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: Transform.rotate(angle: ((book.title.hashCode % 9) - 4) * .009, child: useSpine ? _spine(book, context) : BookCover(book: book, width: 38, height: 156))); }).toList()))),
      Positioned(left: 16, right: 16, bottom: 63, child: Container(height: 19, decoration: BoxDecoration(color: shelfColor, borderRadius: BorderRadius.circular(8), boxShadow: controller.decorations ? [BoxShadow(color: Colors.black.withValues(alpha: .12), blurRadius: 7, offset: const Offset(0, 4))] : const []))),
      Positioned(left: 16, right: 16, bottom: 36, child: Container(height: 13, decoration: BoxDecoration(color: shelfColor.withValues(alpha: .75), borderRadius: BorderRadius.circular(8)))),
      const Positioned(left: 26, bottom: 12, child: Text('BOOKISH · READING JOURNAL', style: TextStyle(letterSpacing: 2.1, fontSize: 9, fontWeight: FontWeight.w800, color: Colors.black54))),
    ]));
  }
}

class _BookishDoodlePainter extends CustomPainter {
  _BookishDoodlePainter({required this.color, required this.gothic, this.density = .6});
  final Color color;
  final bool gothic;
  final double density;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 1.4;
    final count = (5 + density * 20).round();
    for (var i = 0; i < count; i++) {
      final x = 18 + (i * 61.0) % math.max(25, size.width - 36);
      final y = 12 + (i * 43.0) % math.max(30, size.height - 30);
      if (gothic) {
        canvas.drawCircle(Offset(x, y), 7 + i % 3, paint);
        canvas.drawLine(Offset(x - 9, y), Offset(x + 9, y), paint);
      } else {
        canvas.drawArc(Rect.fromCenter(center: Offset(x, y), width: 15, height: 10), 0, math.pi * 1.25, false, paint);
      }
    }
  }
  @override
  bool shouldRepaint(covariant _BookishDoodlePainter oldDelegate) => oldDelegate.color != color || oldDelegate.gothic != gothic || oldDelegate.density != density;
}

// ---------- CUSTOMIZATION ----------

Future<void> _exportBackup(BuildContext context, AppController controller) async {
  final settings = controller._prefs.getString(AppController._settingsKey);
  final payload = {
    'version': 1,
    'exportedAt': DateTime.now().toIso8601String(),
    'books': controller.books.map((book) => book.toJson()).toList(),
    'challenges': controller.challenges.map((challenge) => challenge.toJson()).toList(),
    'settings': settings == null ? <String, dynamic>{} : jsonDecode(settings),
  };
  final dir = await getApplicationDocumentsDirectory();
  final path = '${dir.path}/reading_journal_backup_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.json';
  await File(path).writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
  if (context.mounted) {
    await SharePlus.instance.share(ShareParams(files: [XFile(path)], text: 'Copia de seguridad de READBLOOM'));
  }
}

Future<void> _importBackup(BuildContext context, AppController controller) async {
  final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
  if (files.isEmpty || files.first.path == null) return;
  try {
    final payload = jsonDecode(await File(files.first.path!).readAsString()) as Map;
    final books = (payload['books'] as List? ?? const []).whereType<Map>().map((e) => Book.fromJson(Map<String, dynamic>.from(e))).toList();
    final challenges = (payload['challenges'] as List? ?? const []).whereType<Map>().map((e) => ReadingChallenge.fromJson(Map<String, dynamic>.from(e))).toList();
    controller.books..clear()..addAll(books);
    controller.challenges..clear()..addAll(challenges);
    final settings = payload['settings'];
    if (settings is Map) {
      await controller._prefs.setString(AppController._settingsKey, jsonEncode(settings));
    }
    await controller.save();
    await controller.load();
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copia restaurada: ${books.length} libros y ${challenges.length} retos.')));
  } catch (_) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo restaurar la copia. Comprueba que sea un archivo de READBLOOM.')));
  }
}

class CustomizationPage extends StatelessWidget {
  const CustomizationPage({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final palettes = <String, Color>{
      'terracotta': const Color(0xFFB76E5E), 'lavender': const Color(0xFF8B78A7), 'sage': const Color(0xFF6D8773), 'rose': const Color(0xFFC77887),
      'midnight': const Color(0xFF5D6B9A), 'butter': const Color(0xFFC59B45), 'ocean': const Color(0xFF4F8190), 'berry': const Color(0xFF9A5C78),
      'plum': const Color(0xFF74506C), 'peach': const Color(0xFFD79273), 'forest': const Color(0xFF517663), 'sky': const Color(0xFF648CAA), 'sand': const Color(0xFFB18A63), 'coral': const Color(0xFFC46F62), 'iris': const Color(0xFF756EA8), 'moss': const Color(0xFF71815B), 'inkblue': const Color(0xFF425774), 'apricot': const Color(0xFFCC896D),
    };
    final styles = const {'cozy':'Cozy', 'romance':'Romántico', 'fantasy':'Fantasía', 'gothic':'Gótico', 'dark_academia':'Dark academia', 'cottagecore':'Cottagecore', 'whimsigoth':'Whimsigoth', 'minimal':'Minimal editorial', 'celestial':'Celestial', 'botanical':'Botánico', 'ocean':'Ocean', 'retro':'Retro library', 'noir':'Noir', 'sunset':'Sunset', 'sakura':'Sakura', 'parchment':'Papel antiguo'};
    final moods = const {'warm':'Cálido', 'calm':'Calmado', 'dreamy':'Soñador', 'moody':'Melancólico', 'bright':'Luminoso', 'airy':'Ligero', 'mystic':'Místico'};
    final backgrounds = const {'paper':'Papel crema', 'mist':'Niebla', 'warm':'Arena cálida', 'lavender':'Lavanda', 'sage':'Salvia', 'rose':'Rosa suave', 'blue':'Azul niebla', 'parchment':'Pergamino'};
    final cards = const {'soft':'Suave', 'cream':'Crema', 'glass':'Cristal', 'ink':'Editorial'};
    final densities = const {'compact':'Compacta', 'comfortable':'Cómoda', 'airy':'Aireada', 'roomy':'Muy espaciosa'};
    final languages = const {'es-ES':'Español (España)', 'eu':'Euskera', 'es-LATAM':'Español (Latinoamérica)', 'en-US':'English (US)', 'en-GB':'English (UK)', 'fr':'Français'};
    final fonts = const {'system':'Moderna', 'serif':'Editorial / Serif', 'rounded':'Redondeada', 'mono':'Máquina de escribir', 'condensed':'Sans condensada', 'light':'Sans ligera', 'medium':'Sans media', 'black':'Sans fuerte', 'slab':'Serif robusta'};
    final views = const {'grid':'Cuadrícula', 'compact':'Compacta', 'list':'Lista', 'shelf':'Estantería'};
    final statsStyles = const {'cards':'Tarjetas', 'editorial':'Editorial', 'minimal':'Minimal'};
    final calendarStyles = const {'trail':'Líneas suaves', 'bold':'Líneas marcadas', 'botanical':'Botánico', 'minimal':'Minimal'};
    final navStyles = const {'bar':'Barra clásica', 'pill':'Píldoras', 'compact':'Compacta', 'airy':'Aireada'};
    final coverShapes = const {'rounded':'Redondeada', 'soft':'Muy redondeada', 'square':'Casi cuadrada', 'ticket':'Esquinas suaves'};

    Widget select<T>({required String label, required String value, required Map<String, String> options, required ValueChanged<String?> onChanged}) => DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: options.containsKey(value) ? value : options.keys.first,
      decoration: InputDecoration(labelText: label, isDense: false),
      menuMaxHeight: 420,
      items: options.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, maxLines: 1, overflow: TextOverflow.ellipsis))).toList(),
      onChanged: onChanged,
    );

    Widget fieldGrid(List<Widget> fields) => LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < 640 || fields.length == 1) {
        return Column(children: [for (var i = 0; i < fields.length; i++) ...[if (i > 0) const SizedBox(height: 12), fields[i]]]);
      }
      final width = (constraints.maxWidth - 12) / 2;
      return Wrap(spacing: 12, runSpacing: 12, children: fields.map((field) => SizedBox(width: width, child: field)).toList());
    });

    Widget settingSwitch(String title, String subtitle, bool value, ValueChanged<bool> onChanged) => Container(
      constraints: const BoxConstraints(minHeight: 66),
      padding: const EdgeInsets.fromLTRB(13, 10, 8, 10),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerLow.withValues(alpha: .72), borderRadius: BorderRadius.circular(16), border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .34))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.25)),
        ])),
        const SizedBox(width: 8),
        Switch.adaptive(value: value, onChanged: onChanged),
      ]),
    );

    Widget settingGrid(List<Widget> fields) => fieldGrid(fields);

    return ListView(padding: const EdgeInsets.only(bottom: 34), children: [
      PageIntro(title: controller.tr('customization'), subtitle: 'Aquí puedes controlar la personalidad global y el comportamiento visual de cada zona. Los controles se reorganizan automáticamente para conservar legibilidad en móviles, tablets y pantallas grandes.'),
      Padding(padding: EdgeInsets.symmetric(horizontal: Responsive.pagePad(context, controller)), child: SectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('✨ Presets rápidos', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
        const SizedBox(height: 6),
        Text('Prueba una identidad completa y después ajusta cada detalle manualmente.', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _ChoicePill(label: 'Cozy', selected: false, onTap: () => controller.applyPreset('cozy')),
          _ChoicePill(label: 'Dark academia', selected: false, onTap: () => controller.applyPreset('dark_academia')),
          _ChoicePill(label: 'Sakura', selected: controller.style == 'sakura', onTap: () => controller.applyPreset('sakura')),
          _ChoicePill(label: 'Minimal', selected: false, onTap: () => controller.applyPreset('minimal')),
        ]),
      ]))),
      const SizedBox(height: 14),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: Responsive.pagePad(context, controller)),
        child: SectionCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('🖼️ Galería de estéticas', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 6),
            Text('Toca una estética para aplicar su combinación de color, tipografía, fondo y tarjetas.', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 14),
            LayoutBuilder(builder: (context, constraints) {
              final columns = constraints.maxWidth < 430 ? 2 : constraints.maxWidth < 720 ? 3 : 4;
              final gap = Responsive.narrow(context) ? 9.0 : 12.0;
              final itemWidth = (constraints.maxWidth - gap * (columns - 1)) / columns;
              final entries = const [
                ['cozy','Cozy','Cálido · suave','warm'],
                ['romance','Romántico','Dulce · soñador','dreamy'],
                ['fantasy','Fantasía','Místico · etéreo','mystic'],
                ['gothic','Gótico','Oscuro · dramático','moody'],
                ['dark_academia','Dark academia','Editorial · clásico','moody'],
                ['cottagecore','Cottagecore','Natural · acogedor','calm'],
                ['whimsigoth','Whimsigoth','Místico · bohemio','mystic'],
                ['minimal','Minimal','Limpio · funcional','calm'],
                ['celestial','Celestial','Cósmico · soñador','mystic'],
                ['botanical','Botánico','Verde · orgánico','airy'],
                ['ocean','Ocean','Fresco · sereno','calm'],
                ['retro','Retro','Analógico · nostálgico','bright'],
                ['noir','Noir','Sobrio · cinematográfico','moody'],
                ['sunset','Sunset','Cálido · vibrante','bright'],
                ['sakura','Sakura','Rosado · delicado','dreamy'],
                ['parchment','Pergamino','Clásico · antiguo','warm'],
              ];
              final paletteByStyle = const {
                'cozy': [Color(0xFFB76E5E), Color(0xFFD08B73)], 'romance': [Color(0xFFC77887), Color(0xFFB59BC9)],
                'fantasy': [Color(0xFF756EA8), Color(0xFF8C70A9)], 'gothic': [Color(0xFF74506C), Color(0xFF6F667D)],
                'dark_academia': [Color(0xFF517663), Color(0xFFB18A63)], 'cottagecore': [Color(0xFF71815B), Color(0xFF8AA79B)],
                'whimsigoth': [Color(0xFF9A5C78), Color(0xFF8C70A9)], 'minimal': [Color(0xFF5D6B9A), Color(0xFF6F7A99)],
                'celestial': [Color(0xFF425774), Color(0xFF8C70A9)], 'botanical': [Color(0xFF517663), Color(0xFF6D8773)],
                'ocean': [Color(0xFF4F8190), Color(0xFF8AA79B)], 'retro': [Color(0xFFB18A63), Color(0xFFE2AE55)],
                'noir': [Color(0xFF5D6B9A), Color(0xFF6F667D)], 'sunset': [Color(0xFFC46F62), Color(0xFFE2AE55)],
                'sakura': [Color(0xFFC77887), Color(0xFFE2AE55)], 'parchment': [Color(0xFFC59B45), Color(0xFFD08B73)],
              };
              return Wrap(spacing: gap, runSpacing: gap, children: entries.map((entry) {
                final key = entry[0];
                final label = entry[1];
                final descriptor = entry[2];
                final moodLabel = entry[3];
                final active = controller.style == key;
                final swatches = paletteByStyle[key] ?? const [Color(0xFFB76E5E), Color(0xFFD08B73)];
                return SizedBox(
                  width: itemWidth,
                  child: Semantics(
                    button: true,
                    label: 'Aplicar estética $label',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => unawaited(controller.applyPreset(key)),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        decoration: BoxDecoration(
                          color: active ? Theme.of(context).colorScheme.primary.withValues(alpha: .07) : Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(active ? 22 : 20),
                          border: Border.all(
                            color: active ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .35),
                            width: active ? 2.3 : 1,
                          ),
                          boxShadow: active ? [BoxShadow(color: Theme.of(context).colorScheme.primary.withValues(alpha: .15), blurRadius: 18, offset: const Offset(0, 7))] : const [],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Stack(children: [
                            AspectRatio(aspectRatio: 1.36, child: Image.asset('assets/themes/$key.png', fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => Container(color: swatches[0].withValues(alpha: .18), alignment: Alignment.center, child: Icon(Icons.image_not_supported_outlined, color: swatches[0])))),
                            if (active) Positioned(top: 9, right: 9, child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5), decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(999)), child: const Text('ACTIVO', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 9, letterSpacing: .6)))),
                          ]),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(11, 10, 11, 11),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13))),
                                const SizedBox(width: 7),
                                Row(children: [Container(width: 9, height: 9, decoration: BoxDecoration(color: swatches[0], shape: BoxShape.circle)), const SizedBox(width: 4), Container(width: 9, height: 9, decoration: BoxDecoration(color: swatches[1], shape: BoxShape.circle))]),
                              ]),
                              const SizedBox(height: 4),
                              Text(descriptor, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 5),
                              Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3), decoration: BoxDecoration(color: swatches[0].withValues(alpha: .10), borderRadius: BorderRadius.circular(999)), child: Text(moodLabel, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: swatches[0]))),
                            ]),
                          ),
                        ]),
                      ),
                    ),
                  ),
                );
              }).toList());
            }),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      Padding(padding: EdgeInsets.symmetric(horizontal: Responsive.pagePad(context, controller)), child: SectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('🎨 Color y ambiente', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
        const SizedBox(height: 10),
        Wrap(spacing: 9, runSpacing: 9, children: palettes.entries.map((entry) => InkWell(onTap: () => controller.updateSettings(newPalette: entry.key), borderRadius: BorderRadius.circular(18), child: AnimatedContainer(duration: const Duration(milliseconds: 180), width: Responsive.narrow(context) ? 44 : 50, height: Responsive.narrow(context) ? 44 : 50, decoration: BoxDecoration(color: entry.value, borderRadius: BorderRadius.circular(18), border: Border.all(color: controller.palette == entry.key ? Theme.of(context).colorScheme.onSurface : Colors.transparent, width: 3), boxShadow: controller.palette == entry.key ? [BoxShadow(color: entry.value.withValues(alpha: .34), blurRadius: 14)] : const []), child: controller.palette == entry.key ? const Icon(Icons.check_rounded, color: Colors.white) : null))).toList()),
        const SizedBox(height: 12),
        Text('Intensidad de acento: ${(controller.accentIntensity * 100).round()}%'),
        Slider(value: controller.accentIntensity, min: .15, max: 1, divisions: 17, onChanged: (v) => controller.updateSettings(newAccentIntensity: v)),
        fieldGrid([
          select(label: 'Estilo literario', value: controller.style, options: styles, onChanged: (v) => controller.updateSettings(newStyle: v)),
          select(label: 'Ambiente emocional', value: controller.mood, options: moods, onChanged: (v) => controller.updateSettings(newMood: v)),
          select(label: 'Fondo', value: controller.background, options: backgrounds, onChanged: (v) => controller.updateSettings(newBackground: v)),
        ]),
        const SizedBox(height: 10),
        Text('Intensidad del fondo: ${(controller.backgroundOpacity * 100).round()}%'),
        Slider(value: controller.backgroundOpacity.clamp(0.02, .32), min: .02, max: .32, divisions: 15, onChanged: (v) => controller.updateSettings(newBackgroundOpacity: v)),
      ]))),
      const SizedBox(height: 12),
      Padding(padding: EdgeInsets.symmetric(horizontal: Responsive.pagePad(context, controller)), child: SectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('🧩 Forma de la interfaz', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
        const SizedBox(height: 10),
        fieldGrid([
          select(label: 'Tarjetas', value: controller.cardStyle, options: cards, onChanged: (v) => controller.updateSettings(newCardStyle: v)),
          select(label: 'Densidad', value: controller.density, options: densities, onChanged: (v) => controller.updateSettings(newDensity: v)),
          select(label: 'Forma de las portadas', value: controller.coverShape, options: coverShapes, onChanged: (v) => controller.updateSettings(newCoverShape: v)),
          select(label: 'Navegación', value: controller.navigationStyle, options: navStyles, onChanged: (v) => controller.updateSettings(newNavigationStyle: v)),
        ]),
        const SizedBox(height: 10),
        fieldGrid([
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Redondeado global: ${controller.cornerRadius.round()}'), Slider(value: controller.cornerRadius, min: 6, max: 38, divisions: 16, onChanged: (v) => controller.updateSettings(newCornerRadius: v))]),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Escala de títulos: ${(controller.titleScale * 100).round()}%'), Slider(value: controller.titleScale, min: .82, max: 1.25, divisions: 17, onChanged: (v) => controller.updateSettings(newTitleScale: v))]),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Escala general: ${(controller.uiScale * 100).round()}%'), Slider(value: controller.uiScale.clamp(.95, 1.10), min: .95, max: 1.10, divisions: 6, onChanged: (v) => controller.updateSettings(newUiScale: v))]),
          select(label: 'Ancho del contenido', value: controller.contentWidth, options: const {'narrow':'Estrecho · más foco', 'standard':'Estándar', 'wide':'Amplio', 'full':'Máximo'}, onChanged: (v) => controller.updateSettings(newContentWidth: v)),
          select(label: 'Espaciado interior', value: controller.spacing, options: const {'compact':'Compacto', 'comfortable':'Cómodo', 'airy':'Aireado', 'roomy':'Muy espacioso'}, onChanged: (v) => controller.updateSettings(newSpacing: v)),
        ]),
        const SizedBox(height: 12),
        fieldGrid([
          settingSwitch('Sombras y brillos', 'Añade profundidad a tarjetas y controles.', controller.decorations, (v) => controller.updateSettings(newDecorations: v)),
          settingSwitch('Doodles globales', 'Pequeños trazos decorativos en la interfaz y calendarios.', controller.doodles, (v) => controller.updateSettings(newDoodles: v)),
          settingSwitch('Animaciones', 'Transiciones y cambios suaves.', controller.animations, (v) => controller.updateSettings(newAnimations: v)),
          settingSwitch('Modo oscuro', 'Mantiene el estilo elegido pero adapta la luminancia.', controller.darkMode, (v) => controller.updateSettings(newDark: v)),
          settingSwitch('Subtítulo de cabecera', 'Muestra u oculta el texto bajo READBLOOM.', controller.showAppTagline, (v) => controller.updateSettings(newShowAppTagline: v)),
        ]),
      ]))),
      const SizedBox(height: 12),
      Padding(padding: EdgeInsets.symmetric(horizontal: Responsive.pagePad(context, controller)), child: SectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('📚 Biblioteca', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
        const SizedBox(height: 10),
        fieldGrid([
          select(label: 'Vista al abrir', value: controller.libraryDefaultView, options: views, onChanged: (v) => controller.updateSettings(newLibraryDefaultView: v)),
          select(label: 'Orden por defecto', value: controller.librarySort, options: const {'recent':'Más recientes', 'title':'Título A–Z', 'rating':'Valoración', 'pages':'Páginas'}, onChanged: (v) => controller.updateSettings(newLibrarySort: v)),
        ]),
        const SizedBox(height: 12),
        fieldGrid([
          settingSwitch('Favoritos primero', 'Da prioridad a tus libros marcados con corazón.', controller.favoritesFirst, (v) => controller.updateSettings(newFavoritesFirst: v)),
          settingSwitch('Progreso en tarjetas', 'Muestra página actual y barra de progreso.', controller.showProgressOnCards, (v) => controller.updateSettings(newShowProgressOnCards: v)),
          settingSwitch('Autor en tarjetas', 'Muestra el nombre debajo del título.', controller.showAuthorOnCards, (v) => controller.updateSettings(newShowAuthorOnCards: v)),
        ]),
      ]))),
      const SizedBox(height: 12),
      Padding(padding: EdgeInsets.symmetric(horizontal: Responsive.pagePad(context, controller)), child: SectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('📊 Estadísticas y calendario', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
        const SizedBox(height: 10),
        fieldGrid([
          select(label: 'Estilo de estadísticas', value: controller.statsStyle, options: statsStyles, onChanged: (v) => controller.updateSettings(newStatsStyle: v)),
          select(label: 'Estilo del calendario', value: controller.calendarStyle, options: calendarStyles, onChanged: (v) => controller.updateSettings(newCalendarStyle: v)),
        ]),
        const SizedBox(height: 12),
        fieldGrid([
          settingSwitch('Mostrar calendario', 'Activa o desactiva el calendario de actividad lectora.', controller.showStatsCalendar, (v) => controller.updateSettings(newShowStatsCalendar: v)),
        ]),
      ]))),
      const SizedBox(height: 12),
      Padding(padding: EdgeInsets.symmetric(horizontal: Responsive.pagePad(context, controller)), child: SectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('✨ Wrapped', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
        const SizedBox(height: 10),
        fieldGrid([
          select(label: 'Plantilla favorita', value: controller.wrappedTemplate, options: const {'scrapbook':'Scrapbook', 'editorial':'Editorial', 'dreamy':'Dreamy', 'minimal':'Minimal', 'poster':'Poster'}, onChanged: (v) => controller.updateSettings(newWrappedTemplate: v)),
          select(label: 'Patrón favorito', value: controller.wrappedPattern, options: const {'doodles':'Doodles', 'stars':'Estrellas', 'botanical':'Botánico', 'paper':'Papel', 'clean':'Limpio'}, onChanged: (v) => controller.updateSettings(newWrappedPattern: v)),
          select(label: 'Formato favorito', value: controller.wrappedRatio, options: const {'story':'Historia 9:16', 'portrait':'Vertical 4:5', 'square':'Cuadrado'}, onChanged: (v) => controller.updateSettings(newWrappedRatio: v)),
        ]),
        const SizedBox(height: 6),
        Text('Los cambios también se pueden ajustar al crear cada Wrapped.', style: Theme.of(context).textTheme.bodySmall),
      ]))),
      const SizedBox(height: 12),
      Padding(padding: EdgeInsets.symmetric(horizontal: Responsive.pagePad(context, controller)), child: SectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('🪴 Bookish', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
        const SizedBox(height: 10),
        fieldGrid([
          select(label: 'Escena favorita', value: controller.bookishScene, options: const {'cozy':'Cozy café', 'cottage':'Cottage garden', 'gothic':'Gothic library', 'pastel':'Pastel dream', 'minimal':'Minimal'}, onChanged: (v) => controller.updateSettings(newBookishScene: v)),
          select(label: 'Estantería favorita', value: controller.bookishShelf, options: const {'wood':'Madera cálida', 'marble':'Mármol', 'floating':'Flotante', 'rainbow':'Arcoíris'}, onChanged: (v) => controller.updateSettings(newBookishShelf: v)),
          select(label: 'Decoración favorita', value: controller.bookishDecor, options: const {'plants':'Plantas + café', 'flowers':'Flores + lazos', 'moon':'Luna + estrellas', 'minimal':'Minimal'}, onChanged: (v) => controller.updateSettings(newBookishDecor: v)),
          select(label: 'Mostrar libros como', value: controller.bookishDisplay, options: const {'covers':'Portadas', 'spines':'Lomos', 'mix':'Mezcla'}, onChanged: (v) => controller.updateSettings(newBookishDisplay: v)),
          select(label: 'Formato favorito', value: controller.bookishRatio, options: const {'portrait':'Vertical 4:5', 'story':'Historia 9:16', 'square':'Cuadrado'}, onChanged: (v) => controller.updateSettings(newBookishRatio: v)),
        ]),
      ]))),
      const SizedBox(height: 12),
      Padding(padding: EdgeInsets.symmetric(horizontal: Responsive.pagePad(context, controller)), child: SectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('🌍 Idioma y tipografía', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
        const SizedBox(height: 10),
        fieldGrid([
          select(label: controller.tr('language'), value: controller.localeCode, options: languages, onChanged: (v) => controller.updateSettings(newLocale: v)),
          select(label: controller.tr('typography'), value: controller.fontStyle, options: fonts, onChanged: (v) => controller.updateSettings(newFont: v)),
        ]),
      ]))),
      const SizedBox(height: 12),
      Padding(padding: EdgeInsets.symmetric(horizontal: Responsive.pagePad(context, controller)), child: SectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('💾 Datos', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
        const SizedBox(height: 6),
        const Text('Guarda una copia completa de libros, retos y personalización para restaurarla en otro dispositivo.'),
        const SizedBox(height: 12),
        Row(children: [Expanded(child: FilledButton.tonalIcon(onPressed: () => _exportBackup(context, controller), icon: const Icon(Icons.upload_file_rounded), label: const Text('Exportar copia'))), const SizedBox(width: 10), Expanded(child: OutlinedButton.icon(onPressed: () => _importBackup(context, controller), icon: const Icon(Icons.download_rounded), label: const Text('Restaurar')))]),
      ]))),
      const SizedBox(height: 12),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [controller.seedColor, controller.moodAccent]), borderRadius: BorderRadius.circular(controller.cornerRadius)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(Icons.auto_awesome_rounded, color: Colors.white.withValues(alpha: .9)), const SizedBox(width: 8), const Text('LIVE PREVIEW', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, letterSpacing: 2))]),
        const SizedBox(height: 8),
        Text('READBLOOM', style: TextStyle(color: Colors.white, fontSize: 27 * controller.titleScale, fontWeight: FontWeight.w900, letterSpacing: 2.2)),
        const SizedBox(height: 12),
        Row(children: [Expanded(child: Container(height: 46, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .18), borderRadius: BorderRadius.circular(controller.cornerRadius)))), const SizedBox(width: 10), ClipRRect(borderRadius: BorderRadius.circular(controller.cornerRadius), child: Image.asset('assets/readbloom_logo.png', width: 46, height: 46, fit: BoxFit.cover))]),
        const SizedBox(height: 12),
        Text('${styles[controller.style] ?? controller.style} · ${moods[controller.mood] ?? controller.mood} · ${cards[controller.cardStyle] ?? controller.cardStyle}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ]))),
    ]);
  }
}

Future<String?> _imageToDataUri(String path) async {
  if (path.isEmpty || !File(path).existsSync()) return null;
  final bytes = await File(path).readAsBytes();
  return 'data:image/*;base64,${base64Encode(bytes)}';
}

// Kept isolated for future Android / Windows extensions.
// ignore: unused_element
Future<String?> _safeCoverUri(String path) => _imageToDataUri(path);
