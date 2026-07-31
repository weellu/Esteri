import 'package:flutter/material.dart';

import '../config.dart';
import '../services/map_key_store.dart';
import '../services/navigation_launcher.dart';

/// Karttatiilien API-avaimen syöttö.
///
/// Demovaiheessa käyttäjä antaa oman maksuttoman MML-avaimensa, jolloin
/// sovellusta voi kokeilla ilman uudelleenkäännöstä. Avain tallennetaan vain
/// laitteelle.
class ApiKeyScreen extends StatefulWidget {
  const ApiKeyScreen({super.key, required this.store});

  final MapKeyStore store;

  @override
  State<ApiKeyScreen> createState() => _ApiKeyScreenState();
}

class _ApiKeyScreenState extends State<ApiKeyScreen> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.store.key);
  bool _checking = false;
  MapKeyCheck? _result;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _saveAndVerify() async {
    setState(() {
      _checking = true;
      _result = null;
    });

    final value = _controller.text.trim();
    final check = await MapKeyStore.verify(value);

    // Verkkovirhe ei tarkoita väärää avainta, joten avain tallennetaan
    // muutenkin kuin onnistuneella tarkistuksella.
    if (check.isOk || check.status == MapKeyStatus.networkError) {
      await widget.store.save(value);
    }

    if (!mounted) return;
    setState(() {
      _checking = false;
      _result = check;
    });

    if (check.isOk && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Karttatiilien API-avain')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Taustakartta tulee Maanmittauslaitoksen maksuttomasta '
            'karttakuvapalvelusta, joka vaatii API-avaimen.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 12),
          Text(
            'Avain on ilmainen. Se luodaan MML:n OmaTili-palvelussa eikä vaadi '
            'laskutustiliä tai luottokorttia. Avain tallennetaan vain tälle '
            'laitteelle, eikä sitä lähetetä muualle kuin Maanmittauslaitoksen '
            'tiilipalveluun.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () =>
                NavigationLauncher.openUrl(Config.mmlKeyInstructionsUrl),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('Ohje avaimen luomiseen'),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _controller,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'API-avain',
              hintText: 'Liitä avain tähän',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _saveAndVerify(),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _checking ? null : _saveAndVerify,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: _checking
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Tallenna ja testaa'),
          ),
          if (_result != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _result!.isOk
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(_result!.isOk ? Icons.check_circle_outline : Icons.warning_amber),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_result!.message)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          Text(
            'Ilman avainta invapaikat näkyvät kartalla, mutta taustakartta jää '
            'tyhjäksi. Navigointi puhelimen omaan karttasovellukseen toimii '
            'joka tapauksessa — se ei vaadi avainta.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
