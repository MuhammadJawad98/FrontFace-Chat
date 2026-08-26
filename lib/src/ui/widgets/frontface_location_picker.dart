import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../config/frontface_attachments_config.dart';
import '../../config/frontface_chat_strings.dart';
import '../../config/frontface_chat_theme.dart';
import '../../services/frontface_permission_gate.dart';
import '../../services/frontface_places_client.dart';

/// Full-screen map picker with place search. Returns a location payload or null.
class FrontFaceLocationPickerScreen extends StatefulWidget {
  final FrontFaceChatTheme theme;
  final FrontFaceChatStrings strings;
  final String googleMapsApiKey;

  const FrontFaceLocationPickerScreen({
    super.key,
    required this.theme,
    required this.strings,
    required this.googleMapsApiKey,
  });

  static Future<FrontFaceAttachmentPayload?> open(
    BuildContext context, {
    required FrontFaceChatTheme theme,
    required FrontFaceChatStrings strings,
    required String googleMapsApiKey,
  }) {
    return Navigator.of(context).push<FrontFaceAttachmentPayload>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => FrontFaceLocationPickerScreen(
          theme: theme,
          strings: strings,
          googleMapsApiKey: googleMapsApiKey,
        ),
      ),
    );
  }

  @override
  State<FrontFaceLocationPickerScreen> createState() =>
      _FrontFaceLocationPickerScreenState();
}

class _FrontFaceLocationPickerScreenState
    extends State<FrontFaceLocationPickerScreen> {
  static const _fallback = LatLng(25.2048, 55.2708); // Dubai

  late final FrontFacePlacesClient _places;
  late final FrontFacePlacesSearchController _search;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  GoogleMapController? _mapController;
  LatLng _pin = _fallback;
  double? _accuracyMeters;
  String _label = '';
  bool _loading = true;
  bool _resolvingLabel = false;
  String? _error;
  List<FrontFacePlacePrediction> _suggestions = const [];
  bool _showSuggestions = false;

  FrontFaceChatTheme get _theme => widget.theme;
  FrontFaceChatStrings get _strings => widget.strings;

  @override
  void initState() {
    super.initState();
    _places = FrontFacePlacesClient(widget.googleMapsApiKey);
    _search = FrontFacePlacesSearchController(_places);
    _label = _strings.sharedLocation;
    _bootstrap();
  }

  @override
  void dispose() {
    _search.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final gate = const FrontFacePermissionGate();
    final ok = await gate.ensureLocation(
      context: context,
      strings: _strings,
    );
    if (!mounted) return;

    if (!ok) {
      setState(() {
        _loading = false;
        _error = _strings.locationPermissionDenied;
      });
      return;
    }

    await _goToCurrentLocation(showError: true);
  }

  Future<void> _goToCurrentLocation({bool showError = false}) async {
    try {
      setState(() {
        _loading = true;
        if (showError) _error = null;
        _showSuggestions = false;
      });
      _searchFocus.unfocus();
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      if (!mounted) return;
      await _setPin(
        LatLng(pos.latitude, pos.longitude),
        accuracy: pos.accuracy,
        animate: true,
      );
      setState(() {
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (showError) _error = _strings.locationUnavailable;
      });
    }
  }

  Future<void> _setPin(
    LatLng next, {
    double? accuracy,
    String? label,
    bool animate = true,
    bool reverseGeocode = true,
  }) async {
    setState(() {
      _pin = next;
      _accuracyMeters = accuracy;
      if (label != null && label.trim().isNotEmpty) {
        _label = label.trim();
      }
    });
    if (animate) {
      await _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(next, 16),
      );
    }
    if (reverseGeocode && (label == null || label.trim().isEmpty)) {
      await _refreshLabel(next);
    }
  }

  Future<void> _refreshLabel(LatLng pin) async {
    setState(() => _resolvingLabel = true);
    try {
      final address = await _places.reverseGeocode(pin.latitude, pin.longitude);
      if (!mounted) return;
      if (address != null && address.trim().isNotEmpty) {
        setState(() => _label = address.trim());
      } else {
        setState(() => _label = _strings.sharedLocation);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _label = _strings.sharedLocation);
    } finally {
      if (mounted) setState(() => _resolvingLabel = false);
    }
  }

  void _onSearchChanged(String value) {
    _search.search(value, onResult: (results) {
      if (!mounted) return;
      setState(() {
        _suggestions = results;
        _showSuggestions = results.isNotEmpty && _searchFocus.hasFocus;
      });
    });
  }

  Future<void> _selectPrediction(FrontFacePlacePrediction prediction) async {
    _searchFocus.unfocus();
    setState(() {
      _showSuggestions = false;
      _loading = true;
      _searchController.text = prediction.primaryText;
    });
    try {
      final details = await _places.details(prediction.placeId);
      if (!mounted) return;
      if (details == null) {
        setState(() => _loading = false);
        return;
      }
      await _setPin(
        LatLng(details.latitude, details.longitude),
        label: details.label,
        reverseGeocode: false,
        animate: true,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _confirm() {
    HapticFeedback.selectionClick();
    Navigator.pop(
      context,
      FrontFaceAttachmentPayload(
        kind: FrontFaceAttachmentKind.location,
        latitude: _pin.latitude,
        longitude: _pin.longitude,
        accuracyMeters: _accuracyMeters,
        label: _label.isNotEmpty ? _label : _strings.sharedLocation,
        capturedAt: DateTime.now().toUtc(),
        url: 'https://maps.google.com/?q=${_pin.latitude},${_pin.longitude}',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final topInset = media.padding.top;
    final bottomInset = media.padding.bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: _theme.backgroundColor,
        // Map fills remaining space above the confirm sheet so the
        // my-location control can never sit under it.
        body: Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  GoogleMap(
                    initialCameraPosition:
                        CameraPosition(target: _pin, zoom: 14),
                    myLocationEnabled: true,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    compassEnabled: false,
                    mapToolbarEnabled: false,
                    padding: EdgeInsets.only(top: topInset + 72),
                    onMapCreated: (c) {
                      _mapController = c;
                      if (!_loading) {
                        c.animateCamera(
                          CameraUpdate.newLatLngZoom(_pin, 16),
                        );
                      }
                    },
                    onTap: (latLng) async {
                      _searchFocus.unfocus();
                      setState(() => _showSuggestions = false);
                      await _setPin(latLng, accuracy: null, animate: false);
                    },
                    onCameraMove: (pos) {
                      // Keep pin in sync while user pans with marker drag only.
                    },
                    markers: {
                      Marker(
                        markerId: const MarkerId('selected'),
                        position: _pin,
                        draggable: true,
                        onDragEnd: (p) =>
                            _setPin(p, accuracy: null, animate: false),
                      ),
                    },
                  ),

                  // Top: close + search (safe area).
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                _RoundIconButton(
                                  icon: Icons.close_rounded,
                                  onTap: () => Navigator.pop(context),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _SearchField(
                                    controller: _searchController,
                                    focusNode: _searchFocus,
                                    hint: _strings.searchLocationHint,
                                    onChanged: _onSearchChanged,
                                    onClear: () {
                                      _searchController.clear();
                                      setState(() {
                                        _suggestions = const [];
                                        _showSuggestions = false;
                                      });
                                    },
                                    onFocus: (focused) {
                                      setState(() {
                                        _showSuggestions =
                                            focused && _suggestions.isNotEmpty;
                                      });
                                    },
                                  ),
                                ),
                              ],
                            ),
                            if (_showSuggestions) ...[
                              const SizedBox(height: 8),
                              _SuggestionsCard(
                                suggestions: _suggestions,
                                onSelect: _selectPrediction,
                              ),
                            ],
                            if (_error != null &&
                                !_loading &&
                                !_showSuggestions) ...[
                              const SizedBox(height: 8),
                              _ErrorBanner(message: _error!),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),

                  if (_loading)
                    const ColoredBox(
                      color: Color(0x33FFFFFF),
                      child: Center(child: CircularProgressIndicator()),
                    ),

                  // My location — anchored to the map area, above the sheet.
                  Positioned(
                    right: 16,
                    bottom: 12,
                    child: _RoundIconButton(
                      icon: Icons.my_location_rounded,
                      color: _theme.primaryColor,
                      onTap: _loading ? null : () => _goToCurrentLocation(),
                      tooltip: _strings.useCurrentLocation,
                    ),
                  ),
                ],
              ),
            ),
            _BottomConfirmPanel(
              theme: _theme,
              strings: _strings,
              label: _label,
              latitude: _pin.latitude,
              longitude: _pin.longitude,
              resolving: _resolvingLabel,
              enabled: !_loading,
              bottomInset: bottomInset,
              onSend: _confirm,
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color? color;
  final String? tooltip;

  const _RoundIconButton({
    required this.icon,
    this.onTap,
    this.color,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final child = Material(
      color: Colors.white,
      elevation: 3,
      shadowColor: Colors.black26,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: color ?? const Color(0xFF111827), size: 22),
        ),
      ),
    );
    if (tooltip == null) return child;
    return Tooltip(message: tooltip!, child: child);
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final ValueChanged<bool> onFocus;

  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.onChanged,
    required this.onClear,
    required this.onFocus,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: onFocus,
      child: Material(
        color: Colors.white,
        elevation: 3,
        shadowColor: Colors.black26,
        borderRadius: BorderRadius.circular(16),
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: Color(0xFF111827),
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: const Color(0xFF6B7280).withValues(alpha: 0.9),
              fontWeight: FontWeight.w400,
            ),
            prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF6B7280)),
            suffixIcon: ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (_, value, __) {
                if (value.text.isEmpty) return const SizedBox.shrink();
                return IconButton(
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded, size: 20),
                );
              },
            ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
    );
  }
}

class _SuggestionsCard extends StatelessWidget {
  final List<FrontFacePlacePrediction> suggestions;
  final ValueChanged<FrontFacePlacePrediction> onSelect;

  const _SuggestionsCard({
    required this.suggestions,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 4,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 260),
        child: ListView.separated(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          itemCount: suggestions.length.clamp(0, 6),
          separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
          itemBuilder: (context, index) {
            final item = suggestions[index];
            return ListTile(
              dense: true,
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.place_rounded,
                  color: Color(0xFF2563EB),
                  size: 20,
                ),
              ),
              title: Text(
                item.primaryText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              subtitle: item.secondaryText.isEmpty
                  ? null
                  : Text(
                      item.secondaryText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
              onTap: () => onSelect(item),
            );
          },
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFEF2F2),
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded, color: Color(0xFFDC2626)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Color(0xFF991B1B),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomConfirmPanel extends StatelessWidget {
  final FrontFaceChatTheme theme;
  final FrontFaceChatStrings strings;
  final String label;
  final double latitude;
  final double longitude;
  final bool resolving;
  final bool enabled;
  final double bottomInset;
  final VoidCallback onSend;

  const _BottomConfirmPanel({
    required this.theme,
    required this.strings,
    required this.label,
    required this.latitude,
    required this.longitude,
    required this.resolving,
    required this.enabled,
    required this.bottomInset,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 28,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.location_on_rounded,
                    color: theme.primaryColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        strings.shareLocation,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: theme.subtitleColor,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      if (resolving)
                        const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Text(
                          label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                            color: Color(0xFF111827),
                          ),
                        ),
                      const SizedBox(height: 2),
                      Text(
                        '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.subtitleColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: enabled ? onSend : null,
              style: FilledButton.styleFrom(
                backgroundColor: theme.primaryColor,
                foregroundColor: theme.onPrimaryColor,
                disabledBackgroundColor:
                    theme.primaryColor.withValues(alpha: 0.35),
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.send_rounded, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    strings.sendLocation,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
