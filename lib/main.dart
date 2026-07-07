import 'package:flutter/material.dart';
import 'services/storage_service.dart';
import 'services/video_storage_service.dart';
import 'pages/home_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StorageService().init();
  await VideoStorageService().init();
  runApp(const ComicReaderApp());
}

class ComicReaderApp extends StatelessWidget {
  const ComicReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI 助手',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4E6EF2)),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}
