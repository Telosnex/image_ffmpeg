import 'package:image_ffmpeg/image_ffmpeg.dart';
import 'package:flutter/material.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      appBar: AppBar(title: const Text('image_ffmpeg')),
      body: FutureBuilder<Ffmpeg>(
        future: Ffmpeg.load(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Load failed: ${snapshot.error}'));
          }
          final ffmpeg = snapshot.data;
          if (ffmpeg == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                '${ffmpeg.capabilities}\n\n'
                'Pinned reduced FFmpeg is bundled and ready.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        },
      ),
    ),
  );
}
