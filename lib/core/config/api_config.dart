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

  static const String dataCloudBaseUrl = String.fromEnvironment(
    'DATA_CLOUD_API_BASE_URL',
    defaultValue: '$host/api/datacloud/',
  );

  static const String dataCloudRootPath = String.fromEnvironment(
    'DATA_CLOUD_ROOT_PATH',
    defaultValue: '',
  );

  static const String _chatBaseOverride = String.fromEnvironment('CHAT_API_BASE_URL');
  static const String _chatHubOverride = String.fromEnvironment('CHAT_HUB_URL');
  static String get chatBaseUrl => _chatBaseOverride.isNotEmpty ? _chatBaseOverride
    : Uri.parse(inventoryBaseUrl.endsWith('/') ? inventoryBaseUrl : '$inventoryBaseUrl/').resolve('chat/').toString();
  static String get chatHubUrl => _chatHubOverride.isNotEmpty ? _chatHubOverride
    : Uri.parse(inventoryBaseUrl.endsWith('/') ? inventoryBaseUrl : '$inventoryBaseUrl/').resolve('hubs/chat').toString();
}
