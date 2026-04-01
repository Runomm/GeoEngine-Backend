import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

void main() {
  runApp(const GeoEngineApp());
}

// ---------------------------------------------------------------------------
// Root widget
// ---------------------------------------------------------------------------

class GeoEngineApp extends StatelessWidget {
  const GeoEngineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GeoEngine OSINT',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00C8FF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const AnalysisScreen(),
    );
  }
}

// ---------------------------------------------------------------------------
// Main screen
// ---------------------------------------------------------------------------

class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  // ── State fields ──────────────────────────────────────────────────────────

  XFile? _selectedImage;  // picked file (works on web + native)
  String _status = 'Ready';
  String _responseText = '';
  bool _isLoading = false;

  /// Final predicted location returned by the backend.
  /// Stays null until a successful parse — map is hidden while null.
  LatLng? _markerPosition;

  /// Optional polygon rings from plonk_spatial_distribution.
  List<List<LatLng>> _polygons = [];

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Base URL for the FastAPI backend.
  ///
  /// • Android emulator → 10.0.2.2 maps to the host loopback (127.0.0.1).
  /// • Web / desktop    → plain localhost works fine.
  String get _baseUrl {
    if (kIsWeb) return 'http://localhost:8000';
    if (Platform.isAndroid) return 'http://10.0.2.2:8000';
    return 'http://localhost:8000'; // iOS simulator / desktop
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _pickImage() async {
    setState(() => _status = 'Selecting image…');

    final picker = ImagePicker();
    XFile? file;

    try {
      file = await picker.pickImage(source: ImageSource.gallery);
    } catch (e) {
      setState(() {
        _status = 'Error: could not open picker — $e';
      });
      return;
    }

    if (file == null) {
      // User cancelled
      setState(() => _status = 'Ready');
      return;
    }

    setState(() {
      _selectedImage = file;
      _status = 'Image selected: ${file!.name}';
      _responseText = ''; // clear previous result
    });
  }

  Future<void> _analyzeImage() async {
    if (_selectedImage == null) {
      _showSnackBar('Please select an image first.');
      return;
    }

    setState(() {
      _isLoading = true;
      _status = 'Processing…';
      _responseText = '';
      _markerPosition = null;
      _polygons = [];
    });

    try {
      final uri = Uri.parse('$_baseUrl/analyze');
      final request = http.MultipartRequest('POST', uri);

      // Attach the image bytes (works on both web and native)
      final bytes = await _selectedImage!.readAsBytes();
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',                        // field name the FastAPI endpoint expects
          bytes,
          filename: _selectedImage!.name,
        ),
      );

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 60),
        onTimeout: () => throw Exception('Request timed out after 60 s'),
      );

      final body = await http.Response.fromStream(streamedResponse);

      if (body.statusCode == 200) {
        // Pretty-print JSON if possible
        String pretty;
        LatLng? marker;
        List<List<LatLng>> polygons = [];

        try {
          final decoded = jsonDecode(body.body) as Map<String, dynamic>;
          pretty = const JsonEncoder.withIndent('  ').convert(decoded);

          // ── Extract final lat/lon ─────────────────────────────────────
          // Expected shape: { "results": { "latitude": ..., "longitude": ... } }
          final results = decoded['results'] as Map<String, dynamic>?;
          if (results != null) {
            final rawLat = results['latitude'];
            final rawLon = results['longitude'];
            final lat = (rawLat as num?)?.toDouble();
            final lon = (rawLon as num?)?.toDouble();
            if (lat != null && lon != null && !(lat == 0.0 && lon == 0.0)) {
              marker = LatLng(lat, lon);
            }
          }

          // ── Extract plonk_spatial_distribution polygons (optional) ────
          // Expected: { "results": { "plonk_spatial_distribution": [ [[lon,lat],...], ... ] } }
          final rawPolys = results?['plonk_spatial_distribution'];
          if (rawPolys is List) {
            for (final ring in rawPolys) {
              if (ring is List) {
                final points = <LatLng>[];
                for (final pt in ring) {
                  if (pt is List && pt.length >= 2) {
                    // GeoJSON order: [longitude, latitude]
                    final lon = (pt[0] as num).toDouble();
                    final lat = (pt[1] as num).toDouble();
                    points.add(LatLng(lat, lon));
                  }
                }
                if (points.isNotEmpty) polygons.add(points);
              }
            }
          }
        } catch (_) {
          pretty = body.body; // not JSON — show raw
        }

        setState(() {
          _status = 'Done ✓  (HTTP ${body.statusCode})';
          _responseText = pretty;
          _markerPosition = marker;
          _polygons = polygons;
        });
      } else {
        setState(() {
          _status = 'Server error — HTTP ${body.statusCode}';
          _responseText = body.body;
        });
      }
    } on SocketException catch (e) {
      setState(() {
        _status = 'Network error';
        _responseText = 'Could not reach the server.\n\nDetails: $e';
      });
    } catch (e) {
      setState(() {
        _status = 'Error';
        _responseText = e.toString();
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasImage = _selectedImage != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('GeoEngine OSINT'),
        centerTitle: true,
        backgroundColor: theme.colorScheme.surface,
        surfaceTintColor: theme.colorScheme.primary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Status chip ─────────────────────────────────────────────
            _StatusBadge(status: _status, isLoading: _isLoading),

            const SizedBox(height: 16),

            // ── Action buttons ──────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isLoading ? null : _pickImage,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text(hasImage ? 'Change Image' : 'Pick Image'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: (_isLoading || !hasImage) ? null : _analyzeImage,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.travel_explore),
                    label: const Text('Analyse'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // ── Response viewer ─────────────────────────────────────────
            Expanded(
              flex: 2,
              child: _ResponseViewer(text: _responseText),
            ),

            // ── Map (shown only after a successful parse) ────────────────
            if (_markerPosition != null) ...[
              const SizedBox(height: 12),
              _GeoMap(
                marker: _markerPosition!,
                polygons: _polygons,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small reusable widgets
// ---------------------------------------------------------------------------

/// Coloured status badge that also shows a spinner when loading.
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, required this.isLoading});

  final String status;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Color chipColor;
    if (status.startsWith('Done')) {
      chipColor = Colors.green.shade700;
    } else if (status.toLowerCase().contains('error') ||
        status.toLowerCase().contains('network')) {
      chipColor = Colors.red.shade700;
    } else if (isLoading) {
      chipColor = theme.colorScheme.primary;
    } else {
      chipColor = theme.colorScheme.surfaceContainerHighest;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: chipColor.withOpacity(0.2),
        border: Border.all(color: chipColor.withOpacity(0.6)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          if (isLoading) ...[
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: chipColor,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              status,
              style: theme.textTheme.bodyMedium?.copyWith(color: chipColor),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Map widget
// ---------------------------------------------------------------------------

/// Renders an OSM tile map centred on [marker] with an optional polygon layer
/// for the plonk_spatial_distribution rings.
class _GeoMap extends StatelessWidget {
  const _GeoMap({required this.marker, required this.polygons});

  final LatLng marker;
  final List<List<LatLng>> polygons;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 280,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: marker,
            initialZoom: 6,
          ),
          children: [
            // ── OSM base tiles ──────────────────────────────────────
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.geoengine.client',
            ),

            // ── Polygon layer (plonk spatial distribution) ──────────
            if (polygons.isNotEmpty)
              PolygonLayer(
                polygons: polygons
                    .map(
                      (ring) => Polygon(
                        points: ring,
                        color: const Color(0xFF00C8FF).withOpacity(0.18),
                        borderColor: const Color(0xFF00C8FF),
                        borderStrokeWidth: 1.6,
                      ),
                    )
                    .toList(),
              ),

            // ── Predicted-location marker ───────────────────────────
            MarkerLayer(
              markers: [
                Marker(
                  point: marker,
                  width: 40,
                  height: 40,
                  child: const _PinIcon(),
                ),
              ],
            ),

            // ── OSM attribution ─────────────────────────────────────
            RichAttributionWidget(
              attributions: [
                TextSourceAttribution(
                  'OpenStreetMap contributors',
                  onTap: () {},
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Highly visible pin rendered entirely with Flutter widgets (no asset needed).
class _PinIcon extends StatelessWidget {
  const _PinIcon();

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        // Shadow
        Positioned(
          bottom: 0,
          child: Container(
            width: 12,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.black38,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
        // Pin circle
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: Colors.red.shade600,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: const [
              BoxShadow(
                color: Colors.black38,
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(Icons.location_on, color: Colors.white, size: 16),
        ),
      ],
    );
  }
}

/// Scrollable monospace response panel.
class _ResponseViewer extends StatelessWidget {
  const _ResponseViewer({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEmpty = text.isEmpty;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant,
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: isEmpty
          ? Center(
              child: Text(
                'Response will appear here…',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : SingleChildScrollView(
              child: SelectableText(
                text,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
    );
  }
}
