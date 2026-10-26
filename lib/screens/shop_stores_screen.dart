import 'package:flutter/material.dart';
import '../services/stores_api_service.dart';
import 'store_catalog_screen.dart';

class ShopStoresScreen extends StatefulWidget {
  const ShopStoresScreen({super.key});

  @override
  State<ShopStoresScreen> createState() => _ShopStoresScreenState();
}

class _ShopStoresScreenState extends State<ShopStoresScreen> {
  List<dynamic> _stores = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStores();
  }

  Future<void> _loadStores() async {
    try {
      final list = await StoresApiService().getStores();
      if (!mounted) return;
      setState(() {
        _stores = list;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cửa hàng đối tác')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _stores.length,
              itemBuilder: (context, index) {
                final store = _stores[index] as Map;
                final id = (store['storeId'] ?? store['id'] ?? '').toString();
                final name = (store['name'] ?? 'Đại lý').toString();
                return ListTile(
                  title: Text(name),
                  subtitle: Text((store['address'] ?? '').toString()),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => StoreCatalogScreen(
                        storeId: id,
                        storeName: name,
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
