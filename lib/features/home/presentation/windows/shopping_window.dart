import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:domail/shared/widgets/app_window_dialog.dart';
import 'package:domail/shared/widgets/personal_business_filter.dart';
import 'package:domail/features/home/domain/providers/email_list_provider.dart';
import 'package:domail/data/models/message_index.dart';

class ShoppingWindow extends ConsumerStatefulWidget {
  const ShoppingWindow({super.key});

  @override
  ConsumerState<ShoppingWindow> createState() => _ShoppingWindowState();
}

class _ShoppingWindowState extends ConsumerState<ShoppingWindow> {
  String? _filterLocal;

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(emailListProvider);
    return AppWindowDialog(
      title: 'Shopping',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PersonalBusinessFilter(
            selected: _filterLocal,
            onChanged: (v) => setState(() => _filterLocal = v),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: messagesAsync.when(
              data: (list) {
                final filtered = list.where((m) {
                  final shopping = m.shoppingLocal;
                  if (!shopping) return false;
                  if (_filterLocal == null) return true;
                  return m.localTagPersonal == _filterLocal;
                }).toList();
                if (filtered.isEmpty) return const Center(child: Text('No shopping emails'));
                return ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) => _shoppingTile(filtered[i]),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _shoppingTile(MessageIndex m) {
    return ListTile(
      leading: const Icon(Icons.shopping_bag_outlined),
      title: Text(m.subject, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(m.from, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () {
        // TODO: open email detail
      },
    );
  }
}


