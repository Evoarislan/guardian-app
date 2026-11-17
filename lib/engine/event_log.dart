// Guardian escalation engine (Dart port): hash-chained event log.
// Port of engine/eventlog.js (the verified Node reference).
//
// Every state transition and notable event is appended here. Each entry
// carries a hash of its own content chained to the previous entry's
// hash, so later edits, deletions, or reordering are detectable by
// verify().
//
// Keyed mode: if a key is supplied, entries are chained with
// HMAC-SHA256 under that key instead of plain SHA-256.
//
// HONEST LIMIT (same as the Node reference): tamper-EVIDENCE holds
// against an anchor. anchor() returns {count, headHash}; if that pair is
// stored OUTSIDE this log and later passed to verify(anchor), edits,
// truncation, and wholesale replacement are detected. WITHOUT an
// externally stored anchor or the key, an attacker who can rewrite the
// whole log can also recompute a self-consistent plain chain, and that
// full rewrite is UNDETECTABLE by verify() alone.
//
// Hash compatibility: the hashed payload is the JavaScript
// JSON.stringify of {seq, ts, type, data, prevHash} (key order as
// written, no whitespace, integral numbers without ".0", null kept).
// [jsJsonEncode] reproduces that byte for byte, so a chain built by
// either implementation verifies in the other.

import 'dart:convert';

import 'package:crypto/crypto.dart';

const String genesisHash = 'guardian-genesis';

/// JSON encoder matching JavaScript's JSON.stringify (compact form) for
/// the value types the log carries: Map, List, String, num, bool, null,
/// or any object exposing toJson().
String jsJsonEncode(Object? value) {
  final out = StringBuffer();
  _encode(value, out);
  return out.toString();
}

void _encode(Object? v, StringBuffer out) {
  if (v == null) {
    out.write('null');
  } else if (v is bool) {
    out.write(v ? 'true' : 'false');
  } else if (v is int) {
    out.write(v.toString());
  } else if (v is double) {
    if (v.isNaN || v.isInfinite) {
      out.write('null'); // JS: non-finite numbers serialize as null
    } else if (v == v.truncateToDouble() && v.abs() < 1e21) {
      out.write(v.toInt().toString()); // 3.0 -> "3", -0.0 -> "0"
    } else {
      out.write(v.toString());
    }
  } else if (v is String) {
    _encodeString(v, out);
  } else if (v is Map) {
    out.write('{');
    var first = true;
    v.forEach((k, val) {
      if (!first) out.write(',');
      first = false;
      _encodeString(k.toString(), out);
      out.write(':');
      _encode(val, out);
    });
    out.write('}');
  } else if (v is Iterable) {
    out.write('[');
    var first = true;
    for (final item in v) {
      if (!first) out.write(',');
      first = false;
      _encode(item, out);
    }
    out.write(']');
  } else {
    // ignore: avoid_dynamic_calls
    _encode((v as dynamic).toJson(), out);
  }
}

void _encodeString(String s, StringBuffer out) {
  out.write('"');
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    switch (c) {
      case 0x22:
        out.write(r'\"');
      case 0x5c:
        out.write(r'\\');
      case 0x08:
        out.write(r'\b');
      case 0x0c:
        out.write(r'\f');
      case 0x0a:
        out.write(r'\n');
      case 0x0d:
        out.write(r'\r');
      case 0x09:
        out.write(r'\t');
      default:
        if (c < 0x20) {
          out.write('\\u${c.toRadixString(16).padLeft(4, '0')}');
        } else {
          out.writeCharCode(c);
        }
    }
  }
  out.write('"');
}

String _hashEntry(
  String? key,
  int seq,
  int ts,
  String type,
  Map<String, dynamic> data,
  String prevHash,
) {
  final payload = utf8.encode(jsJsonEncode({
    'seq': seq,
    'ts': ts,
    'type': type,
    'data': data,
    'prevHash': prevHash,
  }));
  return key != null
      ? Hmac(sha256, utf8.encode(key)).convert(payload).toString()
      : sha256.convert(payload).toString();
}

class LogEntry {
  LogEntry({
    required this.seq,
    required this.ts,
    required this.type,
    required this.data,
    required this.prevHash,
    required this.hash,
  });

  int seq;
  int ts;
  String type;
  Map<String, dynamic> data;
  String prevHash;
  String hash;

  factory LogEntry.fromJson(Map<String, dynamic> json) => LogEntry(
        seq: json['seq'] as int,
        ts: json['ts'] as int,
        type: json['type'] as String,
        data: Map<String, dynamic>.from(json['data'] as Map),
        prevHash: json['prevHash'] as String,
        hash: json['hash'] as String,
      );

  LogEntry copy() => LogEntry(
        seq: seq,
        ts: ts,
        type: type,
        data: data,
        prevHash: prevHash,
        hash: hash,
      );

  /// Key order matches the Node export: seq, ts, type, data, prevHash, hash.
  Map<String, dynamic> toJson() => {
        'seq': seq,
        'ts': ts,
        'type': type,
        'data': data,
        'prevHash': prevHash,
        'hash': hash,
      };
}

class Anchor {
  const Anchor({required this.count, required this.headHash});
  final int count;
  final String headHash;

  Map<String, dynamic> toJson() => {'count': count, 'headHash': headHash};
}

class VerifyResult {
  const VerifyResult({required this.ok, this.failedAt});
  final bool ok;

  /// seq of the first entry that does not check out; null when ok.
  final int? failedAt;

  Map<String, dynamic> toJson() => {'ok': ok, 'failedAt': failedAt};

  @override
  String toString() => jsJsonEncode(this);
}

class EventLog {
  /// [now] is the clock (defaults to wall clock). [key] is the optional
  /// HMAC key. Unlike the Node reference, the key is NOT read from the
  /// process environment implicitly (see SESSION-2-RESULT.md).
  EventLog([int Function()? now, String? key])
      : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch),
        _key = key;

  final int Function() _now;
  final String? _key;
  final List<LogEntry> entries = [];

  /// True when this log chains entries with HMAC-SHA256 under a key.
  bool get keyed => _key != null;

  LogEntry append(String type, [Map<String, dynamic> data = const {}]) {
    final seq = entries.length;
    final ts = _now();
    final prevHash = seq == 0 ? genesisHash : entries[seq - 1].hash;
    final stored = Map<String, dynamic>.of(data);
    final hash = _hashEntry(_key, seq, ts, type, stored, prevHash);
    final entry = LogEntry(
      seq: seq,
      ts: ts,
      type: type,
      data: stored,
      prevHash: prevHash,
      hash: hash,
    );
    entries.add(entry);
    return entry;
  }

  /// Compact external reference to the current chain head. Store it
  /// OUTSIDE this log; verify(anchor) later detects truncation and
  /// replacement.
  Anchor anchor() => Anchor(
        count: entries.length,
        headHash: entries.isEmpty ? genesisHash : entries.last.hash,
      );

  /// Recompute the whole chain; with [anchor], the chain must also still
  /// end at that anchor.
  VerifyResult verify([Anchor? anchor]) {
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      final expectedPrev = i == 0 ? genesisHash : entries[i - 1].hash;
      if (e.seq != i) return VerifyResult(ok: false, failedAt: i);
      if (e.prevHash != expectedPrev) {
        return VerifyResult(ok: false, failedAt: i);
      }
      if (e.hash != _hashEntry(_key, e.seq, e.ts, e.type, e.data, e.prevHash)) {
        return VerifyResult(ok: false, failedAt: i);
      }
    }
    if (anchor != null) {
      if (entries.length != anchor.count) {
        return VerifyResult(
          ok: false,
          failedAt:
              entries.length < anchor.count ? entries.length : anchor.count,
        );
      }
      final head = entries.isEmpty ? genesisHash : entries.last.hash;
      if (head != anchor.headHash) {
        return VerifyResult(
          ok: false,
          failedAt: entries.isEmpty ? 0 : entries.length - 1,
        );
      }
    }
    return const VerifyResult(ok: true);
  }

  /// Same shape as the Node export: {keyed, entries}.
  Map<String, dynamic> toJson() => {
        'keyed': keyed,
        'entries': entries.map((e) => e.toJson()).toList(),
      };

  /// Pretty JSON string form of toJson() (2-space indent, like Node).
  String serialize() => const JsonEncoder.withIndent('  ').convert(toJson());
}
