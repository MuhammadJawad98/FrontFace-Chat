import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Thin Google Places / Geocoding helpers for the location picker.
///
/// Uses the same Maps API key as the map. Host projects must enable
/// **Places API** (Autocomplete + Details) and **Geocoding API** on that key.
class FrontFacePlacesClient {
  FrontFacePlacesClient(this.apiKey);

  final String apiKey;

  Future<List<FrontFacePlacePrediction>> autocomplete(String input) async {
    final query = input.trim();
    if (query.length < 2) return const [];

    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/autocomplete/json',
      {
        'input': query,
        'key': apiKey,
        'language': 'en',
      },
    );
    final response = await http.get(uri);
    if (response.statusCode != 200) return const [];

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['status']?.toString() != 'OK' &&
        data['status']?.toString() != 'ZERO_RESULTS') {
      return const [];
    }

    final predictions = data['predictions'] as List<dynamic>? ?? const [];
    return predictions
        .whereType<Map>()
        .map((e) => FrontFacePlacePrediction.fromJson(Map<String, dynamic>.from(e)))
        .where((p) => p.placeId.isNotEmpty)
        .toList();
  }

  Future<FrontFacePlaceDetails?> details(String placeId) async {
    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/details/json',
      {
        'place_id': placeId,
        'fields': 'geometry,name,formatted_address',
        'key': apiKey,
      },
    );
    final response = await http.get(uri);
    if (response.statusCode != 200) return null;

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['status']?.toString() != 'OK') return null;
    final result = data['result'];
    if (result is! Map) return null;
    return FrontFacePlaceDetails.fromJson(Map<String, dynamic>.from(result));
  }

  Future<String?> reverseGeocode(double lat, double lng) async {
    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/geocode/json',
      {
        'latlng': '$lat,$lng',
        'key': apiKey,
      },
    );
    final response = await http.get(uri);
    if (response.statusCode != 200) return null;

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['status']?.toString() != 'OK') return null;
    final results = data['results'] as List<dynamic>? ?? const [];
    if (results.isEmpty) return null;
    final first = results.first;
    if (first is! Map) return null;
    return first['formatted_address']?.toString();
  }
}

class FrontFacePlacePrediction {
  final String placeId;
  final String primaryText;
  final String secondaryText;

  const FrontFacePlacePrediction({
    required this.placeId,
    required this.primaryText,
    required this.secondaryText,
  });

  factory FrontFacePlacePrediction.fromJson(Map<String, dynamic> json) {
    final structured = json['structured_formatting'];
    String primary = json['description']?.toString() ?? '';
    String secondary = '';
    if (structured is Map) {
      primary = structured['main_text']?.toString() ?? primary;
      secondary = structured['secondary_text']?.toString() ?? '';
    }
    return FrontFacePlacePrediction(
      placeId: json['place_id']?.toString() ?? '',
      primaryText: primary,
      secondaryText: secondary,
    );
  }
}

class FrontFacePlaceDetails {
  final double latitude;
  final double longitude;
  final String? name;
  final String? formattedAddress;

  const FrontFacePlaceDetails({
    required this.latitude,
    required this.longitude,
    this.name,
    this.formattedAddress,
  });

  String get label {
    final n = name?.trim();
    if (n != null && n.isNotEmpty) return n;
    final a = formattedAddress?.trim();
    if (a != null && a.isNotEmpty) return a;
    return '$latitude, $longitude';
  }

  factory FrontFacePlaceDetails.fromJson(Map<String, dynamic> json) {
    final geometry = json['geometry'];
    final location = geometry is Map ? geometry['location'] : null;
    final lat = (location is Map ? location['lat'] as num? : null)?.toDouble() ?? 0;
    final lng = (location is Map ? location['lng'] as num? : null)?.toDouble() ?? 0;
    return FrontFacePlaceDetails(
      latitude: lat,
      longitude: lng,
      name: json['name']?.toString(),
      formattedAddress: json['formatted_address']?.toString(),
    );
  }
}

/// Debounces place autocomplete requests while typing.
class FrontFacePlacesSearchController {
  FrontFacePlacesSearchController(this._client);

  final FrontFacePlacesClient _client;
  Timer? _timer;
  int _generation = 0;

  void dispose() {
    _timer?.cancel();
  }

  void search(
    String input, {
    required void Function(List<FrontFacePlacePrediction> results) onResult,
  }) {
    _timer?.cancel();
    final gen = ++_generation;
    final query = input.trim();
    if (query.length < 2) {
      onResult(const []);
      return;
    }
    _timer = Timer(const Duration(milliseconds: 320), () async {
      final results = await _client.autocomplete(query);
      if (gen != _generation) return;
      onResult(results);
    });
  }
}
