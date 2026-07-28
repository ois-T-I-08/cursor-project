import '../../domain/repositories/material_inventory_repository.dart';
import '../db/app_database_facade.dart';

class DriftMaterialInventoryRepository implements MaterialInventoryRepository {
  DriftMaterialInventoryRepository(this._db);
  final AppDatabase _db;

  @override
  Future<Map<String, int>> getInventory(String userId) async {
    final rows = await _db.growthDao.inventoryGet(userId);
    return {for (final r in rows) r.materialId: r.quantity};
  }

  @override
  Future<void> setQuantity(String userId, String materialId, int quantity) =>
      _db.growthDao.inventorySetQuantity(userId, materialId, quantity);

  @override
  Future<void> removeQuantity(String userId, String materialId) =>
      _db.growthDao.inventoryDelete(userId, materialId);
}
