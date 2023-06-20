import 'package:flutter/material.dart';

import 'package:shorebird_code_push/shorebird_code_push.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Shorebird Code Push Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Shorebird Code Push'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({required this.title, super.key});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final _shorebirdCodePush = ShorebirdCodePush();
  int? _currentPatchVersion;
  int? _nextPatchVersion;
  bool _isCheckingForUpdate = false;

  @override
  void initState() {
    super.initState();
    _shorebirdCodePush.currentPatchNumber().then((currentPatchVersion) async {
      final nextPatchVersion = await _shorebirdCodePush.nextPatchNumber();

      if (!mounted) return;

      setState(() {
        _currentPatchVersion = currentPatchVersion;
        _nextPatchVersion = nextPatchVersion;
      });
    });
  }

  Future<void> _checkForUpdate() async {
    setState(() {
      _isCheckingForUpdate = true;
    });

    final isUpdateAvailable = await _shorebirdCodePush.checkForUpdate();

    if (!mounted) return;

    setState(() {
      _isCheckingForUpdate = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isUpdateAvailable ? 'Update available' : 'No update available',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text('Current patch version:'),
            Text(
              _currentPatchVersion != null
                  ? _currentPatchVersion.toString()
                  : 'none',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            if (_nextPatchVersion != null &&
                _nextPatchVersion != _currentPatchVersion)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  const Text('Next patch version:'),
                  Text(
                    _nextPatchVersion.toString(),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ],
              ),
            const SizedBox(
              height: 20,
            ),
            ElevatedButton(
              onPressed: _isCheckingForUpdate ? null : _checkForUpdate,
              child: _isCheckingForUpdate
                  ? const SizedBox(
                      height: 14,
                      width: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Check for update'),
            ),
          ],
        ),
      ),
    );
  }
}
