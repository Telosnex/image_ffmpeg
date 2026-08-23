// Backward-compatible tool entry point for existing CI jobs.
import 'verify_artifacts.dart' as verifier;

Future<void> main() => verifier.main();
