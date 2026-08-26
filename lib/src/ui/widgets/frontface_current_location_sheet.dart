import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../../config/frontface_attachments_config.dart';
import '../../config/frontface_chat_strings.dart';
import '../../config/frontface_chat_theme.dart';
import '../../services/frontface_permission_gate.dart';

/// Confirms sharing the device’s current GPS when no Google Maps key is set.
class FrontFaceCurrentLocationSheet {
  FrontFaceCurrentLocationSheet._();

  static Future<FrontFaceAttachmentPayload?> show(
    BuildContext context, {
    required FrontFaceChatTheme theme,
    required FrontFaceChatStrings strings,
  }) {
    return showModalBottomSheet<FrontFaceAttachmentPayload>(
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CurrentLocationBody(theme: theme, strings: strings),
    );
  }
}

class _CurrentLocationBody extends StatefulWidget {
  final FrontFaceChatTheme theme;
  final FrontFaceChatStrings strings;

  const _CurrentLocationBody({
    required this.theme,
    required this.strings,
  });

  @override
  State<_CurrentLocationBody> createState() => _CurrentLocationBodyState();
}

class _CurrentLocationBodyState extends State<_CurrentLocationBody> {
  bool _loading = true;
  String? _error;
  double? _lat;
  double? _lng;
  double? _accuracy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final gate = const FrontFacePermissionGate();
    final ok = await gate.ensureLocation(
      context: context,
      strings: widget.strings,
    );
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _loading = false;
        _error = widget.strings.locationPermissionDenied;
      });
      return;
    }

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      if (!mounted) return;
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
        _accuracy = pos.accuracy;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = widget.strings.locationUnavailable;
      });
    }
  }

  void _confirm() {
    final lat = _lat;
    final lng = _lng;
    if (lat == null || lng == null) return;
    HapticFeedback.selectionClick();
    Navigator.pop(
      context,
      FrontFaceAttachmentPayload(
        kind: FrontFaceAttachmentKind.location,
        latitude: lat,
        longitude: lng,
        accuracyMeters: _accuracy,
        label: widget.strings.sharedLocation,
        capturedAt: DateTime.now().toUtc(),
        url: 'https://maps.google.com/?q=$lat,$lng',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final theme = widget.theme;
    final strings = widget.strings;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 24,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + (bottom > 0 ? 0 : 8)),
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
                const SizedBox(height: 16),
                Text(
                  strings.shareLocation,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 16),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(color: theme.errorColor, height: 1.35),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: theme.primaryColor.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: theme.primaryColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            Icons.my_location_rounded,
                            color: theme.primaryColor,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                strings.useCurrentLocation,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}',
                                style: TextStyle(
                                  color: theme.subtitleColor,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                if (_error != null)
                  FilledButton(
                    onPressed: _load,
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.primaryColor,
                      foregroundColor: theme.onPrimaryColor,
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(strings.retry),
                  )
                else
                  FilledButton.icon(
                    onPressed: _loading ? null : _confirm,
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.primaryColor,
                      foregroundColor: theme.onPrimaryColor,
                      disabledBackgroundColor:
                          theme.primaryColor.withValues(alpha: 0.35),
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.send_rounded),
                    label: Text(strings.sendLocation),
                  ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(strings.permissionNotNow),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
