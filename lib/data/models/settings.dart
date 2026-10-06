enum CardProviderType { external, sumupSolo, sumupBluetooth }

extension CardProviderTypeX on CardProviderType {
  String get label => switch (this) {
        CardProviderType.external => 'Standalone terminal (confirm on till)',
        CardProviderType.sumupSolo => 'SumUp Solo (Cloud API)',
        CardProviderType.sumupBluetooth => 'SumUp Bluetooth (native SDK)',
      };
}

enum PrinterType { none, system, network, bluetooth }

extension PrinterTypeX on PrinterType {
  String get label => switch (this) {
        PrinterType.none => 'No printer',
        PrinterType.system => 'System print dialog / PDF',
        PrinterType.network => 'Network ESC/POS printer (LAN)',
        PrinterType.bluetooth => 'Bluetooth ESC/POS printer',
      };
}

enum ReceiptDefault { ask, print, email, none }

/// Per-device till settings, mirroring the Goodtill/SumUp POS settings screen.
/// Non-secret settings are also pushed to the register profile on the server.
class PosSettings {
  const PosSettings({
    this.cashEnabled = true,
    this.cashPrompt = false,
    this.cardEnabled = true,
    this.cardPrompt = true,
    this.otherEnabled = true,
    this.cardProvider = CardProviderType.external,
    this.sumupApiKey = '',
    this.sumupMerchantCode = '',
    this.sumupReaderId = '',
    this.eatInTakeAway = false,
    this.floatAfterClose = false,
    this.allergenPopup = false,
    this.outOfStockPrompt = true,
    this.sellBeyondStock = false,
    this.qrAfterOrder = false,
    this.tableQrButton = false,
    this.tableTimers = true,
    this.receiptPrompt = true,
    this.receiptDefault = ReceiptDefault.ask,
    this.pricesIncludeTax = true,
    this.tipsEnabled = false,
    this.maxCashierDiscountPercent = 10,
    this.autoLockSeconds = 0,
    this.printerType = PrinterType.system,
    this.printerHost = '',
    this.printerPort = 9100,
    this.paperWidth = 80,
    this.openDrawerOnCash = true,
    this.receiptFooter = 'Thank you for shopping with us!',
    this.themeMode = 'system',
    this.gridColumns = 0,
    this.showProductImages = true,
    this.soundOnScan = true,
    this.socketCaptureEnabled = false,
    this.socketAppId = 'web:epos.zaamaitech.co.uk',
    this.socketDeveloperId = '',
    this.socketAppKey = '',
  });

  final bool cashEnabled;
  final bool cashPrompt;
  final bool cardEnabled;
  final bool cardPrompt;
  final bool otherEnabled;
  final CardProviderType cardProvider;
  final String sumupApiKey;
  final String sumupMerchantCode;
  final String sumupReaderId;

  final bool eatInTakeAway;
  final bool floatAfterClose;
  final bool allergenPopup;
  final bool outOfStockPrompt;

  /// When false the cart never holds more units than the register's stock.
  final bool sellBeyondStock;
  final bool qrAfterOrder;
  final bool tableQrButton;
  final bool tableTimers;
  final bool receiptPrompt;
  final ReceiptDefault receiptDefault;
  final bool pricesIncludeTax;
  final bool tipsEnabled;
  final int maxCashierDiscountPercent;
  final int autoLockSeconds;

  final PrinterType printerType;
  final String printerHost;
  final int printerPort;
  final int paperWidth;
  final bool openDrawerOnCash;
  final String receiptFooter;

  final String themeMode;

  /// 0 = automatic by screen width.
  final int gridColumns;
  final bool showProductImages;
  final bool soundOnScan;

  /// Socket Mobile Application mode (CaptureJS + Companion). Basic/HID mode needs no setup.
  final bool socketCaptureEnabled;

  /// CaptureJS credentials from the Socket Mobile developer portal; the AppKey is bound to [socketAppId].
  final String socketAppId;
  final String socketDeveloperId;
  final String socketAppKey;

  PosSettings copyWith({
    bool? cashEnabled,
    bool? cashPrompt,
    bool? cardEnabled,
    bool? cardPrompt,
    bool? otherEnabled,
    CardProviderType? cardProvider,
    String? sumupApiKey,
    String? sumupMerchantCode,
    String? sumupReaderId,
    bool? eatInTakeAway,
    bool? floatAfterClose,
    bool? allergenPopup,
    bool? outOfStockPrompt,
    bool? sellBeyondStock,
    bool? qrAfterOrder,
    bool? tableQrButton,
    bool? tableTimers,
    bool? receiptPrompt,
    ReceiptDefault? receiptDefault,
    bool? pricesIncludeTax,
    bool? tipsEnabled,
    int? maxCashierDiscountPercent,
    int? autoLockSeconds,
    PrinterType? printerType,
    String? printerHost,
    int? printerPort,
    int? paperWidth,
    bool? openDrawerOnCash,
    String? receiptFooter,
    String? themeMode,
    int? gridColumns,
    bool? showProductImages,
    bool? soundOnScan,
    bool? socketCaptureEnabled,
    String? socketAppId,
    String? socketDeveloperId,
    String? socketAppKey,
  }) =>
      PosSettings(
        cashEnabled: cashEnabled ?? this.cashEnabled,
        cashPrompt: cashPrompt ?? this.cashPrompt,
        cardEnabled: cardEnabled ?? this.cardEnabled,
        cardPrompt: cardPrompt ?? this.cardPrompt,
        otherEnabled: otherEnabled ?? this.otherEnabled,
        cardProvider: cardProvider ?? this.cardProvider,
        sumupApiKey: sumupApiKey ?? this.sumupApiKey,
        sumupMerchantCode: sumupMerchantCode ?? this.sumupMerchantCode,
        sumupReaderId: sumupReaderId ?? this.sumupReaderId,
        eatInTakeAway: eatInTakeAway ?? this.eatInTakeAway,
        floatAfterClose: floatAfterClose ?? this.floatAfterClose,
        allergenPopup: allergenPopup ?? this.allergenPopup,
        outOfStockPrompt: outOfStockPrompt ?? this.outOfStockPrompt,
        sellBeyondStock: sellBeyondStock ?? this.sellBeyondStock,
        qrAfterOrder: qrAfterOrder ?? this.qrAfterOrder,
        tableQrButton: tableQrButton ?? this.tableQrButton,
        tableTimers: tableTimers ?? this.tableTimers,
        receiptPrompt: receiptPrompt ?? this.receiptPrompt,
        receiptDefault: receiptDefault ?? this.receiptDefault,
        pricesIncludeTax: pricesIncludeTax ?? this.pricesIncludeTax,
        tipsEnabled: tipsEnabled ?? this.tipsEnabled,
        maxCashierDiscountPercent: maxCashierDiscountPercent ?? this.maxCashierDiscountPercent,
        autoLockSeconds: autoLockSeconds ?? this.autoLockSeconds,
        printerType: printerType ?? this.printerType,
        printerHost: printerHost ?? this.printerHost,
        printerPort: printerPort ?? this.printerPort,
        paperWidth: paperWidth ?? this.paperWidth,
        openDrawerOnCash: openDrawerOnCash ?? this.openDrawerOnCash,
        receiptFooter: receiptFooter ?? this.receiptFooter,
        themeMode: themeMode ?? this.themeMode,
        gridColumns: gridColumns ?? this.gridColumns,
        showProductImages: showProductImages ?? this.showProductImages,
        soundOnScan: soundOnScan ?? this.soundOnScan,
        socketCaptureEnabled: socketCaptureEnabled ?? this.socketCaptureEnabled,
        socketAppId: socketAppId ?? this.socketAppId,
        socketDeveloperId: socketDeveloperId ?? this.socketDeveloperId,
        socketAppKey: socketAppKey ?? this.socketAppKey,
      );

  Map<String, dynamic> toJson({bool includeSecrets = true}) => {
        'cashEnabled': cashEnabled,
        'cashPrompt': cashPrompt,
        'cardEnabled': cardEnabled,
        'cardPrompt': cardPrompt,
        'otherEnabled': otherEnabled,
        'cardProvider': cardProvider.name,
        if (includeSecrets) 'sumupApiKey': sumupApiKey,
        'sumupMerchantCode': sumupMerchantCode,
        'sumupReaderId': sumupReaderId,
        'eatInTakeAway': eatInTakeAway,
        'floatAfterClose': floatAfterClose,
        'allergenPopup': allergenPopup,
        'outOfStockPrompt': outOfStockPrompt,
        'sellBeyondStock': sellBeyondStock,
        'qrAfterOrder': qrAfterOrder,
        'tableQrButton': tableQrButton,
        'tableTimers': tableTimers,
        'receiptPrompt': receiptPrompt,
        'receiptDefault': receiptDefault.name,
        'pricesIncludeTax': pricesIncludeTax,
        'tipsEnabled': tipsEnabled,
        'maxCashierDiscountPercent': maxCashierDiscountPercent,
        'autoLockSeconds': autoLockSeconds,
        'printerType': printerType.name,
        'printerHost': printerHost,
        'printerPort': printerPort,
        'paperWidth': paperWidth,
        'openDrawerOnCash': openDrawerOnCash,
        'receiptFooter': receiptFooter,
        'themeMode': themeMode,
        'gridColumns': gridColumns,
        'showProductImages': showProductImages,
        'soundOnScan': soundOnScan,
        'socketCaptureEnabled': socketCaptureEnabled,
        'socketAppId': socketAppId,
        'socketDeveloperId': socketDeveloperId,
        'socketAppKey': socketAppKey,
      };

  factory PosSettings.fromJson(Map<String, dynamic> j) {
    const d = PosSettings();
    bool b(String k, bool def) => j[k] is bool ? j[k] as bool : def;
    int i(String k, int def) => j[k] is num ? (j[k] as num).toInt() : def;
    String s(String k, String def) => j[k] is String ? j[k] as String : def;
    return PosSettings(
      cashEnabled: b('cashEnabled', d.cashEnabled),
      cashPrompt: b('cashPrompt', d.cashPrompt),
      cardEnabled: b('cardEnabled', d.cardEnabled),
      cardPrompt: b('cardPrompt', d.cardPrompt),
      otherEnabled: b('otherEnabled', d.otherEnabled),
      cardProvider: CardProviderType.values.firstWhere((v) => v.name == j['cardProvider'], orElse: () => d.cardProvider),
      sumupApiKey: s('sumupApiKey', d.sumupApiKey),
      sumupMerchantCode: s('sumupMerchantCode', d.sumupMerchantCode),
      sumupReaderId: s('sumupReaderId', d.sumupReaderId),
      eatInTakeAway: b('eatInTakeAway', d.eatInTakeAway),
      floatAfterClose: b('floatAfterClose', d.floatAfterClose),
      allergenPopup: b('allergenPopup', d.allergenPopup),
      outOfStockPrompt: b('outOfStockPrompt', d.outOfStockPrompt),
      sellBeyondStock: b('sellBeyondStock', d.sellBeyondStock),
      qrAfterOrder: b('qrAfterOrder', d.qrAfterOrder),
      tableQrButton: b('tableQrButton', d.tableQrButton),
      tableTimers: b('tableTimers', d.tableTimers),
      receiptPrompt: b('receiptPrompt', d.receiptPrompt),
      receiptDefault: ReceiptDefault.values.firstWhere((v) => v.name == j['receiptDefault'], orElse: () => d.receiptDefault),
      pricesIncludeTax: b('pricesIncludeTax', d.pricesIncludeTax),
      tipsEnabled: b('tipsEnabled', d.tipsEnabled),
      maxCashierDiscountPercent: i('maxCashierDiscountPercent', d.maxCashierDiscountPercent),
      autoLockSeconds: i('autoLockSeconds', d.autoLockSeconds),
      printerType: PrinterType.values.firstWhere((v) => v.name == j['printerType'], orElse: () => d.printerType),
      printerHost: s('printerHost', d.printerHost),
      printerPort: i('printerPort', d.printerPort),
      paperWidth: i('paperWidth', d.paperWidth),
      openDrawerOnCash: b('openDrawerOnCash', d.openDrawerOnCash),
      receiptFooter: s('receiptFooter', d.receiptFooter),
      themeMode: s('themeMode', d.themeMode),
      gridColumns: i('gridColumns', d.gridColumns),
      showProductImages: b('showProductImages', d.showProductImages),
      soundOnScan: b('soundOnScan', d.soundOnScan),
      socketCaptureEnabled: b('socketCaptureEnabled', d.socketCaptureEnabled),
      socketAppId: s('socketAppId', d.socketAppId),
      socketDeveloperId: s('socketDeveloperId', d.socketDeveloperId),
      socketAppKey: s('socketAppKey', d.socketAppKey),
    );
  }
}
