// Offline structural checker for FHIR R4 resources, driven ONLY by the
// hand-written fixtures in test/fixtures/fhir_r4/. It is deliberately
// small: it checks what the R4 definitions say about the four resource
// types Guardian exports (element names, required elements, required
// bindings, primitive formats, extension shape, references inside a
// Bundle). It is NOT the official HL7 validator and is not a substitute
// for one; no server is contacted.

import 'dart:convert';
import 'dart:io';

class Fhir4Definitions {
  Fhir4Definitions._(this._json);

  factory Fhir4Definitions.load() => Fhir4Definitions._(
      jsonDecode(File('test/fixtures/fhir_r4/r4_definitions.json')
          .readAsStringSync()) as Map<String, dynamic>);

  final Map<String, dynamic> _json;

  Map<String, dynamic> get _resources =>
      _json['resources'] as Map<String, dynamic>;
  Map<String, dynamic> get _bindings =>
      _json['requiredBindings'] as Map<String, dynamic>;
  Map<String, dynamic> get _prims => _json['primitives'] as Map<String, dynamic>;

  RegExp _re(String name) => RegExp(_prims[name] as String);

  /// Problems found in one resource (empty = structurally valid).
  /// [bundleUrls] enables urn:uuid reference resolution inside a Bundle.
  List<String> check(Map<String, dynamic> r, {Set<String>? bundleUrls}) {
    final problems = <String>[];
    final type = r['resourceType'];
    final def = _resources[type];
    if (def == null) {
      return ['unsupported resourceType $type'];
    }
    final allowed = {'resourceType', ...(def['elements'] as List).cast<String>()};
    for (final k in r.keys) {
      if (!allowed.contains(k)) problems.add('$type: unknown element $k');
    }
    for (final k in (def['required'] as List).cast<String>()) {
      if (!r.containsKey(k)) problems.add('$type: missing required element $k');
    }
    void prim(String path, Object? v, String kind) {
      if (v is! String || !_re(kind).hasMatch(v)) {
        problems.add('$type.$path "$v" is not a valid $kind');
      }
    }

    void binding(String path, Object? v) {
      final allowedVals = (_bindings[path] as List?)?.cast<String>();
      if (allowedVals != null && !allowedVals.contains(v)) {
        problems.add('$path "$v" is not in the required value set');
      }
    }

    if (r.containsKey('id')) prim('id', r['id'], 'id');
    _checkMeta(type as String, r['meta'], problems);
    _checkNarrative(type, r['text'], problems, binding);
    _checkExtensions(type, 'extension', r['extension'], problems);

    switch (type) {
      case 'Observation':
        binding('Observation.status', r['status']);
        final code = r['code'];
        if (code is! Map || (code['coding'] == null && code['text'] == null)) {
          problems.add('Observation.code needs coding or text');
        }
        if (r.containsKey('effectiveDateTime')) {
          prim('effectiveDateTime', r['effectiveDateTime'], 'dateTime');
        }
        final q = r['valueQuantity'];
        if (q != null) {
          if (q is! Map || q['value'] is! num) {
            problems.add('Observation.valueQuantity.value must be a number');
          } else if (q['system'] != null && q['code'] == null) {
            problems.add('Observation.valueQuantity: system without code');
          }
        }
        _checkCodings(type, r['code'], problems);
        for (final c in (r['category'] as List? ?? const [])) {
          _checkCodings(type, c, problems);
        }
        _checkRef(type, 'subject', r['subject'], problems, bundleUrls);
      case 'Provenance':
        prim('recorded', r['recorded'], 'instant');
        final targets = r['target'];
        if (targets is! List || targets.isEmpty) {
          problems.add('Provenance.target must have at least one reference');
        } else {
          for (final t in targets) {
            _checkRef(type, 'target', t, problems, bundleUrls);
          }
        }
        final agents = r['agent'];
        if (agents is! List || agents.isEmpty) {
          problems.add('Provenance.agent must have at least one entry');
        } else {
          for (var i = 0; i < agents.length; i++) {
            if (agents[i] is! Map || !(agents[i] as Map).containsKey('who')) {
              problems.add('Provenance: agent[$i] missing required element who');
            }
          }
        }
        for (final e in (r['entity'] as List? ?? const [])) {
          if (e is! Map || !e.containsKey('role') || !e.containsKey('what')) {
            problems.add('Provenance.entity needs role and what');
          } else {
            binding('Provenance.entity.role', e['role']);
          }
        }
      case 'Bundle':
        binding('Bundle.type', r['type']);
        if (r.containsKey('timestamp')) prim('timestamp', r['timestamp'], 'instant');
      case 'Patient':
        for (final n in (r['name'] as List? ?? const [])) {
          if (n is Map && n.containsKey('use')) binding('Patient.name.use', n['use']);
        }
    }
    return problems;
  }

  /// Check a whole Bundle: the Bundle itself, every entry resource, unique
  /// fullUrls, and that every urn:uuid reference resolves to an entry.
  List<String> checkBundle(Map<String, dynamic> bundle) {
    final urls = <String>[];
    final entries = (bundle['entry'] as List?) ?? const [];
    for (final e in entries) {
      final url = (e as Map)['fullUrl'];
      if (url is! String || !_re('urnUuid').hasMatch(url)) {
        urls.add('<bad fullUrl $url>');
      } else {
        urls.add(url);
      }
    }
    final problems = <String>[];
    if (urls.toSet().length != urls.length) problems.add('duplicate fullUrl');
    for (final u in urls) {
      if (u.startsWith('<bad')) problems.add('Bundle.entry.$u');
    }
    problems.addAll(check(bundle));
    for (var i = 0; i < entries.length; i++) {
      final res = (entries[i] as Map)['resource'];
      if (res is! Map<String, dynamic>) {
        problems.add('Bundle.entry[$i] has no resource');
        continue;
      }
      problems.addAll(
          check(res, bundleUrls: urls.toSet()).map((p) => 'entry[$i] $p'));
    }
    return problems;
  }

  void _checkMeta(String type, Object? meta, List<String> problems) {
    if (meta == null) return;
    if (meta is! Map) {
      problems.add('$type.meta must be an object');
      return;
    }
    for (final k in ['security', 'tag']) {
      for (final c in (meta[k] as List? ?? const [])) {
        if (c is! Map || c['system'] is! String || c['code'] is! String) {
          problems.add('$type.meta.$k coding needs system and code');
        }
      }
    }
    _checkExtensions(type, 'meta.extension', meta['extension'], problems);
  }

  void _checkNarrative(String type, Object? text, List<String> problems,
      void Function(String, Object?) binding) {
    if (text == null) return;
    if (text is! Map || text['status'] == null || text['div'] == null) {
      problems.add('$type.text needs status and div');
      return;
    }
    binding('Narrative.status', text['status']);
    final div = text['div'] as String;
    if (!div.startsWith('<div xmlns="http://www.w3.org/1999/xhtml">') ||
        !div.endsWith('</div>')) {
      problems.add('$type.text.div must be an xhtml div');
    }
  }

  void _checkCodings(String type, Object? cc, List<String> problems) {
    if (cc is! Map) return;
    for (final c in (cc['coding'] as List? ?? const [])) {
      if (c is! Map || c['system'] is! String || c['code'] is! String) {
        problems.add('$type: coding needs system and code');
      }
    }
  }

  void _checkRef(String type, String path, Object? ref, List<String> problems,
      Set<String>? bundleUrls) {
    if (ref == null) return;
    if (ref is! Map) {
      problems.add('$type.$path must be a Reference');
      return;
    }
    final r = ref['reference'];
    if (r is String && r.startsWith('urn:uuid:') && bundleUrls != null) {
      if (!bundleUrls.contains(r)) {
        problems.add('$type.$path reference $r does not resolve in the Bundle');
      }
    }
  }

  void _checkExtensions(
      String type, String path, Object? ext, List<String> problems) {
    if (ext == null) return;
    if (ext is! List) {
      problems.add('$type.$path must be an array');
      return;
    }
    final types = (_json['extensionValueTypes'] as Map).cast<String, String>();
    for (var i = 0; i < ext.length; i++) {
      final e = ext[i];
      final here = '$type.$path[$i]';
      if (e is! Map || e['url'] is! String || !_re('uri').hasMatch(e['url'] as String)) {
        problems.add('$here has no url');
        continue;
      }
      final valueKeys = e.keys.where((k) => (k as String).startsWith('value')).toList();
      final hasNested = e.containsKey('extension');
      if (valueKeys.isEmpty && !hasNested) {
        problems.add('$here has neither a value nor nested extensions');
      }
      if (valueKeys.isNotEmpty && hasNested) {
        problems.add('$here has both a value and nested extensions');
      }
      if (valueKeys.length > 1) problems.add('$here has more than one value[x]');
      for (final k in valueKeys) {
        final v = e[k];
        switch (types[k]) {
          case 'string':
            if (v is! String) problems.add('$here $k must be a string');
          case 'code':
            if (v is! String || !_re('code').hasMatch(v)) {
              problems.add('$here $k must be a code');
            }
          case 'boolean':
            if (v is! bool) problems.add('$here $k must be a boolean');
          case 'integer':
            if (v is! int) problems.add('$here $k must be an integer');
          case 'unsignedInt':
            if (v is! int || v < 0) {
              problems.add('$here $k must be a non-negative integer');
            }
          case 'dateTime':
            if (v is! String || !_re('dateTime').hasMatch(v)) {
              problems.add('$here $k must be a dateTime');
            }
          default:
            problems.add('$here uses unsupported $k');
        }
      }
      if (hasNested) _checkExtensions(type, '$path[$i].extension', e['extension'], problems);
    }
  }
}

/// Hand-typed expectations for codings (test/fixtures/fhir_r4/r4_codings.json).
Map<String, dynamic> loadCodings() => jsonDecode(
        File('test/fixtures/fhir_r4/r4_codings.json').readAsStringSync())
    as Map<String, dynamic>;
