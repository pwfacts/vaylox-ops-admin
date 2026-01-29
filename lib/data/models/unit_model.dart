class Unit {
  final String id;
  final String companyId;
  final String name;
  final String code;
  final String? address;

  Unit({
    required this.id,
    required this.companyId,
    required this.name,
    required this.code,
    this.address,
  });

  factory Unit.fromJson(Map<String, dynamic> json) {
    return Unit(
      id: json['id'],
      companyId: json['company_id'],
      name: json['name'],
      code: json['code'],
      address: json['address'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'company_id': companyId,
      'name': name,
      'code': code,
      'address': address,
    };
  }
}
