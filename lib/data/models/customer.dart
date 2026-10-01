class Customer {
  const Customer({required this.id, required this.name, this.email, this.phone, this.customerNumber, this.tier, this.totalOrders = 0, this.lifetimeValue = 0});

  final String id;
  final String name;
  final String? email;
  final String? phone;
  final String? customerNumber;
  final String? tier;
  final int totalOrders;
  final double lifetimeValue;

  factory Customer.fromJson(Map<String, dynamic> j) => Customer(
        id: '${j['id']}',
        name: '${j['name'] ?? 'Customer'}',
        email: j['email'] as String?,
        phone: j['phone'] as String?,
        customerNumber: j['customerNumber'] as String?,
        tier: j['tier'] as String?,
        totalOrders: (j['totalOrders'] as num?)?.toInt() ?? 0,
        lifetimeValue: ((j['lifetimeValue'] as num?) ?? 0).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'phone': phone,
        'customerNumber': customerNumber,
        'tier': tier,
        'totalOrders': totalOrders,
        'lifetimeValue': lifetimeValue,
      };
}
