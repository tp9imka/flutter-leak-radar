# flutter_perf_radar example

A minimal Flutter wiring that shows every entry point used in a real app.

## Setup in `main()`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_perf_radar/flutter_perf_radar.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PerfRadar.init(PerfRadarConfig.standard());
  runApp(
    PerfRadar.overlay(child: const MyApp()),
  );
}
```

## Instrumenting a route

```dart
class ProductsScreen extends StatelessWidget {
  const ProductsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Products')),
      body: TracedSubtree(
        label: 'products_list',
        child: const _ProductList(),
      ),
    );
  }
}
```

## Tracing async operations

```dart
Future<List<Product>> loadProducts() async {
  return PerfRadar.traceAsync('load_products', () async {
    return await productsRepository.fetchAll();
  });
}
```

## Manual start/stop for callback-bounded code

```dart
void startDecoding(Uint8List bytes) {
  final handle = PerfRadar.start('image_decode', category: 'media');
  decoder.decode(
    bytes,
    onDone: (_) => handle.stop(),
    onError: (e) => handle.fail(e),
  );
}
```

## Reading frame stats and stability

```dart
final frames = PerfRadar.frameStats;
print('frames: ${frames.frameCount}  jank: ${frames.jankCount}');

final stability = PerfRadar.stabilitySnapshot;
print('errors: ${stability.errorCount}  stalls: ${stability.stallCount}');
```

## Opening the full inspector

```dart
Navigator.of(context).push(
  MaterialPageRoute(builder: (_) => const PerfRadarScreen()),
);
```
