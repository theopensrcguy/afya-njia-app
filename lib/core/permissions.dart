/// Permission names, the same as the server's App\Support\Permissions.
/// Use with `session.user!.can(Perm.viewStock)`.
abstract final class Perm {
  static const sell = 'sell';
  static const receive = 'receive';
  static const confirmDeliveries = 'confirm_deliveries';
  static const receiveUnconfirmed = 'receive_unconfirmed';
  static const viewStock = 'view_stock';
  static const viewCosts = 'view_costs';
  static const editPrices = 'edit_prices';
  static const createProducts = 'create_products';
  static const adjustStock = 'adjust_stock';
  static const voidAnySale = 'void_any_sale';
  static const bigDiscount = 'big_discount';
  static const viewShopSales = 'view_shop_sales';
  static const manageDevices = 'manage_devices';
  static const prepareOrders = 'prepare_orders';
}
