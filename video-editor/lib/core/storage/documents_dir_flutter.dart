import 'package:path_provider/path_provider.dart';

/// The user's documents directory, as reported by the platform.
Future<String> documentsDirectoryPath() async =>
    (await getApplicationDocumentsDirectory()).path;
