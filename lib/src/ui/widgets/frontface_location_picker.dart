import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../config/frontface_attachments_config.dart';
import '../../config/frontface_chat_strings.dart';
import '../../config/frontface_chat_theme.dart';
import '../../services/frontface_permission_gate.dart';

/// Full-screen map picker. Returns a [FrontFaceAttachmentPayload] location
/// when the user confirms, or `null` if cancelled.
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

  GoogleMapController? _controller;
  LatLng _pin = _fallback;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final gate = const FrontFacePermissionGate();
    final ok = await gate.ensure(
      context: context,
      permission: Permission.locationWhenInUse,
      strings: widget.strings,
      rationaleTitle: widget.strings.permissionLocationTitle,
      rationaleBody: widget.strings.permissionLocationBody,
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
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        setState(() {
          _loading = false;
          _error = widget.strings.locationServicesDisabled;
        });
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      if (!mounted) return;
      setState(() {
        _pin = LatLng(pos.latitude, pos.longitude);
        _loading = false;
      });
      await _controller?.animateCamera(CameraUpdate.newLatLngZoom(_pin, 16));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = widget.strings.locationUnavailable;
      });
    }
  }

  void _confirm() {
    Navigator.pop(
      context,
      FrontFaceAttachmentPayload(
        kind: FrontFaceAttachmentKind.location,
        latitude: _pin.latitude,
        longitude: _pin.longitude,
        label: widget.strings.sharedLocation,
        url:
            'https://maps.google.com/?q=${_pin.latitude},${_pin.longitude}',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.strings.shareLocation),
        backgroundColor: widget.theme.primaryColor,
        foregroundColor: widget.theme.onPrimaryColor,
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _pin, zoom: 14),
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            onMapCreated: (c) => _controller = c,
            onTap: (latLng) => setState(() => _pin = latLng),
            markers: {
              Marker(
                markerId: const MarkerId('selected'),
                position: _pin,
                draggable: true,
                onDragEnd: (p) => setState(() => _pin = p),
              ),
            },
          ),
          if (_loading)
            const ColoredBox(
              color: Color(0x66FFFFFF),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_error != null && !_loading)
            Positioned(
              left: 16,
              right: 16,
              top: 16,
              child: Material(
                elevation: 2,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_error!, textAlign: TextAlign.center),
                ),
              ),
            ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 0,
            child: SafeArea(
              minimum: const EdgeInsets.only(bottom: 16),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.theme.primaryColor,
                  foregroundColor: widget.theme.onPrimaryColor,
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: _loading ? null : _confirm,
                icon: const Icon(Icons.send_rounded),
                label: Text(widget.strings.sendLocation),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
