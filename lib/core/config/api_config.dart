class ApiConfig {
  const ApiConfig._();

  static const String host = 'https://pembd-adapter.cns.myfiinet.com';

  static const String inventoryBaseUrl = String.fromEnvironment(
    'INVENTORY_API_BASE_URL',
    defaultValue: '$host/api/',
  );

  static const String productBaseUrl = String.fromEnvironment(
    'PRODUCT_API_BASE_URL',
    defaultValue: '$host/',
  );

  static const String scanBaseUrl = String.fromEnvironment(
    'SCAN_API_BASE_URL',
    defaultValue: '$host/api/Scan/',
  );
}
