import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../config.dart';
import '../data/parking_spot.dart';
import '../data/spot_database.dart';
import '../services/geocoder.dart';
import '../services/map_key_store.dart';
import 'api_key_screen.dart';
import 'map_search_bar.dart';
import 'spot_details_sheet.dart';
import 'spot_marker.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    required this.database,
    required this.keyStore,
    this.geocoder,
  });

  final SpotRepository database;
  final MapKeyStore keyStore;

  /// Testeissä korvattavissa; tuotannossa luodaan oletustoteutus.
  final MmlGeocoder? geocoder;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  late final MmlGeocoder _geocoder = widget.geocoder ?? MmlGeocoder();
  late final bool _ownsGeocoder = widget.geocoder == null;

  List<ParkingSpot> _spots = const [];
  final Map<Key, ParkingSpot> _spotsByKey = {};

  Timer? _debounce;
  bool _loading = false;
  LatLng? _userPosition;

  @override
  void dispose() {
    _debounce?.cancel();
    if (_ownsGeocoder) _geocoder.dispose();
    _mapController.dispose();
    super.dispose();
  }

  /// Siirrä kartta hakutuloksen kohdalle. Zoom 16 näyttää korttelin, mikä
  /// on oikea mittakaava pysäköintipaikan etsimiseen.
  void _goToPlace(GeocodeResult place) {
    _mapController.move(LatLng(place.lat, place.lon), 16);
  }

  Future<void> _goToSpot(ParkingSpot spot) async {
    _mapController.move(spot.position, 17);
    await _loadVisible(_mapController.camera.visibleBounds);
    if (mounted) await SpotDetailsSheet.show(context, spot);
  }

  /// Kartan liikkuessa haetaan vain näkyvän ruudun kohteet. Viive estää
  /// kyselytulvan, kun käyttäjä raahaa karttaa yhtäjaksoisesti.
  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      _loadVisible(camera.visibleBounds);
    });
  }

  Future<void> _loadVisible(LatLngBounds bounds) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final spots = await widget.database.spotsInBounds(
        minLat: bounds.south,
        maxLat: bounds.north,
        minLon: bounds.west,
        maxLon: bounds.east,
      );
      if (!mounted) return;
      setState(() {
        _spots = spots;
        _spotsByKey
          ..clear()
          ..addEntries(spots.map((s) => MapEntry(ValueKey(s.uid), s)));
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _goToMyLocation() async {
    final messenger = ScaffoldMessenger.of(context);

    if (!await Geolocator.isLocationServiceEnabled()) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Sijaintipalvelut eivät ole päällä.')),
      );
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Sijaintilupa puuttuu.')),
      );
      return;
    }

    final position = await Geolocator.getCurrentPosition();
    if (!mounted) return;
    final target = LatLng(position.latitude, position.longitude);
    setState(() => _userPosition = target);
    _mapController.move(target, 16);
  }

  Future<void> _openKeyScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ApiKeyScreen(store: widget.keyStore),
      ),
    );
  }

  List<Marker> _buildMarkers() {
    return _spots
        .map(
          (spot) => Marker(
            key: ValueKey(spot.uid),
            point: spot.position,
            width: 34,
            height: 34,
            child: SpotMarkerIcon(spot: spot),
          ),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LEParkki'),
        actions: [
          IconButton(
            tooltip: 'Asetukset',
            onPressed: _openKeyScreen,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
        bottom: _loading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: ListenableBuilder(
        listenable: widget.keyStore,
        builder: (context, _) {
          return Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: const LatLng(Config.fallbackLat, Config.fallbackLon),
                  initialZoom: Config.fallbackZoom,
                  onPositionChanged: _onPositionChanged,
                  onMapReady: () =>
                      _loadVisible(_mapController.camera.visibleBounds),
                ),
                children: [
                  if (widget.keyStore.hasKey)
                    TileLayer(
                      urlTemplate: Config.mmlTileUrl(widget.keyStore.key),
                      userAgentPackageName: Config.userAgentPackageName,
                      maxNativeZoom: 18,
                    ),
                  if (_userPosition != null)
                    CircleLayer(
                      circles: [
                        CircleMarker(
                          point: _userPosition!,
                          radius: 8,
                          useRadiusInMeter: false,
                          color: Colors.blue.withValues(alpha: 0.9),
                          borderColor: Colors.white,
                          borderStrokeWidth: 2,
                        ),
                      ],
                    ),
                  MarkerClusterLayerWidget(
                    options: MarkerClusterLayerOptions(
                      markers: _buildMarkers(),
                      maxClusterRadius: 45,
                      size: const Size(40, 40),
                      disableClusteringAtZoom: 17,
                      padding: const EdgeInsets.all(50),
                      onMarkerTap: (marker) {
                        final spot = _spotsByKey[marker.key];
                        if (spot != null) SpotDetailsSheet.show(context, spot);
                      },
                      builder: (context, markers) =>
                          ClusterIcon(count: markers.length),
                    ),
                  ),
                ],
              ),
              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    MapSearchBar(
                      repository: widget.database,
                      geocoder: _geocoder,
                      apiKey: widget.keyStore.key,
                      onPlaceSelected: _goToPlace,
                      onSpotSelected: _goToSpot,
                      onOpenSettings: _openKeyScreen,
                    ),
                    if (!widget.keyStore.hasKey)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: _MissingKeyBanner(onTap: _openKeyScreen),
                      ),
                  ],
                ),
              ),
              const Positioned(left: 12, bottom: 12, child: MapLegend()),
              Positioned(
                right: 12,
                bottom: 12,
                child: FloatingActionButton(
                  onPressed: _goToMyLocation,
                  tooltip: 'Oma sijainti',
                  child: const Icon(Icons.my_location),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Ilmoitus siitä, että taustakartta puuttuu avaimen puuttuessa.
///
/// Sovellus on tarkoituksella käyttökelpoinen ilman avainta: invapaikat ja
/// navigointi toimivat, vain taustakartta jää tyhjäksi.
class _MissingKeyBanner extends StatelessWidget {
  const _MissingKeyBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: ListTile(
        leading: const Icon(Icons.map_outlined),
        title: const Text('Taustakartta puuttuu'),
        subtitle: const Text(
          'Lisää maksuton Maanmittauslaitoksen API-avain nähdäksesi kartan ja '
          'ottaaksesi osoitehaun käyttöön. Invapaikat ja navigointi toimivat jo nyt.',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
