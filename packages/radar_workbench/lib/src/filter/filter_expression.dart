// lib/src/filter/filter_expression.dart

/// A small boolean filter language for Memory table rows.
///
/// Supports `field:value` terms (`class:`, `library:`/`lib:`, `package:`,
/// `origin:`), bare substring terms, `&&` / `||` / `!` operators with the
/// usual precedence (`!` > `&&` > `||`), parentheses, and implicit `&&`
/// between whitespace-separated terms. Parsing never throws: a
/// malformed expression degrades to "match everything" and surfaces
/// a human-readable [FilterExpression.error] instead.
library;

import 'package:radar_ui/radar_ui.dart';

import '../memory/mem_format.dart';

/// Preset filter hiding non-project runtime noise: framework and SDK
/// classes. Applied as a one-tap chip; never a default.
const String kHideFrameworkFilter = '!origin:framework !origin:sdk';

/// Anything the filter matches against.
abstract interface class FilterTarget {
  /// The simple class name (e.g. `_MyWidgetState`).
  String get className;

  /// The owning library URI, or `null` if unknown.
  Uri? get libraryUri;
}

/// A parsed leaf term, surfaced as one removable chip.
final class FilterChipData {
  /// Creates chip data for a single parsed leaf term.
  const FilterChipData({
    required this.leafId,
    required this.field,
    required this.value,
    required this.negated,
  });

  /// Stable id: the index of this leaf in left-to-right traversal.
  final int leafId;

  /// One of `'class'`, `'library'`, `'package'`, `'origin'`, or `'text'`.
  final String field;

  /// The raw (unquoted) term value.
  final String value;

  /// Whether this leaf was written with a literal leading `!`.
  final bool negated;

  /// Display label, e.g. `class:Foo`, `!library:app`, or `Foo`.
  String get label {
    final core = field == 'text' ? value : '$field:$value';
    return negated ? '!$core' : core;
  }
}

/// Immutable parsed filter. Build via [FilterExpression.parse].
final class FilterExpression {
  const FilterExpression._(this._root, this.error, this.text, this.chips);

  /// The empty (matches-all) filter.
  static final FilterExpression empty = FilterExpression.parse('');

  /// Parses [input].
  ///
  /// Never throws. On a syntax error, [error] is non-null and
  /// [matches] returns `true` for everything (the UI degrades to
  /// "show all" and displays the error instead of the chip row).
  factory FilterExpression.parse(String input) {
    try {
      final parser = _Parser(input);
      final root = parser.parse();
      if (root == null) {
        return const FilterExpression._(null, null, '', []);
      }
      final chips = <FilterChipData>[];
      root.collectChips(chips);
      return FilterExpression._(root, null, root.render(0), chips);
    } on _ParseError catch (e) {
      return FilterExpression._(null, e.message, input, const []);
    } on Object catch (e) {
      // Defense in depth: this contract must never throw into UI code,
      // even if an unanticipated input trips up the hand-rolled parser.
      return FilterExpression._(null, e.toString(), input, const []);
    }
  }

  final _Node? _root;

  /// Non-null when [input] failed to parse; `null` otherwise.
  final String? error;

  /// Canonical source text, regenerated from the AST.
  final String text;

  /// Leaves in left-to-right order, one per chip.
  final List<FilterChipData> chips;

  /// Whether [target] matches this filter.
  ///
  /// An empty filter or a filter with a parse [error] matches
  /// everything. [projectPackages] resolves `origin:` terms (see
  /// [originOf]); it's session-level context, not part of [target], so it
  /// defaults to the empty set for callers that don't have it.
  bool matches(FilterTarget target, {Set<String> projectPackages = const {}}) =>
      _root?.matches(target, projectPackages) ?? true;

  /// Whether this filter has no leaves (matches everything).
  bool get isEmpty => chips.isEmpty;

  /// Returns a new expression with leaf [leafId] removed.
  ///
  /// The AST is simplified (empty `&&`/`||`/`!` nodes collapsed) and
  /// [text] is regenerated so the result stays re-parseable.
  FilterExpression removeLeaf(int leafId) {
    final root = _root;
    if (root == null) return this;
    final pruned = root.prune(leafId);
    if (pruned == null) {
      return const FilterExpression._(null, null, '', []);
    }
    final newChips = <FilterChipData>[];
    pruned.collectChips(newChips);
    return FilterExpression._(pruned, null, pruned.render(0), newChips);
  }
}

// ── AST ──────────────────────────────────────────────────────────────────

/// `||` binds loosest.
const int _orPrecedence = 0;

/// `&&` (implicit or explicit) binds tighter than `||`.
const int _andPrecedence = 1;

sealed class _Node {
  const _Node();

  bool matches(FilterTarget target, Set<String> projectPackages);

  /// Returns the logical negation of this node.
  _Node negate();

  /// Appends this node's leaves, left to right, to [out].
  void collectChips(List<FilterChipData> out);

  /// Removes leaf [leafId], returning `null` if this whole subtree
  /// was the removed leaf (or collapsed to nothing).
  _Node? prune(int leafId);

  /// Renders canonical text; wraps in parens if this node's own
  /// precedence is lower than [minPrecedence].
  String render(int minPrecedence);
}

final class _TermNode extends _Node {
  const _TermNode({
    required this.leafId,
    required this.field,
    required this.value,
    required this.negated,
  });

  final int leafId;
  final String field;
  final String value;
  final bool negated;

  @override
  bool matches(FilterTarget target, Set<String> projectPackages) {
    final lowerValue = value.toLowerCase();
    final result = switch (field) {
      'class' => target.className.toLowerCase().contains(lowerValue),
      'library' =>
        target.libraryUri?.toString().toLowerCase().contains(lowerValue) ??
            false,
      'package' =>
        packageLabelOf(target.libraryUri)?.toLowerCase().contains(lowerValue) ??
            false,
      'origin' => _matchesOrigin(target, projectPackages, lowerValue),
      _ => target.className.toLowerCase().contains(lowerValue),
    };
    return negated ? !result : result;
  }

  @override
  _Node negate() =>
      _TermNode(leafId: leafId, field: field, value: value, negated: !negated);

  @override
  void collectChips(List<FilterChipData> out) {
    out.add(
      FilterChipData(
        leafId: leafId,
        field: field,
        value: value,
        negated: negated,
      ),
    );
  }

  @override
  _Node? prune(int id) => leafId == id ? null : this;

  @override
  String render(int minPrecedence) {
    final literal = _quoteIfNeeded(value);
    final core = field == 'text' ? literal : '$field:$literal';
    return negated ? '!$core' : core;
  }
}

/// Matches a `origin:` leaf value (already lowercased) against the
/// [RadarOrigin] resolved for [target]. `'yours'` aliases to `'project'`;
/// an unrecognized value never matches (degrade to absent, not a guess).
bool _matchesOrigin(
  FilterTarget target,
  Set<String> projectPackages,
  String value,
) {
  final origin = originOf(target.libraryUri, projectPackages: projectPackages);
  final normalized = value == 'yours' ? 'project' : value;
  return origin.name == normalized;
}

final class _AndNode extends _Node {
  const _AndNode(this.left, this.right);

  final _Node left;
  final _Node right;

  @override
  bool matches(FilterTarget target, Set<String> projectPackages) =>
      left.matches(target, projectPackages) &&
      right.matches(target, projectPackages);

  @override
  _Node negate() => _NotNode(this);

  @override
  void collectChips(List<FilterChipData> out) {
    left.collectChips(out);
    right.collectChips(out);
  }

  @override
  _Node? prune(int id) {
    final newLeft = left.prune(id);
    final newRight = right.prune(id);
    if (newLeft == null) return newRight;
    if (newRight == null) return newLeft;
    return _AndNode(newLeft, newRight);
  }

  @override
  String render(int minPrecedence) {
    final content =
        '${left.render(_andPrecedence)} && ${right.render(_andPrecedence)}';
    return _andPrecedence < minPrecedence ? '($content)' : content;
  }
}

final class _OrNode extends _Node {
  const _OrNode(this.left, this.right);

  final _Node left;
  final _Node right;

  @override
  bool matches(FilterTarget target, Set<String> projectPackages) =>
      left.matches(target, projectPackages) ||
      right.matches(target, projectPackages);

  @override
  _Node negate() => _NotNode(this);

  @override
  void collectChips(List<FilterChipData> out) {
    left.collectChips(out);
    right.collectChips(out);
  }

  @override
  _Node? prune(int id) {
    final newLeft = left.prune(id);
    final newRight = right.prune(id);
    if (newLeft == null) return newRight;
    if (newRight == null) return newLeft;
    return _OrNode(newLeft, newRight);
  }

  @override
  String render(int minPrecedence) {
    final content =
        '${left.render(_orPrecedence)} || ${right.render(_orPrecedence)}';
    return _orPrecedence < minPrecedence ? '($content)' : content;
  }
}

/// Wraps a compound (`&&`/`||`) node in a logical `!`.
///
/// Negating a single term folds the flag into [_TermNode.negated]
/// instead (see [_TermNode.negate]), so [child] here is always an
/// [_AndNode] or [_OrNode] by construction.
final class _NotNode extends _Node {
  const _NotNode(this.child);

  final _Node child;

  @override
  bool matches(FilterTarget target, Set<String> projectPackages) =>
      !child.matches(target, projectPackages);

  @override
  _Node negate() => child;

  @override
  void collectChips(List<FilterChipData> out) => child.collectChips(out);

  @override
  _Node? prune(int id) {
    final newChild = child.prune(id);
    return newChild?.negate();
  }

  @override
  String render(int minPrecedence) => '!(${child.render(0)})';
}

String _quoteIfNeeded(String raw) {
  if (raw.isNotEmpty && !_needsQuoteRe.hasMatch(raw)) return raw;
  final escaped = raw.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  return '"$escaped"';
}

final RegExp _needsQuoteRe = RegExp(r'[\s()!&|"]');

// ── Parser ───────────────────────────────────────────────────────────────

class _ParseError implements Exception {
  _ParseError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Hand-rolled recursive-descent parser.
///
/// Grammar (highest to lowest precedence):
/// ```
/// or    := and ('||' and)*
/// and   := not (('&&')? not)*      // trailing not = implicit &&
/// not   := '!' not | atom
/// atom  := '(' or ')' | term
/// term  := (FIELD ':')? (WORD | '"' ... '"')
/// ```
class _Parser {
  _Parser(this._src);

  final String _src;
  int _pos = 0;
  int _leafCounter = 0;

  static final RegExp _wordRe = RegExp(r'[A-Za-z0-9_$./:-]+');

  /// Parses the whole input, returning `null` for an empty/blank
  /// expression. Throws [_ParseError] on malformed syntax.
  _Node? parse() {
    _skipWs();
    if (_pos >= _src.length) return null;
    final node = _parseOr();
    _skipWs();
    if (_pos != _src.length) {
      throw _ParseError('Unexpected trailing input at position $_pos');
    }
    return node;
  }

  _Node _parseOr() {
    var left = _parseAnd();
    while (_tryConsumeOp('||')) {
      final right = _parseAnd();
      left = _OrNode(left, right);
    }
    return left;
  }

  _Node _parseAnd() {
    var left = _parseNot();
    while (true) {
      if (_tryConsumeOp('&&')) {
        left = _AndNode(left, _parseNot());
        continue;
      }
      if (_looksLikeAtomStart()) {
        left = _AndNode(left, _parseNot());
        continue;
      }
      break;
    }
    return left;
  }

  _Node _parseNot() {
    _skipWs();
    if (_pos < _src.length && _src[_pos] == '!') {
      _pos++;
      return _parseNot().negate();
    }
    return _parseAtom();
  }

  _Node _parseAtom() {
    _skipWs();
    if (_pos >= _src.length) {
      throw _ParseError('Unexpected end of input');
    }
    final c = _src[_pos];
    if (c == '(') {
      _pos++;
      final inner = _parseOr();
      _skipWs();
      if (_pos >= _src.length || _src[_pos] != ')') {
        throw _ParseError('Expected ")" at position $_pos');
      }
      _pos++;
      return inner;
    }
    if (c == ')') {
      throw _ParseError('Unexpected ")" at position $_pos');
    }
    return _parseTerm();
  }

  _Node _parseTerm() {
    if (_src[_pos] == '"') {
      final value = _parseQuoted();
      return _TermNode(
        leafId: _leafCounter++,
        field: 'text',
        value: value,
        negated: false,
      );
    }
    final raw = _scanWord();
    if (raw.isEmpty) {
      throw _ParseError('Unexpected character "${_src[_pos]}"');
    }
    final colonIndex = raw.indexOf(':');
    if (colonIndex > 0) {
      final field = _normalizeField(raw.substring(0, colonIndex));
      if (field != null) {
        final rest = raw.substring(colonIndex + 1);
        if (rest.isNotEmpty) {
          return _TermNode(
            leafId: _leafCounter++,
            field: field,
            value: rest,
            negated: false,
          );
        }
        if (_pos < _src.length && _src[_pos] == '"') {
          final value = _parseQuoted();
          return _TermNode(
            leafId: _leafCounter++,
            field: field,
            value: value,
            negated: false,
          );
        }
        throw _ParseError('Field "$field" has no value');
      }
    }
    return _TermNode(
      leafId: _leafCounter++,
      field: 'text',
      value: raw,
      negated: false,
    );
  }

  String? _normalizeField(String raw) {
    final lower = raw.toLowerCase();
    if (lower == 'class') return 'class';
    if (lower == 'library' || lower == 'lib') return 'library';
    if (lower == 'package') return 'package';
    if (lower == 'origin') return 'origin';
    return null;
  }

  String _scanWord() {
    final match = _wordRe.matchAsPrefix(_src, _pos);
    if (match == null) return '';
    _pos = match.end;
    return match.group(0)!;
  }

  String _parseQuoted() {
    // Assumes _src[_pos] == '"'.
    _pos++;
    final buffer = StringBuffer();
    while (_pos < _src.length) {
      final c = _src[_pos];
      if (c == '"') {
        _pos++;
        return buffer.toString();
      }
      if (c == r'\' &&
          _pos + 1 < _src.length &&
          (_src[_pos + 1] == '"' || _src[_pos + 1] == r'\')) {
        buffer.write(_src[_pos + 1]);
        _pos += 2;
        continue;
      }
      buffer.write(c);
      _pos++;
    }
    throw _ParseError('Unterminated quoted string');
  }

  bool _tryConsumeOp(String op) {
    final saved = _pos;
    _skipWs();
    if (_src.startsWith(op, _pos)) {
      _pos += op.length;
      return true;
    }
    _pos = saved;
    return false;
  }

  bool _looksLikeAtomStart() {
    final saved = _pos;
    _skipWs();
    final isStart =
        _pos < _src.length &&
        _src[_pos] != ')' &&
        _src[_pos] != '&' &&
        _src[_pos] != '|';
    _pos = saved;
    return isStart;
  }

  void _skipWs() {
    while (_pos < _src.length && _isWs(_src[_pos])) {
      _pos++;
    }
  }

  bool _isWs(String c) => c == ' ' || c == '\t' || c == '\n' || c == '\r';
}
