// ignore_for_file: avoid_print
import 'dart:math';

import 'package:dart_bindings/updater.dart';
import 'package:flutter/material.dart';

void main() {
  try {
    Updater.loadFlutterLibrary();
    var updater = Updater();
    // Just to prove the bindings work at all:
    print("active version: ${updater.activeVersion()}");
    print("active path: ${updater.activePath()}");
  } catch (e) {
    print(
        "Could not load shorebird updater library.  Did you run with `shorebird run`?");
    print("Error: $e");
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Shorebird Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Shorebird Updater Demo'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

// Stub until https://github.com/shorebirdtech/shorebird/issues/123 is resolved.
class Update {
  const Update(this.version, this.bytes);

  final String version;
  final int bytes;
}

class _MyHomePageState extends State<MyHomePage> {
  String _fileSizeString(int bytes) {
    const suffixes = ["b", "kb", "mb", "gb"];
    final i = (log(bytes) / log(1024)).floor();
    return ((bytes / pow(1024, i)).toStringAsFixed(1)) + suffixes[i];
  }

  void _showUpdateBanner() {
    const update = Update("1.2.3", 1234567);

    ScaffoldMessenger.of(context).showMaterialBanner(MaterialBanner(
      padding: const EdgeInsets.all(20),
      content: Text('A new version (${update.version}) is available.\n'
          'Download size: ${_fileSizeString(update.bytes)}'),
      leading: const Icon(Icons.update),
      backgroundColor: Colors.green,
      // Android button order appears to be "negative", "neutral", "positive".
      actions: <Widget>[
        TextButton(
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
          },
          child: const Text('LATER'),
        ),
        TextButton(
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
            _showProgressBanner();
          },
          child: const Text('INSTALL'),
        ),
      ],
    ));
  }

  void _showProgressBanner() {
    final controller =
        ScaffoldMessenger.of(context).showMaterialBanner(MaterialBanner(
      content: const LinearProgressIndicator(
        value: null,
        semanticsLabel: 'Download progress',
      ),
      leading: const Icon(Icons.update),
      backgroundColor: Colors.green,
      actions: <Widget>[
        TextButton(
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
          },
          child: const Text('HIDE'),
        ),
      ],
    ));
    Future.delayed(const Duration(seconds: 5)).then((_) {
      controller.close();
      _showRestartBanner();
    });
  }

  void _showRestartBanner() {
    ScaffoldMessenger.of(context).showMaterialBanner(MaterialBanner(
      content: const Text('Restart to apply update.'),
      leading: const Icon(Icons.update),
      backgroundColor: Colors.green,
      // Android button order appears to be "negative", "neutral", "positive".
      actions: <Widget>[
        TextButton(
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
          },
          child: const Text('LATER'),
        ),
        TextButton(
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
            // Need a restart API.
            // https://github.com/shorebirdtech/shorebird/issues/117
          },
          child: const Text('RESTART'),
        ),
      ],
    ));
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
          children: const <Widget>[
            Text(
                "This demo shows how to call the Shorebird updater library from Dart."),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Show Update Banner',
        onPressed: _showUpdateBanner,
        child: const Icon(Icons.update),
      ),
    );
  }
}
