import 'dart:async';

import 'package:flutter/material.dart';

import '../data/parking_spot.dart';
import '../data/spot_database.dart';
import '../services/geocoder.dart';

/// Hakupalkki kartan päällä.
///
/// Haku yhdistää kaksi eri asiaa:
///
/// 1. **Osoitteet ja paikannimet** geokoodauksesta. Tämä on pääasiallinen
///    tapa, koska käyttäjä tietää minne on menossa — ei minkä nimisen
///    invapaikan luo.
/// 2. **Aineiston omat kohteet** nimen tai osoitteen perusteella. Tämä
///    kattaa vain pienen osan aineistosta: osoite tunnetaan 214 kohteelle
///    ja nimi harvemmalle. Siksi se on täydentävä, ei ensisijainen.
class MapSearchBar extends StatefulWidget {
  const MapSearchBar({
    super.key,
    required this.repository,
    required this.geocoder,
    required this.apiKey,
    required this.onSpotSelected,
    required this.onPlaceSelected,
    this.onOpenSettings,
  });

  final SpotRepository repository;
  final MmlGeocoder geocoder;
  final String apiKey;
  final ValueChanged<ParkingSpot> onSpotSelected;
  final ValueChanged<GeocodeResult> onPlaceSelected;
  final VoidCallback? onOpenSettings;

  @override
  State<MapSearchBar> createState() => _MapSearchBarState();
}

class _MapSearchBarState extends State<MapSearchBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  Timer? _debounce;
  int _requestId = 0;

  bool _loading = false;
  String? _error;
  List<GeocodeResult> _places = const [];
  List<ParkingSpot> _spots = const [];

  bool get _hasQuery => _controller.text.trim().isNotEmpty;
  bool get _hasResults => _places.isNotEmpty || _spots.isNotEmpty;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _places = const [];
        _spots = const [];
        _error = null;
        _loading = false;
      });
      return;
    }
    // Geokoodaus on verkkokutsu jaettuun palveluun, joten sitä ei tehdä
    // jokaisesta näppäinpainalluksesta.
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(value));
  }

  Future<void> _search(String query) async {
    final id = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });

    // Paikallinen haku ei voi epäonnistua verkon takia, joten se tehdään
    // aina — myös silloin kun geokoodaus kaatuu tai avain puuttuu.
    List<ParkingSpot> spots = const [];
    try {
      spots = await widget.repository.searchByText(query, limit: 3);
    } catch (_) {
      spots = const [];
    }

    List<GeocodeResult> places = const [];
    String? error;
    try {
      places = await widget.geocoder.search(query, apiKey: widget.apiKey, limit: 6);
    } on GeocoderException catch (exception) {
      error = exception.message;
    } catch (_) {
      error = 'Hakua ei voitu tehdä.';
    }

    if (!mounted || id != _requestId) return;
    setState(() {
      _loading = false;
      _spots = spots;
      _places = places;
      _error = error;
    });
  }

  void _clear() {
    _controller.clear();
    _focusNode.unfocus();
    setState(() {
      _places = const [];
      _spots = const [];
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          elevation: 3,
          borderRadius: BorderRadius.circular(28),
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            textInputAction: TextInputAction.search,
            onChanged: _onChanged,
            onSubmitted: (value) {
              _debounce?.cancel();
              if (value.trim().isNotEmpty) _search(value);
            },
            decoration: InputDecoration(
              hintText: 'Hae osoitteella tai paikannimellä',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : _hasQuery
                      ? IconButton(
                          tooltip: 'Tyhjennä haku',
                          icon: const Icon(Icons.close),
                          onPressed: _clear,
                        )
                      : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: theme.colorScheme.surface,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        if (_hasQuery && (_hasResults || _error != null || !_loading))
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _ResultsPanel(
              places: _places,
              spots: _spots,
              error: _error,
              loading: _loading,
              onOpenSettings: widget.onOpenSettings,
              onSpotTap: (spot) {
                _focusNode.unfocus();
                _clear();
                widget.onSpotSelected(spot);
              },
              onPlaceTap: (place) {
                _focusNode.unfocus();
                _clear();
                widget.onPlaceSelected(place);
              },
            ),
          ),
      ],
    );
  }
}

class _ResultsPanel extends StatelessWidget {
  const _ResultsPanel({
    required this.places,
    required this.spots,
    required this.error,
    required this.loading,
    required this.onSpotTap,
    required this.onPlaceTap,
    this.onOpenSettings,
  });

  final List<GeocodeResult> places;
  final List<ParkingSpot> spots;
  final String? error;
  final bool loading;
  final ValueChanged<ParkingSpot> onSpotTap;
  final ValueChanged<GeocodeResult> onPlaceTap;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final children = <Widget>[];

    if (places.isNotEmpty) {
      children.add(_header(context, 'Osoitteet ja paikat'));
      children.addAll(
        places.map(
          (place) => ListTile(
            dense: true,
            leading: const Icon(Icons.place_outlined),
            title: Text(place.label, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: place.region == null ? null : Text(place.region!),
            onTap: () => onPlaceTap(place),
          ),
        ),
      );
    }

    if (spots.isNotEmpty) {
      children.add(_header(context, 'Invapaikat'));
      children.addAll(
        spots.map(
          (spot) => ListTile(
            dense: true,
            leading: const Icon(Icons.accessible),
            title: Text(spot.title, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: spot.address == null || spot.address == spot.title
                ? null
                : Text(spot.address!),
            onTap: () => onSpotTap(spot),
          ),
        ),
      );
    }

    if (error != null) {
      children.add(
        ListTile(
          dense: true,
          leading: Icon(Icons.warning_amber, color: theme.colorScheme.error),
          title: Text(error!),
          trailing: onOpenSettings == null
              ? null
              : TextButton(
                  onPressed: onOpenSettings,
                  child: const Text('Asetukset'),
                ),
        ),
      );
    }

    if (children.isEmpty) {
      if (loading) return const SizedBox.shrink();
      children.add(
        const ListTile(
          dense: true,
          leading: Icon(Icons.search_off),
          title: Text('Ei hakutuloksia.'),
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        // Hakutulokset eivät saa peittää koko karttaa.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.45,
        ),
        child: ListView(shrinkWrap: true, children: children),
      ),
    );
  }

  Widget _header(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.bold,
              ),
        ),
      );
}
