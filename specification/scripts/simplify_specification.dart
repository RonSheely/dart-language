// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Create a simplified version of 'dartLangSpec.tex'.
///
/// This script creates a version of 'dartLangSpec.tex' that does not
/// contain comments, commentary text, or rationale text. It eliminates
/// all newline characters in a paragraph (that is, each paragraph is
/// entirely on the same line).
///
/// The purpose of this transformation is that the output can be grepped
/// more effectively (the original version may have a newline in the
/// middle of the phrase that we're looking for), and more precisely
/// (the originl version could have hits in comments, commentary, etc,
/// and it is assumed that we only want to find normative text).
///
/// The script should be executed with '..' as the current directory,
/// that is, the directory where 'dartLangSpec.tex' is located.
library;

import 'dart:io';

void main() {
  final inputFile = File(specificationFilename);
  if (!inputFile.existsSync()) fail("Specification not found");
  final contents = inputFile.readAsLinesSync();
  final workingContents =
      List<String?>.from(contents, growable: false)
        ..removeComments()
        ..removeDartCode()
        ..removeTrailingWhitespace()
        ..removeNonNormative()
        ..joinLines()
        ..removeTrailingWhitespace()
        ..removeSpuriousEmptyLines();
  final simplifiedContents = workingContents.whereType<String>().toList();
  final outputFile = File(outputFilename);
  final outputSink = outputFile.openWrite();
  simplifiedContents.forEach(outputSink.writeln);
}

const outputFilename = 'dartLangSpec-terse.tex';

const specificationFilename = 'dartLangSpec.tex';

const percentCodeUnit = 37; // Encoding of '%'.

void fail(String message) {
  print("simplify_specification error: $message");
  exit(-1);
}

// Several steps in the algorithm are processing ranges of lines.
// Typically, those ranges are not expected to include the last line in
// the specification (we're just processing a block of sorts, somewhere
// in the middle of the document). This function is called after loops
// that are doing this kind of processing because the loop is expected
// to reach a `return` statement rather than completing normally.
Never endOfTextFailure() {
  throw StateError("Internal error: reached end of text.");
}

extension on String {
  bool get endsCode => startsWith(r"\end{normativeDartCode}");
  bool get endsList =>
      startsWith(r"\end{itemize}") || startsWith(r"\end{enumerate}");
  bool get endsMinipage => contains(r"\end{minipage}");
  bool get isItem => startsWith(r"\item");
  bool get startsCode => startsWith(r"\begin{normativeDartCode}");
  bool get startsList =>
      startsWith(r"\begin{itemize}") || startsWith(r"\begin{enumerate}");
  bool get startsMinipage => contains(r"\begin{minipage}");
}

extension on List<String?> {
  static final _commentRegExp = RegExp(r"^%|[^%\\]%");
  static final _commentaryRationaleRegExp = RegExp(
    r"^ *\(?\\(commentary|rationale){",
  );
  static final _bracesRegExp = RegExp(r"\\[a-zA-Z]*{.*}");
  static final _parenBracesRexExp = RegExp(r"\(\\[a-zA-Z]*{.*}\)");

  void joinLines() {
    bool inFrontMatter = true;
    for (var lineIndex = 0; lineIndex < length; ++lineIndex) {
      final line = this[lineIndex]; // Invariant.
      if (line == null) continue;
      if (inFrontMatter) {
        if (line.startsWith(r"\begin{document}")) inFrontMatter = false;
        continue;
      }
      if (line.startsWith(r"\LMHash{}")) {
        lineIndex = _gatherParagraph(lineIndex);
      } else if (line.startsWith(r"\noindent")) {
        lineIndex = _gatherContinuedParagraph(lineIndex);
      } else if (line.startsList) {
        lineIndex = _gatherItems(lineIndex);
      }
    }
  }

  // Eliminate comment-only lines. Reduce other comments to `%`.
  void removeComments() {
    for (int i = 0; i < length; ++i) {
      final line = this[i];
      if (line == null) continue; // It isn't, but flow-analysis doesn't know.
      final match = _commentRegExp.firstMatch(line);
      if (match != null) {
        if (match.start == 0) {
          this[i] = null; // A comment-only line disappears entirely.
        } else {
          final cutPosition = match.start + 2; // Include the `%`.
          if (line.trimLeft().codeUnitAt(0) == percentCodeUnit) {
            // An indented comment-only line disappears entirely.
            this[i] = null;
          } else {
            final resultLine = line.substring(0, cutPosition);
            assert(i < length - 1);
            this[i] = resultLine;
          }
        }
      } else if (line.startsWith("\\end{document}")) {
        // All text beyond `\end{document}` is a comment.
        for (int j = i + 1; j < length; ++j) this[j] = null;
        break;
      }
    }
  }

  /// Remove all blocks `\begin{dartCode} .. \end{dartCode}`.
  /// All of these are examples, described in commentary.
  void removeDartCode() {
    final length = this.length;
    var inDartCode = false;
    for (var index = 0; index < length; ++index) {
      final line = this[index];
      if (line == null) continue;
      if (line.startsWith(r"\begin{dartCode}")) {
        inDartCode = true;
      }
      if (inDartCode) this[index] = null;
      if (line.startsWith(r"\end{dartCode}")) {
        inDartCode = false;
      }
    }
  }

  /// Remove non-normative text elements.
  /// This method removes `\commentary{...}` and `\rationale{...}`,
  /// and it removes `\BlindDefineSymbol{...}`. It does not make
  /// any attempts to balance brace begin and brace end characters,
  /// it trusts the indentation to reflect this structure correctly.
  void removeNonNormative() {
    for (int i = 0; i < length; ++i) {
      final line = this[i];
      if (line == null) continue;
      if (line.startsWith(r"\BlindDefineSymbol{")) {
        this[i] = null;
        continue;
      }
      final match = _commentaryRationaleRegExp.firstMatch(line);
      if (match != null) {
        final matchParenthesizedOneliner = _parenBracesRexExp.firstMatch(line);
        if (matchParenthesizedOneliner != null) {
          if (matchParenthesizedOneliner.start == 0 &&
              matchParenthesizedOneliner.end == line.length) {
            this[i] = null;
          } else {
            this[i] = line.replaceRange(
              matchParenthesizedOneliner.start,
              matchParenthesizedOneliner.end,
              '',
            );
          }
        } else {
          final matchOneliner = _bracesRegExp.firstMatch(line);
          if (matchOneliner != null) {
            if (matchOneliner.start == 0 && matchOneliner.end == line.length) {
              this[i] = null;
            } else {
              this[i] = line.replaceRange(
                matchOneliner.start,
                matchOneliner.end,
                '',
              );
            }
          } else {
            final lineStart = _lineStart(line);
            while (i < length && this[i]?.startsWith(lineStart) != true) {
              this[i] = null;
              ++i;
            }
            if (i < length) this[i] = null;
          }
        }
      }
    }
  }

  void removeSpuriousEmptyLines() {
    final length = this.length;
    bool previousLineWasEmpty = false;
    for (int i = 0; i < length; ++i) {
      var line = this[i];
      if (line == null) continue;
      if (line.isEmpty) {
        if (previousLineWasEmpty) {
          this[i] = null;
        } else {
          previousLineWasEmpty = true;
        }
      } else {
        previousLineWasEmpty = false;
      }
    }
  }

  void removeTrailingWhitespace() {
    for (int i = 0; i < length; ++i) {
      final line = this[i];
      if (line == null) continue;
      if (line.isNotEmpty && _isWhitespace(line, line.length - 1)) {
        this[i] = line.trimRight();
      }
    }
  }

  /// Return the index of the first line, starting with [startIndex],
  /// that contains the command `\item`. Note that this implies
  /// `this[i] != null` where `i` is the returned value.
  int _findItem(final int startIndex) {
    final length = this.length;
    for (int searchIndex = startIndex; searchIndex < length; ++searchIndex) {
      final line = this[searchIndex];
      if (line == null) continue;
      final trimmedLine = line.trimLeft();
      // A well-formed document should have some items in every itemized list.
      if (trimmedLine.endsList) {
        fail("no items found (line $searchIndex seems to be malformed)");
      }
      if (trimmedLine.isItem) return searchIndex;
    }
    endOfTextFailure();
  }

  /// Return the index of the first non-empty line after [startIndex].
  int _findText(final int startIndex) {
    final length = this.length;
    for (int searchIndex = startIndex; searchIndex < length; ++searchIndex) {
      final line = this[searchIndex];
      if (line == null) continue;
      final trimmedLine = line.trim();
      if (trimmedLine.isNotEmpty) {
        return searchIndex;
      }
    }
    endOfTextFailure();
  }

  /// Gather the text in lines `paragraphIndex + 1` into
  /// a single line and store it at [paragraphIndex].
  /// The line at [paragraphIndex] is expected to contain
  /// `\noindent` which will be preserved.
  int _gatherContinuedParagraph(final int paragraphIndex) =>
      _gatherParagraphBase(paragraphIndex, StringBuffer(r"\noindent "));

  /// Starting from the line with index [listIndex], which is assumed
  /// to start with `\begin{itemize}` or `\begin{enumerate}`, search for
  /// `\item` commands and gather the subsequent lines for each item into a
  /// single line. Also handle nested itemized lists (no attempt to balance
  /// them, we just rely on finding `\end{itemize}` or `\end{enumerate}` at
  /// the beginning of a line). Return the index of the first line after the
  /// itemized list.
  int _gatherItems(final int listIndex) {
    final length = this.length;
    var itemIndex = _findItem(listIndex + 1);
    var itemLine = this[itemIndex]; // Invariant.
    var buffer = StringBuffer(itemLine!.trimRight());
    var insertSpace = true;
    var inCode = false;
    var inMinipage = false;

    for (var gatherIndex = itemIndex + 1; gatherIndex < length; ++gatherIndex) {
      var gatherLine = this[gatherIndex]; // Invariant.
      if (gatherLine == null) continue;
      if (gatherLine.startsMinipage) inMinipage = true;
      if (inMinipage) {
        if (gatherLine.endsMinipage) {
          inMinipage = false;
          // Finalize current item, set up new.
          this[itemIndex] = buffer.toString();
          itemIndex = _findText(gatherIndex + 1);
          itemLine = this[itemIndex]; // Restore the `itemLine` invariant.
          if (itemLine!.endsList) {
            // No extra lines, at the end of the outermost itemized list: Done.
            return itemIndex + 1;
          } else if (itemLine.trimLeft().isItem) {
            // No extra lines, starting a new item.
            buffer = StringBuffer(itemLine);
            gatherIndex = itemIndex;
            continue;
          } else {
            // Some extra text found, gather it.
            buffer = StringBuffer(itemLine); // Not starting with `\item`.
            gatherIndex = itemIndex;
            continue;
          }
        }
        continue;
      }
      if (gatherLine.startsCode) inCode = true;
      if (inCode) {
        if (gatherLine.endsCode) inCode = false;
        continue;
      }
      final trimmedGatherLine = gatherLine.trimLeft();
      if (trimmedGatherLine.startsList) {
        // We do not gather a nested itemized list into the current item.
        // Finalize the current item.
        this[itemIndex] = buffer.toString();
        // Set up the first item of the nested itemized list.
        itemIndex = _findItem(gatherIndex + 1);
        itemLine = this[itemIndex];
        buffer = StringBuffer(itemLine!);
        gatherIndex = itemIndex;
        continue;
      }
      if (gatherLine.endsList) {
        // At the end of the outermost itemized list: Done.
        this[itemIndex] = buffer.toString();
        return gatherIndex;
      }
      final foundItem = trimmedGatherLine.isItem;
      final foundEnd = trimmedGatherLine.endsList;
      if (foundItem || foundEnd) {
        // Current `\item` has ended, transfer the data.
        this[itemIndex] = buffer.toString();
        if (foundItem) {
          // Another `\item` coming, set up.
          buffer = StringBuffer(gatherLine);
          itemIndex = gatherIndex;
          itemLine = this[itemIndex]; // Restore the `itemLine` invariant.
          continue;
        } else {
          // `foundEnd` is true.
          // Gather lines after the nested itemized list, if any. Note
          /// that `itemLine` does not contain `\item`, but it's treated
          /// as if it did contain `\item`.
          itemIndex = _findText(gatherIndex + 1);
          itemLine = this[itemIndex]; // Restore the `itemLine` invariant.
          if (itemLine!.endsList) {
            // No extra lines, at the end of the outermost itemized list: Done.
            return itemIndex + 1;
          } else if (itemLine.trimLeft().isItem) {
            // No extra lines, starting a new item.
            buffer = StringBuffer(itemLine);
            gatherIndex = itemIndex;
            continue;
          } else {
            // Some extra text found, gather it.
            buffer = StringBuffer(itemLine); // Not starting with `\item`.
            gatherIndex = itemIndex;
            continue;
          }
        }
      }
      // `gatherLine` is text belonging to the current `\item`.
      final spacing = insertSpace ? ' ' : '';
      final endsInPercent = gatherLine.endsWith('%');
      final String addLine;
      if (endsInPercent) {
        addLine = gatherLine.substring(0, gatherLine.length - 1).trimLeft();
        insertSpace = false;
      } else {
        addLine = gatherLine.trimLeft();
        insertSpace = true;
      }
      if (addLine.isNotEmpty) buffer.write('$spacing$addLine');
      this[gatherIndex] = null;
    }
    endOfTextFailure();
  }

  /// Gather the text in lines `paragraphIndex + 1` into
  /// a single line and store it at [paragraphIndex].
  /// The line at [paragraphIndex] is expected to contain
  /// `\LMHash{}` which will be removed.
  int _gatherParagraph(final int paragraphIndex) =>
      _gatherParagraphBase(paragraphIndex, StringBuffer(''));

  int _gatherParagraphBase(final int paragraphIndex, StringBuffer buffer) {
    final length = this.length;
    var insertSpace = false;
    for (
      var gatherIndex = paragraphIndex + 1;
      gatherIndex < length;
      ++gatherIndex
    ) {
      var gatherLine = this[gatherIndex]; // Invariant.
      if (gatherLine == null) continue;
      if (gatherLine.isEmpty || gatherLine.startsWith(r"\EndCase")) {
        // End of paragraph, finalize.
        this[paragraphIndex] = buffer.toString();
        return gatherIndex;
      }
      final spacing = insertSpace ? ' ' : '';
      final endsInPercent = gatherLine.endsWith('%');
      final String addLine;
      if (endsInPercent) {
        addLine = gatherLine.substring(0, gatherLine.length - 1).trimLeft();
        insertSpace = false;
      } else {
        addLine = gatherLine.trimLeft();
        insertSpace = true;
      }
      if (addLine.isNotEmpty) buffer.write('$spacing$addLine');
      this[gatherIndex] = null;
    }
    endOfTextFailure();
  }

  static int _indentation(String text) {
    final length = text.length;
    for (int i = 0; i < length; ++i) {
      if (!_isWhitespace(text, i)) {
        return i;
      }
    }
    return length;
  }

  static bool _isWhitespace(String text, int index) {
    int codeUnit = text.codeUnitAt(index);
    return codeUnit == 0x09 || // Tab
        codeUnit == 0x0A || // Line Feed
        codeUnit == 0x0B || // Vertical Tab
        codeUnit == 0x0C || // Form Feed
        codeUnit == 0x0D || // Carriage Return
        codeUnit == 0x20 || // Space
        codeUnit == 0xA0 || // No-Break Space
        codeUnit == 0x1680 || // Ogham Space Mark
        (codeUnit >= 0x2000 && codeUnit <= 0x200A) || // En Space to Hair Space
        codeUnit == 0x202F || // Narrow No-Break Space
        codeUnit == 0x205F || // Medium Mathematical Space
        codeUnit == 0x3000 || // Ideographic Space
        codeUnit == 0xFEFF; // Zero Width No-Break Space (BOM)
  }

  static String _lineStart(String line) {
    final indentation = _indentation(line);
    return "${' ' * indentation}}";
  }
}
